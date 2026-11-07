# DSH Pocket · OTA 通道

App 从这里读 `android.json`，按 `versionCode` 判断是否有新版本，下载同仓库的 APK 并校验 `sha256`。

发布新版本的步骤：

```bash
./release.sh 0.2.0 path/to/dsh-pocket-0.2.0.apk
git add -A && git commit -m "release 0.2.0" && git push
```
