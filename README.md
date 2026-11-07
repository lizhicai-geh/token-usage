# Codex Token

原生 macOS 大尺寸小组件。液晶面板显示今日 Token、最近 27 周活动和五项账户统计。

面板右上角显示无背景圆环：使用套餐时，中心为菱形，圆环显示周额度剩余比例；使用积分时，中心为堆叠硬币，有可用积分显示完整圆环，不将余额换算为百分比。悬停显示深色圆角单行提示，例如「每周 · 剩余 43%」或「积分 · 9,702」，App 内点击圆环可展开详情。

## 使用

需要 macOS 14 或更新版本，以及能调用 `account/usage/read` 的 Codex CLI。App 可使用 ChatGPT 桌面版随附的 Codex CLI。请先在 Codex 中登录支持账户用量的账号，例如 ChatGPT 账号。

1. 打开 `Codex Token.app`。App 启动时会读取账户用量，也可以点「立即刷新」。
2. 在 macOS 桌面点右键，选择「编辑小组件」。
3. 搜索 **Codex Token**，添加大尺寸小组件。

App 内的热图支持触控板左右滑动，鼠标可使用 Shift＋滚轮，查看账户接口返回的更早历史记录。默认定位到最近一周，悬停格子查看完整日期和用量。桌面小组件保留最近 27 周；点击格子会打开 App，并定位到对应日期。

关掉窗口后，只要 App 还在运行，本机统计、账户用量和额度查询就会各自每分钟刷新一次。退出 App 后，小组件会显示最近保存的快照。WidgetKit 决定桌面上的实际刷新时机。缺失的指标显示「—」。

## 数据

App 通过 stdio 启动 `codex app-server`，完成初始化后调用 `account/usage/read`。每日用量与系统时区的日历日期匹配。摘要字段直接对应累计 Token 数、单日峰值、最长任务用时、最长连续天数和当前连续天数。

额度通过 `account/rateLimits/read` 独立读取，优先使用 `codex` 桶，按 10,080 分钟的窗口识别周额度。来源切换优先采用服务端的 `ordinaryUsageAllowed`；旧版 CLI 缺少该字段时，根据额度窗口耗尽或服务端限制状态推断。账户有积分余额本身不会触发切换。余额缺失显示「—」，明确无积分显示「0」，不限量显示「不限量」。额度读取失败时圆环变为空环，详情显示「—」，不影响 Token 统计；缓存超过 45 分钟时在悬停提示中标记缓存数据。

App 增量读取当前 Codex 数据目录里的会话用量事件，按本机时区统计今天的 Token，并保存每个文件的读取进度以便重启后续读。账户接口缺少当天记录或请求失败时，主数字显示「本机」用量。接口返回当天记录后，主数字自动切回「账户」。热力图和历史统计来自最近一次成功查询的账户数据。

App 在 `~/Library/Application Support/CodexTokenWidget/` 保存本机统计进度和小组件使用的用量快照。小组件图库内的样例带有「预览数据」标记。

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
