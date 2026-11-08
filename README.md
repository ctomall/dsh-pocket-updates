# DSH Pocket · OTA 通道

App 从这里读 `android.json`，按 `versionCode` 判断是否有新版本，下载同仓库的 APK 并校验 `sha256`。

发布新版本的步骤：

```bash
./release.sh 0.2.0 path/to/dsh-pocket-0.2.0.apk
git add -A && git commit -m "release 0.2.0" && git push
```

### 会话导出（0.10.39）

Web 端 `/export` 打的是 ZIP；手机端先做**纯 Markdown**（一次点击、不弹选择器）：

- 入口：会话页右上「⋯」→「导出会话（Markdown）」
- 落盘：`getExternalFilesDir("export")/session-<id前8位>-<时间戳>.md`
- 结构：front-matter（session / host / 导出时间 / 消息数）→ 按 `## 你`、`## 助手`、`### 工具 · <name>`、代码块分段
- 回执：Toast 显示完整路径；文件可用 `adb pull` 取走

样例：`design/shots/0149-export-sample.md`（41 行 / 562 字节，来自 mock 会话）。截图 `0149-export-toast.png`。

**未做**：ZIP 打包、分享 sheet（`ACTION_SEND`）、导出「原始事件流」而非渲染后的消息。
