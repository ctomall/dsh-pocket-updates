#!/usr/bin/env bash
# 用法: ./release.sh <version> <apk路径> [备注]
set -euo pipefail
VER=${1:?version}; APK=${2:?apk}; NOTE=${3:-release $VER}
BASE=$(basename "$APK")
cp "$APK" "$BASE"
SHA=$(sha256sum "$BASE" | cut -d' ' -f1)
SIZE=$(stat -c%s "$BASE")
CODE=$(( $(echo "$VER" | cut -d. -f1) * 10000 + $(echo "$VER" | cut -d. -f2) * 100 + $(echo "$VER" | cut -d. -f3) ))
cat > android.json <<JSON
{
  "version": "$VER",
  "versionCode": $CODE,
  "size": $SIZE,
  "url": "https://raw.githubusercontent.com/ctomall/dsh-pocket-updates/main/$BASE",
  "sha256": "$SHA",
  "notes": ["$NOTE"]
}
JSON
echo "published $VER (code $CODE, $SIZE bytes)"
cat android.json
