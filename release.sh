#!/usr/bin/env bash
# 原子发布：先把包装到两个源并核对 sha256，全部通过才写清单并提交。
# 用法: ./release.sh <version> <apk路径> [备注]
set -euo pipefail

VER=${1:?usage: ./release.sh 0.4.4 path/to.apk "note"}
APK=${2:?apk path}
NOTE=${3:-release $VER}
CDN_DIR=/var/www/tongpin-demo/dsh-pocket
CDN_BASE=https://dsh.ila3.top/demo/dsh-pocket
RAW_BASE=https://raw.githubusercontent.com/ctomall/dsh-pocket-updates/main

cd "$(dirname "$0")"
BASE="dsh-pocket-$VER.apk"
SHA=$(sha256sum "$APK" | cut -d' ' -f1)

# 包里真实的版本号才算数：防止「清单写 0.4.7、包里是 0.4.6」
# 用 sed -n 1p 而不是 head -1：head 提前关闭管道会让 aapt2 收到 SIGPIPE，
# 在 set -o pipefail 下整条 pipeline 返回 141，脚本静默退出（0.10.46/0.10.47 就栽在这）。
BADGING=$(/home/pro/android-sdk/build-tools/34.0.0/aapt2 dump badging "$APK" 2>/dev/null | sed -n '1p')
APK_CODE=$(echo "$BADGING" | sed -E "s/.*versionCode='([0-9]+)'.*/\1/")
APK_NAME=$(echo "$BADGING" | sed -E "s/.*versionName='([^']+)'.*/\1/")
WANT_CODE=$(( $(echo "$VER" | cut -d. -f1) * 10000 + $(echo "$VER" | cut -d. -f2) * 100 + $(echo "$VER" | cut -d. -f3) ))
if [ "$APK_NAME" != "$VER" ] || [ "$APK_CODE" != "$WANT_CODE" ]; then
  echo "   ✗ 包内版本 $APK_NAME ($APK_CODE) 与要发布的 $VER ($WANT_CODE) 不一致，停止发布"
  exit 1
fi
echo "   ✓ 包内版本核对通过：$APK_NAME ($APK_CODE)"
SIZE=$(stat -c%s "$APK")
CODE=$(( $(echo "$VER" | cut -d. -f1) * 10000 + $(echo "$VER" | cut -d. -f2) * 100 + $(echo "$VER" | cut -d. -f3) ))

echo "== 1/4 放置安装包 =="
cp "$APK" "$BASE"
sudo cp "$APK" "$CDN_DIR/$BASE"
sudo chmod a+r "$CDN_DIR/$BASE"
echo "   $BASE  $SIZE bytes  sha256 ${SHA:0:16}…"

echo "== 2/4 核对落盘文件一致（本地权威） =="
LOCAL=$(sha256sum "$CDN_DIR/$BASE" | cut -d' ' -f1)
if [ "$LOCAL" != "$SHA" ]; then
  echo "   ✗ 落盘文件与源不一致：$LOCAL"
  echo "   清单未写入，发布中止"
  exit 1
fi
echo "   ✓ 落盘 sha256 与源一致"
# 镜像可达性属于外部条件：慢或不通不阻断发布，只提示
REMOTE=$(timeout 25 curl -sS "$CDN_BASE/$BASE" 2>/dev/null | sha256sum | cut -d' ' -f1 || true)
if [ "$REMOTE" = "$SHA" ]; then
  echo "   ✓ 镜像已可取到同一字节"
else
  echo "   ! 镜像此刻未确认（可能缓存/链路慢），清单仍会写入"
fi

echo "== 3/5 上传 GitHub Release 资产（分发主源） =="
TOKEN=$(python3 -c "
import re
t=open('/home/pro/.dsh/.credentials.yaml').read()
m=re.search(r'(gh[pousr]_[A-Za-z0-9_]{20,})', t); print(m.group(1) if m else '')
")
REPO=ctomall/dsh-pocket-updates
TAG="v$VER"
RID=$(timeout 30 curl -sS -X POST -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases" \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"$VER\"}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','') or '')" || true)
if [ -n "$RID" ]; then
  ASSET=$(timeout 180 curl -sS -X POST -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/vnd.android.package-archive" \
    --data-binary @"$BASE" \
    "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=$BASE" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('browser_download_url','') or '')" || true)
else
  ASSET=""
fi
if [ -n "$ASSET" ]; then
  echo "   ✓ 资产已上传：$ASSET"
else
  echo "   ! 资产上传失败，退回镜像作主源"
fi

echo "== 4/5 写清单（包已就位才写） =="
cat > android.json <<JSON
{
  "version": "$VER",
  "versionCode": $CODE,
  "size": $SIZE,
  "url": "${ASSET:-$RAW_BASE/$BASE}",
  "fallback": "$CDN_BASE/$BASE",
  "sha256": "$SHA",
  "notes": ["$NOTE"]
}
JSON

# 再写一份 CDN 清单：url 指向 jsDelivr 自己，绕开 github.com:443
python3 - "dsh-pocket-$VER.apk" <<'PYCDN'
import json,sys
m=json.load(open('android.json'))
m['url']="https://cdn.jsdelivr.net/gh/ctomall/dsh-pocket-updates@main/"+sys.argv[1]
m.pop('fallback',None)
json.dump(m,open('android-cdn.json','w'),ensure_ascii=False,indent=2)
PYCDN
sudo cp android.json android-cdn.json "$CDN_DIR/"
sudo chmod a+r "$CDN_DIR/android.json"
echo "   ✓ 清单已写，versionCode $CODE"

echo "== 5/5 同时提交包与清单 =="
git add "$BASE" android.json android-cdn.json
git -c user.name="DSH Pocket" -c user.email="dev@dsh.local" commit -q -m "release $VER: $NOTE"
echo "   ✓ commit $(git rev-parse --short HEAD)（包与清单在同一个提交里）"
echo
echo "下一步：git push —— 清单与包一起上去，不存在'清单有包没有'的窗口"
