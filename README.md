# Codex Token

原生 macOS 大尺寸小组件。液晶面板显示今日 Token、最近 27 周活动和五项账户统计。

## 使用

需要 macOS 14 或更新版本，以及能调用 `account/usage/read` 的 Codex CLI。App 可使用 ChatGPT 桌面版随附的 Codex CLI。请先在 Codex 中登录支持账户用量的账号，例如 ChatGPT 账号。

1. 打开 `Codex Token.app`。App 启动时会读取账户用量，也可以点「立即刷新」。
2. 在 macOS 桌面点右键，选择「编辑小组件」。
3. 搜索 **Codex Token**，添加大尺寸小组件。

关掉窗口后，只要 App 还在运行，就会每 15 分钟查询一次。退出 App 后，小组件会显示最近一次成功获取的快照。WidgetKit 决定桌面上的实际刷新时机。API 缺失的指标或今日用量显示「—」。

## 数据

App 通过 stdio 启动 `codex app-server`，完成初始化后调用 `account/usage/read`。每日用量与系统时区的日历日期匹配。摘要字段直接对应累计 Token 数、单日峰值、最长任务用时、最长连续天数和当前连续天数。

App 在 `~/Library/Application Support/CodexTokenWidget/usage.json` 保存用量和抓取时间。小组件只需读取该目录。小组件图库内的样例带有「预览数据」标记。

App 会在 PATH、常见安装位置及 ChatGPT 桌面版中查找 Codex CLI。如果 CLI 装在自定义位置，可在启动进程的环境中将 `CODEX_TOKEN_WIDGET_CLI` 设为其绝对路径。

## 构建和测试

用 Xcode 16 或更新版本打开 `CodexToken.xcodeproj`，运行 `CodexToken` 方案。也可以从命令行构建本地签名的 App。

```sh
xcodebuild -project CodexToken.xcodeproj -scheme CodexToken \
  -destination 'platform=macOS' -derivedDataPath .build/xcode build
open '.build/xcode/Build/Products/Local/Codex Token.app'
./Scripts/test
```

[Codex App Server 用量接口文档](https://developers.openai.com/codex/app-server)
