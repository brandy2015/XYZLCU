# XYZLCU

**给 AI 智能体用的 macOS 电脑操控工具**：零依赖命令行 + MCP 服务器，做桌面自动化 / GUI 自动化（截屏、鼠标、键盘、辅助功能树），支持 Claude、Codex、ChatGPT、Grok、DeepSeek。

[English](README.md) | **中文**

**当前版本 0.7.1**：全局输入安全门、锁定失败保护与严格单窗口后台控制。见 [CHANGELOG.md](CHANGELOG.md)。

[![License: MIT](https://img.shields.io/github/license/brandy2015/XYZLCU)](LICENSE) [![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](#系统要求) [![Universal: Apple Silicon + Intel](https://img.shields.io/badge/arch-Apple%20Silicon%20%2B%20Intel-blue)](#系统要求) [![Release](https://img.shields.io/github/v/release/brandy2015/XYZLCU)](https://github.com/brandy2015/XYZLCU/releases/latest) [![智能体: Grok · Codex · ChatGPT · Claude · DeepSeek](https://img.shields.io/badge/agents-Grok%20%C2%B7%20Codex%20%C2%B7%20ChatGPT%20%C2%B7%20Claude%20%C2%B7%20DeepSeek-8A2BE2)](#支持的智能体)

**支持的智能体：**[Grok · Codex · ChatGPT · Claude · DeepSeek · ……](#支持的智能体)（任何能跑 shell 命令或接 MCP 服务器的智能体都能用）

**XYZLCU（XYZ Local Computer Use）** 是一个零依赖的 macOS 电脑操控（computer use）命令行工具和 MCP 服务器，用于图形界面 / 桌面自动化。只要能执行 shell 命令，不管是 AI 智能体（Claude Code、Codex、任何会跑命令的 Agent）还是你自己写的脚本，就能看屏幕、点鼠标、打字、按快捷键、读取界面结构并按下按钮。整个工具是一个 Swift 源文件（编译成 `xyzlcu-core`）加一个几十行的 C 小客户端（`xyzlcu`），不用 Python、Node、Homebrew，也不需要任何第三方库。

> **通用，不绑定任何智能体。** XYZLCU 就是一个普通的命令行程序：任何能执行 shell 命令、能读 JSON 输出的智能体都能直接用（**Grok**、**Codex**、**ChatGPT**、**Claude**、**DeepSeek**，以及 Cursor、Gemini CLI、Cline / Roo、Aider、OpenClaw、OpenCode、Trae……），不需要专门的插件或适配层；只支持 MCP 的客户端可以用内置的 `xyzlcu mcp`。不用智能体也行：shell 脚本、快捷指令、cron / launchd 一样能调。见[支持的智能体](#支持的智能体)。

> 借鉴自 Amont Labs 的 [LCU（Local Computer Use）](https://github.com/amontlabs/lcu)，在此致谢（见[致谢](#致谢)）。XYZLCU 是**独立实现**：没有复制 LCU 的代码，也**不需要 ChatGPT / Codex** 桌面应用或其运行时。和 LCU 的速度、用法对比见[性能对比](#性能对比与-lcu)。

<a id="后台--锁定窗口模式v070"></a>

## 单窗口后台控制（Single-window background control）

锁定**一个进程的一个窗口**，让智能体操作它，你继续使用 Mac。`lock` 默认严格模式：只用目标内的辅助功能或直接投递给该 pid 的事件；不移动真实鼠标、不激活/抬升应用、不发送全局 HID 按键、不改共享剪贴板。AX 焦点可以在**目标应用内部**改变。不支持的操作直接拒绝，不会悄悄切到前台输入。

```bash
xyzlcu windows
xyzlcu lock --app TextEdit --window-title "Notes"   # 或 --window-id N；--pid P 可区分同名进程
xyzlcu set-text --role AXTextArea "来自 AX 的文字" --assert-no-contention
xyzlcu type --via pid " — 你好 😀" --assert-no-contention
xyzlcu value --role AXTextArea
xyzlcu menu "Edit|编辑>Select All|全选" --assert-no-contention
xyzlcu screenshot --out /tmp/notes.png --assert-no-contention
xyzlcu lock --status
xyzlcu unlock
```

多窗口应用建议 `lock --pid P --window-id N`。持久锁损坏/无法读取时按拒绝执行处理；应用退出或窗口关闭不会静默清除锁，需要显式 `unlock` 或成功重新 `lock` 恢复。`lock` 失败（包括无效/空选择器、未知选项）会在同一状态文件及守护进程写入 `lock-failed` 标记，之后输入命令返回 `LOCK_FAILED`，直到 `unlock` 或成功 `lock`。选项值为空或缺失属于硬参数错误，不会把下一个选项当作值。锁保存在 `XYZLCU_SOCKET` 同目录（默认 `~/.xyzlcu/lock.json`），使用同一 socket 的 CLI、守护进程与 MCP 共用。显式指定的 app/pid/window 必须与锁一致。单条命令可用 `--background --app A [--window-title T]`。锁定下的坐标/AX 中心点，以及每张指定窗口截图的原点/差异区域统一是**窗口相对点坐标**，左上角 `(0,0)`；图像像素仍需按返回的比例换算。

MCP 先调 `lock`：`{"app":"TextEdit","window_title":"Notes"}` 或 `{"pid":1234,"window_id":5678}`；再调 `set_text`：`{"role":"AXTextArea","text":"你好","assert_no_contention":true}`、`type_text`：`{"text":"世界","via":"pid","assert_no_contention":true}` 和 `screenshot`：`{}`。可能发送全局输入的工具提供 `allowGlobal`（布尔值，默认 `false`），对应 `--allow-global`；`allow_foreground`、`assert_no_contention` 对应各自 CLI 选项；`lock` 支持 `unsafe:true` 和 `unlock:true`。专用工具缺少某个选项时，可用通用 `xyzlcu` 工具的 CLI 参数。

| 操作 | 严格后台路线 | 证据 / 限制 |
|---|---|---|
| `set-text`、`insert`、`type` | `ax-focus-value` → `ax-selected-text` → 支持时 `pid-keys`；`type --via pid` 强制 pid Unicode | 先 AXFocused / 应用 AXFocusedUIElement，再写值并读回；严格模式不回退菜单粘贴 |
| `click`、`click-el`、`press`、`select` | `ax-focus` / `ax-press` / `ax-select` / `ax-showmenu`，再按支持情况 `pid-mouse` | 窗口相对命中；可核对 AX 状态/值变化，投递成功不等于送达 |
| `key`、`menu` | 安全编辑菜单/默认/取消按钮，或 `pid-keys` | 严格模式仅放行 Edit > Select All / Undo / Redo（编辑 > 全选/撤销/重做）；新建/打开/退出及作用域不明菜单拒绝 |
| `scroll`、`scroll-to` | `ax-scrollbar` / AXScrollToVisible / 有界 AX 遍历，再 `pid-scroll` | 应用可能忽略 pid 事件，需核对 AX 变化 |
| `screenshot` | `sck-window`：ScreenCaptureKit `SCContentFilter(desktopIndependentWindow:)` | 单独截目标窗口；被遮挡时不从桌面裁图 |
| `move`、`drag`、`open`、`activate`、`hide`、`movewin`、`replay` | 拒绝 | 必须单条命令显式放行；无自动前台回退 |

pid 鼠标投递把窗口点换成事件所需全局位置，填入窗口号并保留 down/up 按住时间，使用公开的 `CGEvent.postToPid`。它是进程定向投递，不能保证每个应用都按预期窗口处理；不依赖私有 SLEvent/PSN 投递接口。`route` 写明实际路线；`verified:true` 表示可用的状态/值核对通过，`verified:false` 加 `reason` 表示效果未获证实。不能把 post 成功当作点击成功。有界 AX 树变化仅证明观察到变化，不证明命令语义已完成。AX 写入已被接受但读回不明确时会停下，避免重复输入。

每个 JSON 对象带 `frontmostBefore`、`frontmostAfter`、`contention`（鼠标位置或前台 pid 变化）；旧的列表/纯文本/二进制输出保持格式。`--assert-no-contention` / MCP `assert_no_contention:true` 检测到争用就失败。这只是前后快照，并非连续监测：无法发现短暂切换又切回，也无法区分用户自己移动鼠标。目标应用可能因 AX 动作自行激活；工具报告观察到的变化，但不能撤销已执行动作。异步 `press` 和下拉菜单 worker 的父进程结果只覆盖派发时快照；worker 完成、应用延迟效果和之后的争用不在监测范围，完成后应重新观察/读回。保证的是投递策略，不能替其他应用保证内部行为。

**全局输入安全门（v0.7.1）。** 未锁定时，全局键盘输入（`events-hid` / session tap）、HID 鼠标点击/移动/拖拽/滚动，以及应用激活（含打开到前台、隐式激活），必须显式传入本条命令的 `--allow-global`，或用 `--app <名称|bundleId>` / `--pid <pid>` 指定已经处于前台的目标。每批事件发送前立即核对前台目标，序列中前台改变就停止并报错。拒绝决策发生在创建全局 CGEvent 之前：非零退出，JSON 含 `ok:false`、`code:"GLOBAL_INPUT_REFUSED"` 及实际前台应用。`--expect-front`、`--allow-foreground`、`XYZLCU_ALLOW_GLOBAL=1` 都不能放行未锁定的全局输入。自动路线选择同样必须通过安全门，AX-only 和 `postToPid` 不受影响。MCP 执行相同策略，`allowGlobal` 默认为 `false`。

**显式退出保护与兼容性变化。** `--allow-global` 只对**本条命令**放行全局 HID / 剪贴板，仍受当前锁策略约束。`--allow-foreground` 只对**本条命令**放宽锁定时的前台路线，主动退出无争用约束；未锁定的全局动作仍须通过上面的安全门。`lock --unsafe` 持续放宽锁策略，直到重新锁定或解除。普通 AX/pid 操作不需要这些选项。严格锁下 `--no-lock` 必须同时给显式放行选项。旧脚本若依赖剪贴板回退、任意应用菜单、激活、拖拽、整屏截图或 `--no-lock`，需调整。拒绝时返回明确 JSON，例如：

```json
{"ok":false,"error":"global input refused: no lock and no verified frontmost target; pass --app/--pid (must be frontmost) or --allow-global; frontmost: Terminal (pid 1234)","code":"GLOBAL_INPUT_REFUSED"}
```

**隐含副作用审计（严格锁）。**

| 命令 / 路线 | 全局或隐含副作用 | 严格策略 |
|---|---|---|
| `type/key --via events`、点击回退 | 全局 HID / 前台键盘 | 拒绝，不静默回退 |
| `type/set-text/insert --via paste`、`cmd+c/x/v` | 即使用 AX 菜单粘贴，也改共享剪贴板 | 无 `--allow-global` 则拒绝；普通 AX 输入不回退粘贴 |
| `move`、`drag`、普通鼠标路线 | CGWarpMouse / 全局按下、抬起、滚轮 | 拒绝；点击/滚动走窗口 AX/pid |
| `open`、`activate`、`hide`、`movewin`、`menu --activate` | 激活、抬升、可见窗口布局改变 | 无前台放行则拒绝 |
| `menu`、快捷键菜单查找、`press/select` 菜单 | 应用级操作可能逃出文稿或新开对话框 | 限窗口 AX；安全编辑菜单白名单；作用域不明则拒绝 |
| `check`、`check --probe`、健康检查 | 权限 / 历史事件监听元数据 | 不创建、不发送全局输入事件；probe 请求也保持被动 |
| `request`、`request --open` | 权限弹窗 / 打开系统设置 | 严格锁下拒绝；先授权再锁定 |
| `replay` | 录制的全局键鼠事件 | 无显式放行则拒绝 |
| `screenshot` | 整屏或桌面裁剪可能泄露其他应用 | 只截锁定窗口；冲突的 display/region/window 拒绝 |
| AX 聚焦/写值/按下/选择 | 目标内焦点和应用自定义动作 | 不激活、不发 HID；核对值/状态及 contention |

**如实说明的限制。** 某些 WebView、游戏、Electron/Chromium 自绘界面和后台文稿快捷键忽略进程事件；App Nap 也会延迟执行。WKWebView 常需先 AX 聚焦，再写值或 pid 输入。AX 聚焦不等于把插入光标放在点击位置。安全输入框可能拒绝读写，无法核对。悬停专属 UI、拖放没有严格路线。其他进程托管的系统/打开/存储面板超出锁范围，包括 TCC 弹窗。目标关闭或失效就失败，不改找另一个窗口。

ScreenCaptureKit 可以截被覆盖窗口，以及系统仍提供背板内容的部分屏外窗口。最小化或其他 Space 的窗口可能不在列表里、内容旧、空白或无法捕获，取决于 macOS/应用；工具不会为截图取消最小化、切 Space 或激活应用。指定窗口截图支持 macOS 13+（macOS 13 用单帧 SCStream，macOS 14+ 用 SCScreenshotManager/实时窗口流），窗口路线不可用就失败；窗口目标拒绝 `--cli`，不回退整屏。`windowFrame` 单独提供全局窗口范围；`originX/originY` 和 `diff.rects` 为窗口相对坐标。检查 `route`、`method` 及图像。TCC 权限属于**负责启动它的宿主应用**（终端、智能体宿主或守护进程启动者），用 `whoami` / `check` 确认，在那里授予辅助功能和录屏并重启宿主。

在已授权 Mac 手工验收：`./scripts/bg_selftest.sh`。保持另一个应用（如终端）在前台，鼠标静止。脚本用 `open -g` 打开临时 TextEdit 文稿，隔离 socket/锁，直接调用已构建 core，核对 AX 写值、pid Unicode 输入、AXSelectedTextRange 全选及 AXSelectedText 读回、单窗口截图、文稿内容和前台/鼠标不变。它以唯一文件名轮询约 10 秒定位文稿，结束时仅通过该窗口的 AX 关闭按钮清理，不退出 TextEdit。它不发送全局输入，输出 PASS/FAIL/SKIP 表并保留产物；后台编辑菜单被禁用属于预期限制，记为 SKIP，全选由独立 AX 操作验证。编译与无权限自测通过不代表真实应用已验收。

## 为什么选 XYZLCU（核心优势）

下面保留的是 v0.5.0–0.6.1 历史测速，不代表 v0.7.1：新版点击默认增加 75 毫秒悬停和 60 毫秒按住时间，按键默认按住 30 毫秒。数字都是在同一台 Apple Silicon Mac（macOS 26+）上实测的中位数，测法和完整数据见[性能对比](#性能对比与-lcu)。LCU 的数字是 0.4.2 那一轮在同一台机器上测的（LCU 0.13.4）。LCU 也有比 XYZLCU 强的地方，同样写在[性能对比](#性能对比与-lcu)里。

- 🔌 **支持 Grok、Codex、ChatGPT、Claude、DeepSeek** 等主流智能体：能跑 shell 命令就能用，只认 MCP 的客户端用内置的 `xyzlcu mcp`。已实测：Grok Bot、Codex CLI、OpenCode、MCP 客户端（完整握手）、Python / Node、shell 脚本；ChatGPT、Claude、DeepSeek 走同一接口，兼容（还没亲自实测）。见[支持的智能体](#支持的智能体)。
- 🪟 **单窗口后台控制**（v0.7.0）：严格 `lock` 把操作与截图限制在一个窗口，默认拒绝全局输入、剪贴板改动及激活。见[策略、路线和限制](#单窗口后台控制single-window-background-control)。
- ⚡ **快**：开着守护进程时，`xyzlcu` 是一个很小的 C 程序，一次调用约 **3 毫秒**。

  | 操作 | XYZLCU | LCU |
  |---|---:|---:|
  | 点击 | **6 毫秒** | 140 毫秒 |
  | 输入英文 `abc` | **5 毫秒** | 43 毫秒 |
  | 输入中文 `你好abc` | **7 毫秒** | 约 9 秒 |
  | 按键 | **4 毫秒** | 14 毫秒 |
  | 窗口截图 | **6 毫秒**（第一次约 25 毫秒） | 51 毫秒 |
  | 列出应用 | **3 毫秒** | 17 毫秒 |

- 🧠 **截图不落盘、只看变化**：`--base64` / `--stdout` 直接在内存里出图，`--fast` 半尺寸 JPEG 约 **9 毫秒**。`--diff` 只返回变化的那一块，画面没变时只回一小段 JSON（3–4 毫秒，没有图片），适合智能体反复「看一眼」。
- 🛣 **先聚焦再写值的 AX 输入**：`set-text`（旧名 `settext`）先 AX 聚焦、写值再读回；严格后台输入可用 AXSelectedText 或 pid Unicode，不回退剪贴板。
- 🪙 **省 token**：`ax --compact` 只列可以操作的控件，一行一个，带编号和中心点；再用 `click-el --ref N` 按编号点。访达加菜单栏的控件树 **13.7 KB → 0.4 KB**，文本编辑窗口 740 → 243 字节。
- 🧰 **功能全**：鼠标位置和移动、拖拽、滚动、整屏 / 窗口 / 区域截图、窗口列表、移动和调整窗口、显示器列表、后台按菜单、控件树和按控件、等控件出现、录制和回放。LCU 在 Mac 上没有鼠标位置 / 移动、整屏截图和窗口列表这几项。
- 🔒 **安全**：
  - 锁屏时拒绝键鼠操作，防止把字打进锁屏密码框。
  - 录制器只监听、不拦截输入；安全输入（密码框）开启时和锁屏时不录按键。
  - 不做反检测：不伪装成真人，不绕过验证码或机器人检测。
- 🏠 **隐私**：只在本机运行，**不联网、没有遥测**。代码里唯一的套接字是守护进程本机的 Unix 套接字；截图/启动应用使用系统的 `screencapture` 和 `open`，异步 AX 动作可启动另一个 xyzlcu-core 工作进程。录制文件权限 0600，只存本机。
- 📦 **零依赖**：两个文件（`xyzlcu` + `xyzlcu-core`），通用二进制，Apple Silicon 和 Intel 都能跑，macOS 13+。不需要 ChatGPT 桌面应用，也不需要 Python、Node、Homebrew 或任何第三方库。
- 📖 **开源**：MIT 许可，中英文文档，测速脚本在 `scripts/`，结果可以自己复现。

## 功能

- **v0.7.1**：未锁定全局输入安全门、锁定失败标记、被动诊断及 MCP `allowGlobal:false`；严格单窗口后台控制、`--pid`、可核对的 `set-text`、深层 `press` / `select`、AX 滚动 / 文字等待、争用断言与宿主权限诊断 MCP。安全变化见开头章节。

- 📸 **截屏**：截整块屏、单个窗口（`--window`）或一块区域（`--region`），可缩小；`--fast` 一键出小 JPEG；会输出点坐标与像素的换算关系
- 🧠 **内存截图**（v0.4.2）：`--base64` / `--stdout` 直接在内存里出图，不写文件；守护进程按需保持截图流，重复截同一个窗口约 20 毫秒
- 🚀 **v0.5.0 更快**：C 小客户端（空调用约 3 毫秒）、守护进程启动时预开主屏截图流（`--fast` 约 9 毫秒）、并行 PNG 编码（全尺寸 PNG 171 → 31 毫秒）、JPEG / HEIC、`--diff` 只返回变化的区域、MCP `batch` 一次多步
- 🪟 **窗口锁**：CLI/MCP 共用持久目标；v0.7.0 收紧 v0.6.1 原有后台模式，拒绝不安全回退。
- ⚡ **v0.6.0**：守护进程自己维护应用表（`apps` 10 → 3 毫秒，`ax` 27 → 5 毫秒，`find` 21 → 8 毫秒）、没被挡住的窗口直接从主屏流里裁（第一次截窗口 114 → 25 毫秒）、`ax --compact` + `click-el --ref` 省 token、升级后自动重启旧守护进程
- 🖱 **鼠标**：单击、右键、双击、移动、拖拽、滚动
- ⌨️ **键盘**：直接输入 Unicode 文字（中文、emoji 都行，不经过输入法），支持组合键（`cmd+shift+4`）
- 🌳 **辅助功能树**：导出任意应用窗口的控件树（角色、标题、值、坐标）；`find` 按角色/标题直接返回坐标和中心点，`click-el` 一步找到并按下，`wait` 等控件出现或消失
- 🪟 **应用与窗口**：列出、打开、激活、隐藏应用；列出窗口；移动和调整窗口大小；列出显示器
- 🛣 **多条输入路径**：辅助功能写值、键盘事件、直接投递进程、菜单粘贴，输出实际路线并在可读时核对。健康检查和 `check --probe` 只读取元数据，不发送输入。
- ⏺ **录制 / 回放**：只监听地录下键鼠操作（不拦截输入，密码框和锁屏时不录按键），按原节奏回放
- 🔒 **锁屏保护**：屏幕锁定时拒绝键鼠操作，防止把字打进锁屏密码框
- 📊 **实测数据**：和 LCU 的逐项速度对比见[性能对比](#性能对比与-lcu)，脚本可复现
- ⚡ **常驻守护进程**：`xyzlcu serve --background` 之后，命令自动转发给它，省掉进程启动开销，同时保留权限和安全检查；历史查询类命令为 2–10 毫秒
- 🔌 **MCP 服务器**（v0.4.2）：`xyzlcu mcp` 走 stdio，给只支持 MCP 的客户端（如 Claude Desktop），截图直接作为图片返回
- 🧾 **输出好解析**：结果是 JSON 或一行 `ok`，出错时返回明确的退出码

## 快速开始（3 步）

**1. 安装**（二选一）

```bash
# A. 下载编译好的 universal 二进制（Apple Silicon + Intel）
mkdir -p ~/.local/bin && curl -fsSL https://github.com/brandy2015/XYZLCU/releases/latest/download/xyzlcu-macos-universal.zip -o /tmp/xyzlcu.zip \
  && unzip -o /tmp/xyzlcu.zip -d ~/.local/bin && chmod +x ~/.local/bin/xyzlcu ~/.local/bin/xyzlcu-core \
  && xattr -d com.apple.quarantine ~/.local/bin/xyzlcu ~/.local/bin/xyzlcu-core 2>/dev/null; rm -f /tmp/xyzlcu.zip

# B. 从源码编译（需要 Xcode 或 Command Line Tools）
git clone https://github.com/brandy2015/XYZLCU.git && cd XYZLCU && ./build.sh --install
```

把 `~/.local/bin` 加到 PATH（zsh）：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

**2. 授权**：在「系统设置 > 隐私与安全性」里，给**启动命令的那个 App** 打开「辅助功能」和「屏幕与系统录音」，详见[权限设置](#权限设置)。

**3. 检查**

```bash
xyzlcu check
# {"accessibility": true, "screenRecording": true, "screenLocked": false, "responsibleProcess": "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", ...}
```

两项都是 `true` 就可以用了。

也可以用 Swift Package Manager 编译：`swift build -c release`，产物在 `.build/release/`（`xyzlcu-core` 和 `xyzlcu` 要放在同一个目录）。

> **两个文件**（v0.5.0 起）：`xyzlcu` 是很小的 C 客户端，有守护进程时直接把命令转发过去（约 3 毫秒）；没有守护进程，或者是 `mcp` / `serve` / `record` / `replay` / 帮助，就 `exec` 同目录下的 `xyzlcu-core`（真正干活的 Swift 程序；也可以用 `XYZLCU_CORE` 指定路径）。两者都要放在 `~/.local/bin`。`macctl` 软链接照旧指向 `xyzlcu`。

## 系统要求

- macOS 13 Ventura 及以上（编译目标 `macos13`；历史回归覆盖 macOS 27）；macOS 13 窗口截图用单帧 SCStream，该系统分支仍需手工运行验收。
- Apple Silicon 或 Intel（`build.sh` 和 Release 产出 universal 二进制）
- 从源码编译需要 Xcode 或 Command Line Tools（`xcode-select --install`）

## 权限设置

macOS 的隐私权限（TCC）**不是授给 xyzlcu 本身**，而是授给启动它的「负责 App」。比如你在「终端」里运行，要授权的是「终端」；AI 智能体通过某个 App 执行命令时，要授权的是那个 App。

**查出该给谁授权：**

```bash
xyzlcu whoami
```

它会列出父进程链和 `responsiblePath`。`responsiblePath` 指向的 `.app` 就是要打开开关的那个。

| 运行方式 | 通常要授权的 App |
|---|---|
| 终端 | 终端（Terminal.app） |
| iTerm2 | iTerm |
| VS Code / Cursor 内置终端 | Visual Studio Code / Cursor |
| Claude Code、Codex CLI | 运行它的终端 App |
| 桌面 AI 助手远程执行命令 | 该助手的 App（看 `whoami`） |

**打开开关：**

1. 「系统设置 > 隐私与安全性 > **辅助功能**」：打开上面那个 App 的开关。点击、打字、按键、读取界面树、按按钮、移动窗口都要用。
2. 「系统设置 > 隐私与安全性 > **屏幕与系统录音**」（旧版系统叫「屏幕录制」）：打开同一个 App 的开关。截图要用。
3. 列表里没有这个 App 的话，点「+」从「应用程序」里添加。
4. 改完后**退出并重新打开那个 App**，然后运行 `xyzlcu check` 确认。

`check` 保留旧的 `responsibleProcess` 路径字符串，另加 `responsibleProcessInfo`（`pid`、`name`、`path`、`bundleId`）。MCP 权限错误会指出应授权的宿主和相应开关；授权后要重启那个宿主。终端获得授权不代表另一个 MCP 宿主也有权限。

`xyzlcu request` 弹出系统授权窗口；加 `--open` 打开首个缺失权限的设置页，也可用 `--permission accessibility|screen-recording|input-monitoring` 指定。录制和显式事件探测需要「输入监控」。XYZLCU 不修改 TCC 数据库，也不绕过权限。

## 命令一览

| 命令 | 说明 | 示例 |
|---|---|---|
| `check [--probe]` | 权限、锁屏状态、各输入路径是否可用（见[多条输入路径](#多条输入路径键盘被卡住时)） | `xyzlcu check` |
| `request [--open] [--permission P]` | 请求权限，打开缺失或指定的隐私设置页 | `xyzlcu request --open --permission accessibility` |
| `whoami` | 进程链与负责 App | `xyzlcu whoami` |
| `version` | 版本号 | `xyzlcu version` |
| `screenshot [path] [--scale S] [--display N] [--format png\|jpg\|heic] [--quality Q]` | 截屏。格式看 `--format`，没给就看文件扩展名，都没有时 PNG（`--fast` 和只在内存里出图时 JPEG） | `xyzlcu screenshot /tmp/s.jpg --scale 0.5` |
| `screenshot … --fast` | 快速截图：JPEG、质量 0.6、缩放 0.5 | `xyzlcu screenshot --fast` |
| `screenshot … --window "App" [--title T]` | 只截某个应用的窗口（默认它最前面的窗口） | `xyzlcu screenshot /tmp/w.png --window Safari` |
| `screenshot … --window-id N` | 按 `windows` 列出的 id 截某个窗口 | `xyzlcu screenshot /tmp/w.png --window-id 1234` |
| `screenshot … --region x,y,w,h` | 只截一块区域（全局点坐标） | `xyzlcu screenshot /tmp/r.png --region 100,100,400,300` |
| `screenshot … --base64` | 不写文件，图片以 base64 放在 JSON 的 `base64` 字段（没给路径时默认 JPEG） | `xyzlcu screenshot --fast --base64` |
| `screenshot … --stdout` | 不写文件，图片原始字节写到 stdout，元数据 JSON 写到 stderr | `xyzlcu screenshot --window Safari --stdout > w.jpg` |
| `screenshot … --diff` | 只返回和上一张（同一目标、同一缩放）相比变了的区域：输出 `diff.rects`（窗口截图为窗口相对点坐标，其余为全局点坐标）、`changedPercent`，图片裁到变化范围；没变化时不出图。只在守护进程 / MCP 里有效 | `xyzlcu screenshot --fast --diff --base64` |
| `screenshot … --out 路径` / `--timing` | `--out` 同时写一份文件；`--timing` 输出各阶段耗时 `timingMs` | `xyzlcu screenshot --fast --base64 --timing` |
| `displays` | 列出显示器及其坐标范围 | `xyzlcu displays` |
| `click x y [--right] [--double] [--hold ms]` | 点击，默认悬停 75 毫秒后按住 60 毫秒 | `xyzlcu click 500 300 --hold 90` |
| `move x y` | 移动鼠标 | `xyzlcu move 800 600` |
| `drag x1 y1 x2 y2` | 按住左键拖动 | `xyzlcu drag 100 100 400 400` |
| `scroll dx dy` | 滚动，单位是行，正 dy 向上 | `xyzlcu scroll 0 -5` |
| `cursor` | 当前鼠标位置 | `xyzlcu cursor` |
| `type "文字" [--app "App"] [--window 标题] [--via auto\|ax\|events\|pid\|paste]` | 输入 Unicode 文本，输出 JSON（`path` = 实际走的路、`verified` = 是否读回核对过）。默认 auto 自动挑路 | `xyzlcu type --app TextEdit --window 笔记 "你好 😀"` |
| `insert "App" [定位] "文字"` | 用辅助功能在焦点处插入文字（写 AXSelectedText），不经过键盘事件，写完读回核对 | `xyzlcu insert TextEdit --window 笔记 "你好"` |
| `set-text "App" [定位] "文字"` | 用 AX 聚焦、整体替换 AXValue 并读回核对；兼容旧名 `settext` | `xyzlcu set-text --pid 1234 --role AXTextArea "你好"` |
| `value "App" [定位]` | 读回元素的值（默认焦点元素），用来核对输入结果 | `xyzlcu value TextEdit` |
| `menu "App" "菜单>菜单项" [--window 标题] [--activate]` | 按菜单路径按下菜单项（AXPress，默认不激活应用），代替快捷键；每级可写多个候选 `文件\|File` | `xyzlcu menu TextEdit "文件>新建"` |
| `key 组合… [--app "App"] [--via auto\|events\|menu\|pid]` | 按键 / 组合键，可以一次多个；输出 JSON，每个键实际走的路。事件流卡住时自动改按对应菜单项 | `xyzlcu key cmd+s` · `xyzlcu key --app TextEdit cmd+a` |
| `apps` | 正在运行的图形界面应用 | `xyzlcu apps` |
| `open "App"` | 打开应用 | `xyzlcu open "TextEdit"` |
| `activate "App"` | 切换到前台 | `xyzlcu activate Finder` |
| `hide "App"` | 隐藏应用（相当于 cmd+h） | `xyzlcu hide TextEdit` |
| `windows [--all]` | 屏幕上的窗口（所属应用、标题、位置） | `xyzlcu windows` |
| `movewin "App" x y [--w W --h H] [--title T]` | 移动 / 缩放窗口并置前 | `xyzlcu movewin "Safari" 200 100 --w 1200 --h 800` |
| `ax ["App"] [--depth N] [--menu]` | 导出界面控件树 | `xyzlcu ax TextEdit --depth 6` |
| `ax ["App"] --compact [--menu] [--text] [--max 300]` | 只列可操作控件，带编号、中心点、enabled 和 focused，给智能体用 | `xyzlcu ax TextEdit --compact` |
| `find "App" [--role R] [--title T] [--contains] [--index N\|--all] [--window T] [--menu]` | 找控件，返回 role、title、frame、center、enabled、focused；找到指定项就停 | `xyzlcu find TextEdit --role AXButton --title 保存` |
| `click-el "App" --role R --title T [--click] [--right] [--double]` | 找到控件并按下（AXPress，不行就点中心） | `xyzlcu click-el TextEdit --role AXButton --title 保存` |
| `click-el --ref N ["App"]` | 按上一次 `ax --compact` 的编号按下控件（需要守护进程） | `xyzlcu click-el --ref 3` |
| `press "App" [--role R] [--title T] [--nth N] [--list] [--async]` | 深层包含匹配标题、描述、值和子控件文字后 AXPress；下拉框自动异步 | `xyzlcu press XYZStudio --role AXRadioButton --title "My Models" --nth 1` |
| `wait "App" --title T [--role R] [--timeout 秒] [--gone]` | 等控件出现（或 `--gone` 消失），默认 5 秒超时 | `xyzlcu wait TextEdit --role AXSheet --timeout 3` |
| `select "App" --popup T --item T [--nth N] [--timeout s]` | 异步打开原生下拉框，再按菜单项 | `xyzlcu select XYZStudio --popup Model --item "Local model"` |
| `scroll-to "App" --role R --title T [--index N]` | 用 AXScrollToVisible、聚焦或有限次滚动条遍历使控件可见 | `xyzlcu scroll-to XYZStudio --role AXDisclosureTriangle --title Documents` |
| `scroll dx dy --ax [--pid N] [--role R] [--title T]` | 改所在滚动区的滚动条值，不移动鼠标 | `xyzlcu scroll 0 -5 --ax --pid 1234 --role AXTextArea` |
| `wait-text "App" "文字片段" [--timeout s] [--gone]` | 轮询静态文字和 AX 值，等文字出现或消失 | `xyzlcu wait-text XYZStudio "Complete" --timeout 60` |
| `observe ["App"] [--pid N] [--max N]` | 纯文字返回前台应用、目标窗口和简洁 AX 摘要 | `xyzlcu observe --pid 1234` |
| `selftest` | 无需 GUI 权限的解析、匹配和输入策略自检 | `build/xyzlcu-core selftest` |
| `wait 毫秒` / `sleep 毫秒` | 等待固定时间 | `xyzlcu sleep 300` |
| `taps` | 列出系统事件监听（排查输入卡顿/丢失），`blocking` 标出可疑的 | `xyzlcu taps` |
| `record [--out f.jsonl] [--duration 秒] [--no-moves]` | 只监听地录制键鼠，见[录制与回放](#录制与回放) | `xyzlcu record --duration 30` |
| `replay f.jsonl [--speed N] [--no-keys] [--force]` | 回放录制 | `xyzlcu replay rec.jsonl --no-keys` |
| `run [--continue-on-error] '命令; 命令; …'` | 一次执行多条命令（`;` 或换行分隔） | `xyzlcu run 'click-el TextEdit --title 保存; wait TextEdit --role AXSheet; key return'` |
| `batch [--continue-on-error] [文件]` | 从文件或 stdin 逐行读命令执行 | `printf 'type a\nkey return\n' \| xyzlcu batch` |
| `serve [--background\|--status\|--stop]` | 启动 / 后台启动 / 查看 / 停止常驻守护进程，见[守护进程](#守护进程) | `xyzlcu serve --background` |
| `mcp` | 以 stdio MCP 服务器运行，见[MCP 服务器](#mcp-服务器) | `xyzlcu mcp` |

补充：

- **应用名**可写本地化名、英文名或 bundle ID。AX 命令（`ax`、`find`、`press`、`click-el`、`set-text`、`value`、`menu`、`scroll`、`scroll-to`、`wait`、`wait-text`、`lock`）也可用 `--pid N` 代替应用名。同名进程优先选有屏幕窗口的那个，结果报告所选 pid；有 watchdog/辅助进程时建议明确指定 pid。
- **按键名**：`a–z`、`0–9`、常用符号、`return`/`enter`、`tab`、`space`、`delete`/`backspace`、`forwarddelete`、`esc`、`up`/`down`/`left`/`right`、`home`/`end`/`pageup`/`pagedown`、`f1–f12`。修饰键：`cmd`、`shift`、`opt`/`alt`、`ctrl`、`fn`。
- **`ax` 输出格式**：`角色(子角色) title="…" desc="…" value="…" id="…" [x,y 宽x高]`。中括号里的就是点坐标，中心点 = `(x + 宽/2, y + 高/2)`。
- **`find` / `click-el` / `wait`**：`--title` 也可以写成第二个参数（`xyzlcu find TextEdit 保存`）。标题按完全匹配（不区分大小写）比对 title、description、value 和 identifier，加 `--contains` 改为包含匹配。先搜当前焦点窗口，再搜其他窗口；`--menu` 才搜菜单栏。找到第 `--index` 个（默认第 1 个）就立刻停止，不会遍历整棵树。找不到返回退出码 4。
- **`click-el`** 先 AXPress，不行再点中心；`--click`、`--right`、`--double` 强制点击。**`press`** 深层搜索并包含匹配子控件文字，只走 AX；`--list` 查看带编号的候选，`--nth N` 选第 N 项（从 1 开始）。`--async` 适用于菜单保持打开的动作，AXPopUpButton / AXMenuButton 自动异步。
- **`wait "App" …`** 先 20 毫秒检查一次，间隔逐步加到 250 毫秒，超时返回退出码 4。
- **`type` / `key --app "App"` 或 `--pid N`**：把 AX/菜单和按键投递限定到该进程。WebView 可能忽略 pid 事件，仍要确认目标窗口并读回值；任何全局回退都必须通过安全一节的前台检查。
- **`run` / `batch`**：引号规则和 shell 一样（`"…"`、`'…'`、`\` 转义），`#` 开头的行是注释。默认遇到第一个出错的命令就停止，退出码同那条命令，错误信息会写明是第几步；加 `--continue-on-error` 则继续执行后面的步骤，最后返回最后一个出错步骤的退出码（全部成功为 0）。里面可以混用 `find`、`click-el`、`wait`、`sleep`。
- **`--hold ms`**：只覆盖本次命令的按下到抬起时间（0–60000 毫秒），默认点击 60、按键 30。`XYZLCU_CLICK_HOLD` 改点击默认值，不影响悬停等待；守护进程不会把本次覆盖留给下一条请求。
- **`--delay N`**：鼠标/键盘事件之间的间隔（毫秒，默认 2）。个别应用反应慢、丢字时调大，例如 `xyzlcu --delay 20 type …` 或 `XYZLCU_DELAY=20`。
- **截图**：指定/锁定窗口使用 ScreenCaptureKit 单窗口捕获，不裁桌面、不回退全局截图。未指定窗口的整屏/区域捕获在旧系统或 `--cli` 下保留系统 `screencapture` 回退。`method` 标明路线；每次指定窗口时 `originX/originY` 为窗口相对坐标，整屏/区域时为全局坐标。

## 多条输入路径（键盘被卡住时）

有时系统里某个进程的键盘事件监听（event tap）卡住了：键盘事件发出去迟迟不到应用，甚至排队到很久以后才一起冒出来，鼠标却正常。v0.4.0 起，`type`、`key` 会先检查事件流是否健康，再挑一条走得通的路，并在输出 JSON 的 `path` 里写明实际走的是哪条。 以下前台路线描述未锁定行为；严格锁优先，不允许剪贴板/HID 回退，并限制应用菜单。

**健康检查**

- 读系统事件监听列表（`CGGetEventTapList`）：主动拦截（不是只监听）、平均延迟超过 1000 毫秒（`XYZLCU_TAP_THRESHOLD_MS` 可改）的监听算可疑。
- 这些统计是历史值，平均延迟高不能证明 Siri 等进程此刻拦住输入。普通检查输出 `suspectedTapStats`，不会发送任何合成探测事件。
- 健康检查、`check`、`check --probe` 均为被动诊断，不创建、不发送任何全局键鼠输入。监听统计是诊断元数据，不代表事件已成功送达；普通守护进程状态缓存 1.5 秒。
- `XYZLCU_EVENTS_HEALTH=bad` / `good` 强制当作卡住 / 正常，用来测试备用路径（守护进程模式下也生效，客户端会把这些环境变量随请求转发过去）。

**各条路**

| `path` | 做法 | 经过 HID 事件流的监听？ | 应用要在前台？ | 核对 |
|---|---|---|---|---|
| `ax-focus-value` | 先设 AXFocused，再写 AXValue 并读回；保持前台应用 | 否 | 否 | 读回 AXValue |
| `ax-selected-text` | 辅助功能写焦点元素的 `AXSelectedText`（在光标处插入） | 否 | 否 | 读回 `AXValue` |
| `events-hid` | CGEvent 发到系统 HID 事件流（`type` / `key` 不带 `--app`） | 是 | 是 | 300 毫秒内读回 |
| `events-pid` | `CGEventPostToPid` 直接投递给应用进程（带 `--app`，或 `--via pid`） | 否 | 否 | 600 毫秒内读回 |
| `paste-menu` | 文字放进剪贴板，AXPress 应用的「编辑>粘贴」菜单项，核对后恢复剪贴板 | 否 | 否 | 读回 |
| `menu` | `key` 专用：在菜单栏里找快捷键相同的菜单项并 AXPress（如 `cmd+a` → 「编辑>全选」） | 否 | 见下文 | — |
| `ax-menu` | `menu` 命令：按菜单路径 AXPress | 否 | 见下文 | — |

**`type --via auto`（未锁定默认；严格锁排除全局/粘贴路线）**

- 事件流正常：焦点是标准文本框（`AXTextField` / `AXTextArea` / `AXComboBox` / `AXSearchField`）时走 `ax`，否则仅在通过全局输入安全门后走 `events`；拒绝时不会静默向前台投递。
- 事件流卡住：依次试 `ax` → `pid` → `paste`，每一步都读回核对，没生效才换下一条。卡住时**不会**用 `events-hid`，那些按键会排队，事件流恢复后突然打出来。
- 读不到输入框内容、没法核对时，就停在当前这条路，不再换路，避免同一段文字被输入两次。
- 所有路都没生效：退出码 4，错误里列出每条路的结果（`tried`）。
- `paste` 没核对成功时**不恢复剪贴板**（输出 `clipboardRestored: false`），避免排队中的粘贴贴出旧内容。
- `--via ax|events|pid|paste` 指定一条路；环境变量 `XYZLCU_TYPE_VIA` 改默认值。
- `--window 标题`：焦点元素不在标题含这段文字的窗口里就拒绝输入（退出码 4），防止打进别的文稿。

**`key --via auto`（未锁定默认；严格锁限制快捷键/菜单）**

- 事件流正常：通过全局输入安全门后才走 `events`（带 `--app` 时是 `events-pid`）。
- 事件流卡住：先在应用菜单栏里找快捷键相同的菜单项（比对 `AXMenuItemCmdChar` / `AXMenuItemCmdModifiers` / `AXMenuItemCmdGlyph`，优先可用的项）并按下；找不到对应菜单项（方向键、return 等）就用 `CGEventPostToPid`。
- 都不行：退出码 4，提示改用 `menu` 指定菜单项。`--via events|menu|pid` 指定一条路，`XYZLCU_KEY_VIA` 改默认值。
- 输出 `keys[]`：每个组合键实际走的 `path`，走菜单时还有 `menuItem`。

**后台菜单**

`menu "App" "菜单>项" [--window 标题]` 按 pid 读菜单栏并 AXPress，**不把应用切到前台**（输出 `activated: false`、`appWasActive`）。`--window` 会先把那个窗口设成主窗口。在文本编辑上实测：

- 应用级菜单项（「文件>新建」「文件>打开…」等）在后台照常生效；
- 作用于文稿或输入焦点的菜单项（全选、粗体、防止编辑等）在应用不在前台时被 Cocoa 置灰，按了也没效果，输出会带 `note` 说明。这时加 `--activate`（先激活应用再按），或者改用 `insert` / `settext` / `type --via ax`。

**其他绕开键盘事件的命令**

```bash
xyzlcu insert TextEdit --window 我的笔记 "在光标处插入"         # 写 AXSelectedText
xyzlcu set-text TextEdit --role AXTextArea --window 我的笔记 "整体替换" # 聚焦、写值、读回
xyzlcu value TextEdit --window 我的笔记                         # 读回核对
```

- 定位：默认是应用当前焦点元素。`set-text` 支持 `--role`、`--title`、`--contains`、`--index`，或 compact AX 的 `--ref N`；用应用名或 `--pid N`，并按需限定锁定/窗口范围。`--window 标题` 限定目标窗口。
- 检查读回值和 `verified`：只有 `true` 才证明预期的 AX 值已写入；`false` 加 `reason` 表示效果未核实，不能算输入已确认，失败会列出尝试路线。
- 原生 Cocoa 文本框通常支持 AX 写入；网页和自绘界面可能需要 pid 事件，也可能忽略它。严格锁下剪贴板路线必须显式放宽。

**`check` 输出**：`paths` 里列出 events / mouse / ax / menu / pid / paste / record 的权限及健康元数据（`probeMs` 不是主动送达测试），`typeOrder` / `keyOrder` 是当前 auto 会按什么顺序试，`keyboardBlockedBy` 是卡住的监听。

**限制**：`events-pid`、`menu`、`paste` 绕开的是 HID 事件流上的监听；如果应用自己的主线程卡住了，哪条路都没用。要真正修好，需要重启卡住的进程（`xyzlcu taps` 里 `blocking: true` 的那个）或者注销/重启。XYZLCU 不会替你结束任何进程。

## 在后台操控 WKWebView / Tauri / Electron 应用

先用 `windows` / `apps` 找到真正拥有窗口的进程，避免选到同名 watchdog，再按 pid 锁定并观察 AX。下面是人工验收步骤；v0.7.1 的真实 GUI 行为仍需在有权限的 Mac 上验收。

```bash
xyzlcu lock --pid 1234 --window-title XYZStudio
xyzlcu observe --pid 1234
xyzlcu ax --pid 1234 --compact --text
xyzlcu set-text --pid 1234 --role AXTextArea --index 1 "你好，AX"
xyzlcu value --pid 1234 --role AXTextArea
xyzlcu press --pid 1234 --role AXRadioButton --title "My Models" --list
xyzlcu press --pid 1234 --role AXRadioButton --title "My Models" --nth 1
xyzlcu select --pid 1234 --popup Model --item "Local model"
xyzlcu scroll-to --pid 1234 --role AXDisclosureTriangle --title Documents
xyzlcu scroll 0 -5 --ax --pid 1234 --role AXTextArea
xyzlcu wait-text --pid 1234 "Complete" --timeout 60
xyzlcu wait-text --pid 1234 "Generating" --gone --timeout 60
xyzlcu unlock
```

`set-text` 先设控件 AXFocused 和应用 AXFocusedUIElement，再写 AXValue（`route: "ax-focus-value"`），不激活应用。可尝试 AXSelectedText；后台 `type` 还可用 pid Unicode。严格模式不回退剪贴板/菜单粘贴或全局输入。AX 读回核对文字，不支持核对的 pid 路线会如实标明。

原生 HTML select 通常表现为 AXPopUpButton，不能直接写值。AXPress 可能一直等到菜单关闭才返回，因此 `select` 异步打开菜单，找到该应用的 AXMenuItem 后按下。`press --list` 显示 index、role、title、frame、enabled、focused，便于先检查子文字标签和同名控件。

视口外的控件可能尚不存在于 AX 树。`scroll-to` 用 AXScrollToVisible、聚焦滚动或滚动条值做有限次遍历，`scroll --ax` 直接改最近滚动区。这依赖具体 WebView 的 AX 支持。pid 鼠标和按键事件可能被忽略；要看 `verified`、读回值并观察界面变化，投递成功本身不代表送达。

### 人工验收清单

- 让另一个应用留在前台，执行锁定后的输入步骤；确认 `verified: true`、值读回一致、`frontmostBefore` / `frontmostAfter` 相同且鼠标未动。
- 查看 `press --list`，按角色、文字片段和序号操作单选/展开控件；选择原生下拉菜单项后，用 AX 或截图确认选中状态。
- 在长页面上滚到原先不在 AX 树里的控件，核对 `scroll-to` 的可见性和 `scroll --ax` 的滚动条读回；分别测试文字出现和 `--gone`。
- 锁定后、目标不在前台时，显式全局输入路线必须失败；未锁定时，目标 `--app` / `--pid` 或 `--expect-front` 与前台不同，也必须在发字前失败。
- 在可丢弃的前台文稿中测试 `click --hold 90`、`key return --hold 40`、单击/右键/双击，再分别在目标应用验收。编译和 selftest 通过不代表 GUI 送达。
- 从实际 MCP 宿主启动，查看 `responsibleProcessInfo`，调用 `observe` 和 `screenshot`（`max_side: 1024`），确认权限错误点名那个宿主；`request --open` 应打开指定设置页。

无需 GUI 权限的检查：`./build.sh`、`build/xyzlcu-core version`、`build/xyzlcu-core --help`、`scripts/selftest.sh`（CLI、C 客户端和 MCP 协议检查）。没有 GUI/AX 权限的沙箱中不要运行上述 GUI 验收步骤。

## 录制与回放

```bash
xyzlcu record --duration 30                        # 默认存到 ~/.xyzlcu/recordings/rec-时间戳.jsonl
xyzlcu record --out /tmp/demo.jsonl --no-moves     # 不录鼠标移动
xyzlcu replay /tmp/demo.jsonl --speed 2 --no-keys  # 两倍速，只回放鼠标
```

- `record` 用的是**只监听**的事件监听（listenOnly，排在最后）：不拦截、不修改、不延迟任何输入，它自己卡住也不会挡住键盘。需要「输入监控」权限（`check` 里的 `inputMonitoring`）。Ctrl-C 或到 `--duration` 秒（默认 60）结束，输出摘要。
- 录下：按键按下 / 抬起 / 修饰键（含字符）、鼠标按键、拖动、滚动；鼠标移动最多每 15 毫秒一条（`--no-moves` 不录）。文件第一行是表头（版本、开始时间、显示器布局）。
- **隐私**：文件权限 0600，只存在本机，不上传。安全输入（密码框）开启时、屏幕锁定时**不录按键**（摘要里 `skippedSecureKeys` 计数）；锁屏后录制自动停止。录制文件里可能有你打的字，用完记得删掉。
- `replay` 按录制时的时间间隔把事件发到 HID 事件流，`--speed` 加速，`--no-keys` 只回放鼠标。事件流卡住时默认拒绝（回放的事件会排队），`--force` 强制；回放中屏幕被锁定会立刻停止（退出码 3）。回放前同样要确认前台窗口。
- 回放的就是普通合成事件，原样按时间重放：不加随机抖动，不做「拟人化」，也不做任何反检测处理。

## 守护进程

每次执行 `xyzlcu` 都要启动进程、检查权限、连接窗口服务器，大约 15–50 毫秒。常驻守护进程把这些开销只付一次：

```bash
xyzlcu serve --background   # 在智能体/终端自己的 shell 里启动（后台，日志在 ~/.xyzlcu/serve.log）
xyzlcu serve &              # 或者这样前台挂着
xyzlcu serve --status       # 查看：pid、版本、运行时长、权限、负责 App、截图流
xyzlcu check            # 输出里 "daemon": true 表示已经在走守护进程
xyzlcu serve --stop     # 停止
```

- 启动后，所有命令（包括 `run`、`batch`）**自动转发**给守护进程，用法和输出完全一样。连不上或版本不一致时自动退回进程内执行。
- `XYZLCU_DAEMON=0`：不用守护进程；`XYZLCU_DAEMON=1`：必须用守护进程，连不上就返回退出码 5。
- **只会有一个守护进程**（v0.5.0）：`serve` 启动时先拿 `~/.xyzlcu/sock.lock` 的文件锁，已经有守护进程在跑就直接说明并返回 0（可以放心重复运行）；被 `kill -9` 留下的旧套接字会被识别并替换。守护进程刚启动、还没开始接受连接时，客户端最多等 3 秒（`XYZLCU_CONNECT_WAIT_MS`），不会误判成没有守护进程。
- **协议**（v0.5.0）：客户端和守护进程之间图片走原始二进制（长度前缀），不再 base64；`--base64` 的 JSON 输出和 MCP 仍然是 base64。版本不同的客户端会自动退回进程内执行；`serve --stop` 能停掉旧版本的守护进程。
- **旧守护进程自动重启**（v0.6.0）：升级后，客户端发现守护进程比自己旧，就停掉它、用新版本在后台重启，再执行这条命令（只发生一次，约 1 秒）。多个客户端同时发现时用 `~/.xyzlcu/sock.restart` 的文件锁排队。新守护进程的权限跟着启动它的进程走，所以只有当前进程同时有辅助功能和屏幕录制权限时才会自动重启，否则提示你在有权限的终端里手动重启。`XYZLCU_AUTO_RESTART=0` 关闭。客户端比守护进程旧时不动守护进程，退回进程内执行。
- 套接字在 `~/.xyzlcu/sock`（目录权限 0700，套接字 0600），只接受**同一用户**的连接（`getpeereid` 校验），不监听网络端口。可以用 `XYZLCU_SOCKET` 改路径。
- 守护进程里同样有锁屏保护和权限检查，相对路径按调用方的当前目录解析。
- **权限（TCC）**：守护进程使用的是**启动它的那个 App** 的权限，所以要在智能体或终端自己的 shell 里运行 `xyzlcu serve --background`，这样负责 App 和直接运行命令时一样。用 `xyzlcu serve --status` 看 `responsibleProcess`。
- **截图流（v0.4.2）**：守护进程第一次截某个窗口 / 屏幕 / 区域时，会在后台为它开一个 ScreenCaptureKit 截图流，之后的截图直接取最新一帧（输出 `method: "screencapturekit-stream"`），不用每次重新截。v0.5.0 起每个缩放比例单独一个流，由 GPU 直接缩放（新缩放比例的流还没出帧时，先用已有的流在 CPU 上缩一张）。最多同时 4 个流；某个流 20 秒没人用就自动关掉（`XYZLCU_STREAM_IDLE=秒` 可改）。刚点击 / 打字之后的截图会等到新的一帧（最多 0.12 秒），不会拿到操作前的旧画面。截图流开着时，菜单栏会显示系统的录屏指示，这是正常的；`XYZLCU_STREAM=0` 关闭截图流，每次单独截。`xyzlcu serve --status` 里 `liveStreams` 列出当前开着的流。
- **预热主屏（v0.5.0）**：守护进程一启动就为主屏开好原尺寸和半尺寸两个截图流（`XYZLCU_PREWARM_SCALES=1,0.5` 可改），这样第一次截图也只要 25–35 毫秒，而不是 170–210 毫秒。**代价**：只要守护进程在跑，菜单栏就一直有录屏指示；两个流大约占 45 MB 内存，GPU 在屏幕变化时持续做一点缩放。预热的流 600 秒没人用才关（`XYZLCU_PREWARM_IDLE=秒`），关了之后下次截图再按需重开。不想要就 `XYZLCU_PREWARM=0 xyzlcu serve --background`。
- **PNG 编码（v0.5.0）**：自己写的多线程 PNG 编码器（zlib 级别 1，按条带并行压缩），保持截图原来的色彩空间并嵌入 ICC 描述文件，和系统 ImageIO 编出来的像素完全一致，只是文件稍大。`XYZLCU_PNG=imageio` 改回系统编码器，`XYZLCU_PNG_LEVEL=0-9` 调压缩级别。
- **指定窗口截图（v0.7.0）**：锁定/指定窗口始终用 ScreenCaptureKit 桌面独立窗口过滤器。跳过 v0.6.0 的 `display-stream-crop` 优化，避免其他应用像素进入图像；下方旧裁剪测速不代表当前路线。
- **应用表（v0.6.0）**：守护进程自己维护运行中的应用（启动 / 退出 / 激活 / 隐藏通知更新，最多 10 秒整体刷新一次），`apps`、找应用都不用再挨个问 LaunchServices。
- 想开机自动启动，可以自己写一个 LaunchAgent（`~/Library/LaunchAgents/*.plist`，`ProgramArguments` 为 `xyzlcu serve`）。注意这时负责进程是 launchd 启动的 xyzlcu 本身，要在系统设置里单独给 `xyzlcu-core` 这个二进制授权（`ProgramArguments` 也建议直接写 `xyzlcu-core serve`）。XYZLCU 不会替你安装 LaunchAgent。

## 完整示例：用文本编辑写一段中文并保存

```bash
# 0. 准备一个空文件，打开它（这样输入的文字肯定落在这个文件里）
: > ~/Documents/xyzlcu-demo.txt
open -a TextEdit ~/Documents/xyzlcu-demo.txt
xyzlcu wait 1500
xyzlcu activate TextEdit

# 1. 确认前台和焦点窗口就是这个文件（不是别的文稿）
xyzlcu wait TextEdit --role AXWindow --title xyzlcu-demo.txt --timeout 5
xyzlcu ax TextEdit --depth 0          # 第一行窗口的 title 应该是 xyzlcu-demo.txt

# 2. 找到文本区域并点进去（一步完成）
xyzlcu click-el TextEdit --role AXTextArea --window xyzlcu-demo.txt --click

# 3. 输入中文、换行、再来一行
xyzlcu type "你好，这是 XYZLCU 的电脑操控测试 123"
xyzlcu key return
xyzlcu type "第二行：Unicode 😀"

# 4. 保存并核对
xyzlcu key cmd+s
cat ~/Documents/xyzlcu-demo.txt

# 5. 关闭文稿
xyzlcu key cmd+w
```

## 支持的智能体

XYZLCU 是**通用的**：它不依赖任何智能体框架，也不需要插件。一个智能体只要能 ① 执行 shell 命令、② 读命令的输出（JSON 或 `ok`）和退出码，就能用 XYZLCU 操作这台 Mac。只会说 MCP 的客户端用 `xyzlcu mcp`。

| 智能体 / 工具 | 怎么接入 | 状态 |
|---|---|---|
| **Grok**（Grok Bot） | shell 工具直接运行 `xyzlcu …` | ✅ 已实测 |
| **Codex**（OpenAI Codex CLI） | shell 工具；或 MCP（`~/.codex/config.toml`） | ✅ 已实测（0.163.0，shell 方式）。需要完全访问模式：在沙箱里 `xyzlcu cursor` 会返回 `0,0`，见下方说明 |
| **ChatGPT**（ChatGPT 桌面版 / ChatGPT 里的 agent） | 能执行本机命令的 ChatGPT 系工具（如 Codex）直接跑 `xyzlcu …`；只接 MCP 的场景用 `xyzlcu mcp`（stdio；ChatGPT 若只支持远程 MCP，需要自己用 stdio→HTTP 桥接） | 🟡 兼容（MCP / 命令行），未实测 |
| **Claude**（Claude Code） | Bash 工具；或 `claude mcp add`（见下方） | 🟡 兼容（命令行 / MCP），未实测 |
| **Claude**（Claude Desktop） | MCP（`claude_desktop_config.json` 的 `mcpServers`，见下方） | 🟡 兼容（MCP），未实测 |
| **DeepSeek**（基于 DeepSeek 模型的智能体 / harness） | harness 的 shell 工具运行 `xyzlcu …`；或在 harness 的 MCP 配置里加 `xyzlcu mcp` | 🟡 兼容（命令行 / MCP），未实测 |
| OpenCode | bash 工具 | ✅ 已实测（2.0.32） |
| 任意 MCP 客户端 | `xyzlcu mcp`（stdio） | ✅ 已实测（用脚本做了完整握手：initialize、tools/list、tools/call、截图图片返回） |
| 自己写的 Python / Node 程序 | `subprocess` / `child_process`，见下方示例 | ✅ 已实测 |
| Cursor | Agent 的终端；或 `.cursor/mcp.json` | 🟡 兼容（命令行 / MCP），未实测 |
| Gemini CLI | `run_shell_command`；或 `~/.gemini/settings.json` 的 `mcpServers` | 🟡 兼容（命令行 / MCP），未实测（本机登录不可用，没跑完） |
| Cline / Roo Code | `execute_command`；或扩展的 MCP 设置 | 🟡 兼容（命令行 / MCP），未实测 |
| Aider | `/run xyzlcu …` | 🟡 兼容（命令行），未实测 |
| OpenClaw | exec / shell 工具 | 🟡 兼容（命令行），未实测 |
| Trae | 终端；或 MCP 设置 | 🟡 兼容（命令行 / MCP），未实测 |
| 不用智能体 | shell 脚本、快捷指令「运行 Shell 脚本」、cron / launchd | ✅ 已实测（shell 脚本） |

「已实测」是指在测试机上真的让它调用了 `xyzlcu`（至少 `check`、`cursor`、`apps` 和截图）并核对了结果；「兼容」是指它能执行 shell 命令或接 MCP 服务器，XYZLCU 对它和对其他调用方没有任何区别，但还没在测试机上亲自跑过。欢迎跑通后提 issue / PR 把状态改成已实测。

**快速接入**（完整说明见 [MCP 服务器](#mcp-服务器)）

- 会跑 shell 命令的智能体（Grok、Codex、Claude Code、DeepSeek harness……）：把下面「放进 AGENTS.md / CLAUDE.md」那段贴进项目说明，直接调用 `xyzlcu …` 即可。
- Claude Code 用 MCP：

  ```bash
  claude mcp add xyzlcu -- "$(which xyzlcu)" mcp
  ```

- Claude Desktop 及其他用 `mcpServers` 格式的客户端（`command` 写 `which xyzlcu` 的完整路径，很多客户端不展开 `~`）：

  ```json
  {
    "mcpServers": {
      "xyzlcu": { "command": "xyzlcu", "args": ["mcp"] }
    }
  }
  ```

**注意**

- **权限跟着负责 App 走**：系统的「辅助功能」「屏幕与系统录音」要授给启动 `xyzlcu` 的那个 App（终端、Cursor、Claude.app……）。用 `xyzlcu whoami` 查看。先在智能体自己的 shell 里运行 `xyzlcu serve --background`，之后的命令和 `xyzlcu mcp` 都会转发给这个守护进程、用它的权限。
- **Codex CLI 的沙箱**：在默认的沙箱模式里，命令连不上窗口服务器（比如 `xyzlcu cursor` 返回 `0,0`、截图失败）。要用完全访问模式（`--sandbox danger-full-access`），或者在它询问时允许这条命令在沙箱外运行。别的有沙箱的智能体同理。
- 智能体在沙箱或远程容器里跑、碰不到本机图形会话时，XYZLCU 无法工作。

### 放进 AGENTS.md / CLAUDE.md / .cursor/rules 的一段

直接复制到项目的 `AGENTS.md`（Codex、OpenCode、Gemini CLI 等）、`CLAUDE.md`（Claude Code）、`.cursor/rules/xyzlcu.mdc`（Cursor）、`.clinerules`（Cline）或系统提示词里：

```markdown
## 操作 Mac 图形界面：xyzlcu

你可以用命令行工具 `xyzlcu` 看屏幕、点击、打字、按键、读取界面控件树。

开始
- 会话开始时运行一次 `xyzlcu serve --background`（之后的命令都更快，重复运行没关系），再运行 `xyzlcu check`。
- `screenLocked` 为 true 或权限缺失：停下来告诉用户，不要继续。

常用命令（输出 JSON 或 `ok`）
- 看：`xyzlcu find "App" --role AXButton --title 保存`（返回 center）、`xyzlcu ax "App" --depth 6`
- 截图：`xyzlcu screenshot --fast --base64`（整屏，图片在 JSON 的 base64 字段，不写文件）、
  `xyzlcu screenshot --window "App" --base64`、`xyzlcu screenshot /tmp/s.jpg --region x,y,w,h`
- 按控件：`xyzlcu click-el "App" --role AXButton --title 保存`
- 省 token 的看法：`xyzlcu ax "App" --compact` 只列可操作的控件（`[3] Button "保存" @612,340`），再 `xyzlcu click-el --ref 3` 按编号点
- 点坐标：`xyzlcu click x y`（锁定时窗口相对点，未锁定时全局点；截图像素按 pixelsPerPoint 和 originX/originY 换算）
- 打字：`xyzlcu type --app "App" --window "窗口标题" "文字"`（看输出的 path 和 verified）
- 按键：`xyzlcu key --app "App" cmd+s`
- 应用：`xyzlcu apps`、`xyzlcu activate "App"`
- 等待：`xyzlcu wait "App" --title T --timeout 5`（不要用固定 sleep）
- 连续几步：`xyzlcu run 'click-el App --title 搜索; type 你好; key return'`
- 只看变化：`xyzlcu screenshot --fast --diff --base64`（没变化就不出图）

退出码
- 0 成功；1 参数错误或找不到应用/元素；2 缺少权限；3 屏幕锁定，操作被拒绝；
  4 找不到控件、wait 超时、输入没生效或 --window 不符；5 要求守护进程但连不上。

安全规则
- 优先 `lock --pid N` 和 AX 控件/写值；绝不静默放行全局输入。前台流程用 `--app "App"` / `--pid N` 指定已在前台的目标（或显式 `--allow-global`），检查 frontmostBefore/frontmostAfter 和 verified。
- 循环：观察 → 定位 → 操作 → 验证。操作后重新 find / 截图确认结果。
- 付款、删除、发送、提交等不可撤销的操作先征得用户同意。
- 不要用 `--force` 绕过锁屏保护。
- 遇到验证码、「确认你是真人」或其他反机器人检查时停下来交给用户，不要尝试绕过。
```

### 在自己的程序里调用

Python：

```python
import base64, json, subprocess

def xyz(*args):
    r = subprocess.run(["xyzlcu", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"xyzlcu {args[0]} 失败（退出码 {r.returncode}）：{r.stderr.strip()}")
    out = r.stdout.strip()
    return json.loads(out) if out.startswith(("{", "[")) else out

print(xyz("cursor"))                                   # {"x": …, "y": …}
shot = xyz("screenshot", "--fast", "--base64")         # 不写文件
jpeg = base64.b64decode(shot["base64"])
```

Node：

```js
import { execFileSync } from "node:child_process";
const xyz = (...args) => JSON.parse(execFileSync("xyzlcu", args, { encoding: "utf8" }));
console.log(xyz("cursor"));
const jpeg = execFileSync("xyzlcu", ["screenshot", "--fast", "--stdout"]); // Buffer，原始 JPEG 字节；元数据 JSON 在 stderr
```

### MCP 服务器

`xyzlcu mcp` 以 stdio 方式运行一个 MCP 服务器（JSON-RPC 2.0，一行一条消息），给只支持 MCP、不能直接跑命令的客户端。提供这些工具：

- 只读：`check`、`observe`（前台应用、目标窗口、简洁 AX 文字）、`screenshot`、`apps`、`windows`、`cursor`、`ax`、`find`、`wait_text`
- 操作：保留 `click_element`、`click`、`type_text`、`key`、`activate`；新增 `set_text`、`press`（`nth`、`list`、`async`）、`select_popup_item`（`popup`、`item`）、`scroll_to`
- 后台：`lock` 支持 `app` / `pid`、`window_title` / `window_id`、`unsafe`、`unlock`、`status`。可能发送全局输入的工具支持 `allowGlobal`（默认 `false`）；`allow_foreground`、`assert_no_contention`、`expect_front` 对应 CLI 策略。通用工具可在 CLI 参数中传入 `--allow-global`。锁定后可省应用名；`ax.focus` 为 `content` / `window` / `web`。
- 批量：`batch`（`steps` 是命令字符串数组，比如 `["click-el TextEdit --title 保存", "wait TextEdit --role AXSheet", "screenshot --diff"]`，一次调用按顺序执行，返回每一步的输出和图片；`continue_on_error` 出错后继续）。省掉多次往返和模型多轮生成；截图步骤默认半尺寸 JPEG
- `screenshot` 默认 fast JPEG、质量 0.6、缩放 0.5，锁定窗口也一样；`max_side` 限制图片最长边，`scale` 覆盖默认缩放。`diff: true` 只返回变化区域。元数据给出坐标换算，应按返回比例计算，不要假定 Retina 一定为 2 倍。
- 通用：`xyzlcu`（`args` 数组，执行任意子命令；不允许 `mcp`、`serve`、`record`、`replay`、`batch` 和 `--stdout`）

有守护进程在跑时，每个工具调用都转发给它；没有时 `xyzlcu mcp` 自己就是一个常驻进程（同样会保持截图流），不会每次调用都启动新进程。

下面把 `/Users/你的用户名/.local/bin/xyzlcu` 换成 `which xyzlcu` 的结果（很多客户端不展开 `~`）。

Claude Desktop（`~/Library/Application Support/Claude/claude_desktop_config.json`）、Cursor（项目里的 `.cursor/mcp.json` 或 `~/.cursor/mcp.json`）、Gemini CLI（`~/.gemini/settings.json`）用的都是这个格式：

```json
{
  "mcpServers": {
    "xyzlcu": {
      "command": "/Users/你的用户名/.local/bin/xyzlcu",
      "args": ["mcp"]
    }
  }
}
```

Claude Code：

```bash
claude mcp add xyzlcu -- "$(which xyzlcu)" mcp
```

Codex CLI（`~/.codex/config.toml`）：

```toml
[mcp_servers.xyzlcu]
command = "/Users/你的用户名/.local/bin/xyzlcu"
args = ["mcp"]
```

自己测一下握手：

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | xyzlcu mcp
```

- MCP 服务器由客户端 App 启动，所以系统权限要授给**那个 App**（比如 Claude.app、Cursor）；或者先在已授权的终端里 `xyzlcu serve --background`，MCP 调用就会转发给它、用它的权限。
- 客户端问是否允许调用某个工具时，按你对它的信任来选；操作类工具（`click`、`type_text`、`key` 等）会真的操作你的电脑。

## 性能对比（与 LCU）

下表保留旧版本测量。v0.7.0 增加了点击/按键按住时间并调整 AX 路线，这里没有宣称新版 GUI 测速已经完成。

**LCU 仍然占优的地方**（先说清楚）：

- **后台操作**：两者都有后台路线。XYZLCU 现在提供锁定窗口 + AX 优先操作，但支持程度取决于应用，限制见上文；下方历史测速中的 XYZLCU 输入采用前台路线。
- **和模型的配合**：LCU 背后是 ChatGPT 的 CUA 运行时，按应用组织操作，和 ChatGPT / Codex 配合得更紧。下面的表只比单个操作的延迟，不代表完成整个任务的能力。

### 0.6.0 对比 0.5.0

同一台机器，两个守护进程（0.5.0 和 0.6.0）同时跑在不同的套接字上，**交替**调用，每项 21 次，**中位数 / p90**，单位毫秒。交替测是为了排除系统负载波动（同一版本前后两轮能差 20%）。

| 操作 | 0.5.0 | **0.6.0** |
|---|---:|---:|
| 列出应用（`apps`） | 9.5 / 9.9 | **3.2 / 3.5** |
| 列出窗口（`windows`） | 3.4 / 7.0 | 3.3 / 4.4 |
| 控件树（`ax 文本编辑`，焦点窗口） | 26.9 / 28.1 | **5.3 / 7.5** |
| 控件树带菜单（`ax Finder --menu`） | 52.1 / 53.7 | **23.0 / 23.9** |
| `find` 找到文本区域 | 20.6 / 23.3 | **7.9 / 11.0** |
| `find` 找不到（搜完整棵树） | 26.9 / 30.9 | **12.9 / 14.9** |
| 窗口截图（被挡住的窗口，流已开） | 14.7 / 16.0 | **6.2 / 6.8** |
| 窗口截图（最前面的窗口，流已开） | 17.2 / 38.6 | **6.4 / 19.9** |
| 整屏 `--fast` | 8.9 / 25.8 | 8.9 / 18.5 |
| **第一次**截某个窗口（没被挡住，主屏流预热中；8 次） | 113.6 / 128.1 | **25.3 / 31.2** |
| **第一次**截某个窗口（被挡住；8 次） | 98.3 / 120.6 | 82.1 / 88.6 |

`ax --compact` 的输出大小（同样的窗口）：

| | `ax` | `ax --compact` |
|---|---:|---:|
| 文本编辑窗口 | 740 字节 / 11 行 | **243 字节 / 4 行** |
| 文本编辑窗口 + 菜单栏（`--menu`） | 9209 字节 / 153 行 | **513 字节 / 12 行** |
| 访达 + 菜单栏（`--menu`） | 13680 字节 / 224 行 | **401 字节 / 11 行** |

**慢在哪、改了什么（实话实说）**

- **最大的瓶颈是 NSRunningApplication**：用 `sample` 看守护进程，`apps` 的时间几乎全花在 `_LSCopyApplicationInformation` 的同步 XPC 上。`NSWorkspace.runningApplications` 每次都返回新对象，读每个对象的第一个属性（连 `processIdentifier` 都算）都要问一次 LaunchServices，140 个进程约 8–15 毫秒。按 pid 缓存没用（读 pid 本身就慢），所以改成守护进程自己维护应用表。`find`、`ax`、窗口截图都要先找应用，所以一起变快。
- **控件树**：原来每个控件 6–8 次 IPC，改成一次 `AXUIElementCopyMultipleAttributeValues`。
- **第一次截窗口**：原来要先用 `SCScreenshotManager` 截一张（约 55 毫秒）再开窗口流。现在窗口没被挡住、整个在一块屏幕里、那块屏幕的流开着（守护进程默认预热主屏），就直接裁主屏的最新一帧。被挡住的窗口仍然走原来的路（约 80 毫秒），因为裁出来会带上前面的窗口。判断「挡住」时忽略铺满整块屏幕的非普通层窗口（程序坞、全屏透明覆盖层），否则所有窗口都会被判成挡住。
- **没改的**：
  - 进程内（不开守护进程）调用约 13 毫秒的固定开销是加载 Swift 运行时和 AppKit 等框架，代码里省不掉；解决办法就是守护进程 + C 客户端（3 毫秒）。
  - `--fast` 已经是 GPU 直接出小图，约 9 毫秒，主要是编码和传输。
  - 预热的流保持 60 fps：空闲时守护进程约占 1.9% 的一个核、9.6 MB 内存（只在最后一次截图后的 10 分钟内）。降帧率会让点击后的截图等更久，不划算。
  - `run` 里多张 `--stdout` 图没有做成一次返回多张（命令行的标准输出只能放一段二进制），改成明确报错；要多张图用 `-o` 文件或 MCP `batch`。

### 0.5.0 对比 0.4.2 和 LCU
**环境**：Apple Silicon Mac（macOS 26+）。XYZLCU 0.5.0 对比 0.4.2 和 [LCU](https://github.com/amontlabs/lcu) 0.13.4（ChatGPT 自带的 CUA 运行时 0.0.35）。每项跑 15 次，表里是**中位数 / p90**，单位毫秒。LCU 一列是 0.4.2 那一轮在同一台机器上测的（这次没有重装 LCU）。

| 操作 | 0.5.0 进程内 | **0.5.0 守护进程** | 0.4.2 守护进程 | LCU（MCP `js` 调用） |
|---|---:|---:|---:|---:|
| 版本号（`version`，相当于空调用） | 8 / 11 | **3 / 3** | 8 / 9 | — |
| 列出应用（`apps` / `cua.listApps`） | 18 / 19 | **10 / 10** | 15 / 18 | 17 / 18 |
| 列出窗口（`windows`） | 57 / 68 | **3 / 3** | 7 / 11 | —（Mac 上没有） |
| 鼠标位置（`cursor`） | 28 / 32 | **2 / 2** | 6 / 6 | —（Mac 上没有） |
| 移动鼠标（`move`） | 68 / 75 | **2 / 4** | 7 / 10 | —（Mac 上没有） |
| 整屏截图（全尺寸 PNG，写文件） | 223 / 248 | **31 / 34** | 171 / 180 | —（Mac 上没有） |
| 整屏截图（全尺寸 JPEG，写文件） | 214 / 226 | **30 / 33** | 48 / 50 | —（Mac 上没有） |
| 整屏截图（全尺寸 HEIC，写文件） | — | 98 / 103 | — | —（Mac 上没有） |
| 整屏截图（半尺寸 PNG，写文件） | 199 / 212 | **12 / 15** | 50 / 52 | —（Mac 上没有） |
| 整屏截图（`--fast`，半尺寸 JPEG，写文件） | 202 / 212 | **9 / 10** | 13 / 72 | —（Mac 上没有） |
| 整屏截图（`--fast --base64`，只在内存里） | 192 / 199 | **10 / 10** | 20 / 24 | —（Mac 上没有） |
| 整屏截图（`--fast --stdout`，只在内存里） | 194 / 206 | **9 / 9** | 18 / 20 | —（Mac 上没有） |
| 整屏截图（`--fast --diff --base64`） | — | **9 / 15** | — | —（Mac 上没有） |
| 窗口截图（文本编辑窗口，PNG 写文件） | 202 / 228 | **17 / 103** | 26 / 86 | 51 / 53 |
| 窗口截图（`--window … --base64`，只在内存里） | 203 / 220 | **18 / 24** | 24 / 32 | 51 / 53 |
| 控件树（`ax --depth 3` / `getAXState`） | 64 / 76 | **20 / 22** | 32 / 47 | 55 / 76 |
| 点击（`click`） | 59 / 69 | **6 / 9** | 11 / 16 | 140 / 166 |
| 输入英文 `abc` | 85 / 113 | **5 / 9** | 10 / 14 | 43 / 48 |
| 输入中文 `你好abc` | 109 / 121 | **7 / 10** | 10 / 14 | 9057 / 10541 |
| 按键（`cmd+right` / `super+Right`） | 71 / 87 | **4 / 11** | 10 / 14 | 14 / 19 |
| 连续 3 次调用（`cursor`、`--fast` 截图、`windows`） | 271 / 283 | 17 / 20 | 41 / 44 | — |
| 同样 3 步放进一次 `run` | 195 / 207 | **12 / 15** | 25 / 26 | — |

**其他测量**（0.5.0，守护进程）

| 项目 | 0.4.2 | 0.5.0 |
|---|---:|---:|
| 守护进程重启 1.5 秒后的第一次 `--fast` 截图 | 190–220 | **24–37**（预热）；`XYZLCU_PREWARM=0` 时 173–213 |
| 一次转发调用（`cursor`，30 次中位数） | 6（Swift 客户端） | **3.1**（C 客户端；`/usr/bin/true` 本身 1.6） |
| MCP：`cursor` + `screenshot` + `windows` 三次工具调用 vs 一次 `batch` | — | 16.1 vs 15.8 |
| MCP `screenshot`（半尺寸 JPEG，直接返回图片） | — | 11–12 |
| MCP `screenshot diff: true`，画面没变 | — | 3–4（不返回图片） |

**怎么测的**

- **XYZLCU**：每次都是一次完整的命令行调用（启动进程 → 执行 → 输出 JSON），也就是智能体从 shell 调用时真正付出的时间。「进程内」= `XYZLCU_DAEMON=0`；「守护进程」= 先运行 `xyzlcu serve`。先测进程内、再启动守护进程测（原因见[常见问题](#常见问题)里截图那一条）。
- **LCU**：在临时目录里装了一份（不改系统、不改任何智能体配置），用 LCU 自带的 `adapters/client.mjs` 以 stdio 方式连上 `lcu` MCP 服务器，每个操作是一次 `js` 工具调用，比如 `await app.click([x, y])`、`await app.typeText("abc")`。计的是**已连上之后**一次调用的往返时间；连接（约 270 ms）、首次调用（约 520 ms）、`getApp`（约 70 ms）都不算在内，智能体自己生成工具调用的时间也不算。
- 「连续 3 次调用」是三次独立的命令行调用；「一次 `run`」是 `xyzlcu run 'cursor; screenshot --fast; windows'`。
- **GUI 操作**都在一份临时的文本编辑文稿里做：每次输入前确认它在前台、而且是最前面的窗口；结束后读回文稿内容核对（两边输入的文字都正确），再关闭、删除这份文稿。LCU 第一次操作文本编辑时会请求授权，测试只回答「仅本次会话」。

**结果怎么看（实话实说）**

- **转发开销降到 2–3 毫秒**：守护进程在跑时，`xyzlcu` 是一个很小的 C 程序，连上套接字、发请求、把结果原样写出来就退出，不再加载 Swift 运行时和那些系统框架。查询、点击、打字、按键都比 0.4.2 快一倍左右。
- **全尺寸 PNG 171 → 31 毫秒**：慢的不是截图，是编码。0.4.2 用系统 ImageIO，单线程，而且要先转换色彩空间；0.5.0 自己并行压缩，保持原色彩空间并嵌入 ICC。像素和 ImageIO 编出来的完全相同，文件大一些。
- **`--fast` 约 9 毫秒，而且第一次也快**：每个缩放比例单独一个 ScreenCaptureKit 流，由 GPU 缩放；守护进程启动时预开主屏的原尺寸和半尺寸流。从原尺寸流在 CPU 上缩放并不快：读一张 4112×2658 的 IOSurface（44 MB）本身就要 11 毫秒左右，所以改成让 GPU 直接出小图。
- **HEIC 比 JPEG 慢**（全尺寸 98 vs 30 毫秒），文件更小。想省带宽 / token 用 HEIC，想要快用 JPEG。
- **窗口截图 p90 偏高（103 毫秒）**：每轮第一次截某个窗口要先建流，之后 17–18 毫秒。
- **`run` / MCP `batch` 省的是往返**：命令行下 3 次调用 17 毫秒，一次 `run` 12 毫秒；MCP 本来就连着守护进程，3 次调用和一次 `batch` 差不多（16.1 vs 15.8 毫秒）。MCP `batch` 真正省的是模型多轮生成工具调用的时间（每轮通常是几百毫秒到几秒），这一部分这里没算。
- **`--diff`**：画面没变时只回一小段 JSON（3–4 毫秒，没有图片）；变了就只给变化的那块。对需要反复「看一眼」的智能体最省 token。
- 进程内（不开守护进程）基本和 0.4.2 一样，时间主要花在启动进程和连接窗口服务器上；比 0.4.2 多 1–2 毫秒，是 C 客户端 `exec` 到 `xyzlcu-core` 的代价。
- **历史点击对比**：旧的 140 毫秒与 6 毫秒数字比较的是不同投递路线；v0.7.0 增加悬停和按住时间，当前延迟需重新测速，后台送达另行核对。
- **LCU 输入中文很慢**：`你好abc` 中位数约 9 秒，纯英文只要 43 毫秒。XYZLCU 直接发送 Unicode 或写辅助功能，中英文一样快。
- **「—」在 LCU 列不是没测，是 LCU 在 Mac 上没有这个能力**（没有鼠标位置 / 移动、整屏截图和窗口列表，它按应用来操作）。
- 这张表只比单个操作的延迟，不代表完成整个任务的能力。LCU 背后是 ChatGPT 的 CUA 运行时，在和模型配合、后台操作方面有它的长处。

**用起来的区别**

| | XYZLCU | LCU |
|---|---|---|
| 需要什么 | 一个二进制，macOS 13+，Apple Silicon 或 Intel | 已安装 ChatGPT 桌面应用（借用它的 CUA 运行时）、Apple Silicon；自带 Node |
| 怎么接入 | 任何能跑 shell 命令的工具；也可以 `xyzlcu mcp` | MCP 服务器（`lcu setup --agent …` 写入智能体配置） |
| 授权 | 系统「辅助功能」「屏幕与系统录音」授给负责 App | 系统权限之外，每个应用第一次被操作时还要批准（仅本次会话 / 始终） |
| 操作方式 | 全局坐标 + 真实键鼠事件，另有辅助功能、直接投递、菜单等不经过键盘事件的路 | 按应用操作，坐标是窗口截图里的像素，后台投递 |
| 输出 | JSON；截图写成文件，或 `--base64` / `--stdout` 只在内存里；MCP 下直接返回图片 | 工具结果直接带图片 |

**自己跑一遍**

```bash
python3 scripts/bench.py ~/.local/bin/xyzlcu --runs 15            # 只测 XYZLCU（进程内 + 守护进程）
python3 scripts/bench.py ~/.local/bin/xyzlcu --runs 15 --gui      # 再加点击、输入、按键（会开一个临时文本编辑文稿）
python3 scripts/bench.py ~/.local/bin/xyzlcu --runs 15 --gui \
    --lcu /path/to/lcu --lcu-allow-session --json bench.json       # 同时测 LCU（需要已装好 LCU 和 ChatGPT 桌面应用）
```

`--mode inproc|daemon` 只测一种模式。不加 `--lcu-allow-session` 时，脚本会拒绝 LCU 的授权请求，需要授权的那些操作就没有数字；脚本永远不会选「始终允许」。想要干净的进程内截图数字，先 `xyzlcu serve --stop`。

<details>
<summary>v0.4.2 的对比结果</summary>

**环境**：Apple Silicon Mac（macOS 26+）。XYZLCU 0.4.2 对比 [LCU](https://github.com/amontlabs/lcu) 0.13.4（ChatGPT 自带的 CUA 运行时 0.0.35）。每项跑 15 次，表里是**中位数 / p90**，单位毫秒；最后一列是同一台机器上 0.4.1 守护进程的中位数。

| 操作 | XYZLCU 进程内 | XYZLCU 守护进程 | LCU（MCP `js` 调用） | 0.4.1 守护进程 |
|---|---:|---:|---:|---:|
| 版本号（`version`，相当于空调用） | 6 / 7 | 7 / 12 | — | 10 |
| 列出应用（`apps` / `cua.listApps`） | 15 / 19 | **13 / 13** | 17 / 18 | 17 |
| 列出窗口（`windows`） | 44 / 52 | **9 / 18** | —（Mac 上没有） | 7 |
| 鼠标位置（`cursor`） | 26 / 32 | **8 / 11** | —（Mac 上没有） | 6 |
| 移动鼠标（`move`） | 55 / 73 | **9 / 19** | —（Mac 上没有） | 7 |
| 整屏截图（全尺寸 PNG，写文件） | 352 / 361 | 180 / 200 | —（Mac 上没有） | 233 |
| 整屏截图（`--fast`，半尺寸 JPEG，写文件） | 184 / 200 | **13 / 75** | —（Mac 上没有） | 60 |
| 整屏截图（`--fast --base64`，只在内存里） | 192 / 208 | **21 / 23** | —（Mac 上没有） | — |
| 窗口截图（文本编辑窗口，PNG 写文件） | 199 / 207 | **35 / 72** | 51 / 53 | 68 |
| 窗口截图（`--window … --base64`，只在内存里） | 185 / 199 | **23 / 27** | 51 / 53 | — |
| 控件树（`ax --depth 3` / `getAXState`） | 66 / 69 | **26 / 29** | 55 / 76 | 28 |
| 点击（`click`） | 56 / 74 | **12 / 19** | 140 / 166 | 12 |
| 输入英文 `abc` | 82 / 93 | **13 / 17** | 43 / 48 | 12 |
| 输入中文 `你好abc` | 82 / 116 | **13 / 18** | 9057 / 10541 | 14 |
| 按键（`cmd+right` / `super+Right`） | 78 / 98 | **10 / 13** | 14 / 19 | 8 |

</details>

<details>
<summary>v0.4.1 的对比结果</summary>

**环境**：Apple Silicon Mac（macOS 26+）。XYZLCU 0.4.1 对比 [LCU](https://github.com/amontlabs/lcu) 0.13.4（ChatGPT 自带的 CUA 运行时 0.0.35）。每项跑 15 次，表里是**中位数 / p90**，单位毫秒。

| 操作 | XYZLCU 进程内 | XYZLCU 守护进程 | LCU（MCP `js` 调用） |
|---|---:|---:|---:|
| 版本号（`version`，相当于空调用） | 5 / 6 | 10 / 18 | — |
| 列出应用（`apps` / `cua.listApps`） | 14 / 16 | 17 / 18 | 14 / 16 |
| 列出窗口（`windows`） | 52 / 63 | **7 / 8** | —（Mac 上没有） |
| 鼠标位置（`cursor`） | 27 / 35 | **6 / 6** | —（Mac 上没有） |
| 移动鼠标（`move`） | 54 / 65 | **7 / 10** | —（Mac 上没有） |
| 整屏截图（全尺寸 PNG） | 354 / 367 | 233 / 250 | —（Mac 上没有） |
| 整屏截图（`--fast`，半尺寸 JPEG） | 190 / 196 | 60 / 68 | —（Mac 上没有） |
| 窗口截图（文本编辑窗口） | 198 / 210 | 68 / 78 | **47 / 51** |
| 控件树（`ax --depth 3` / `getAXState`） | 66 / 71 | **28 / 47** | 49 / 70 |
| 点击（`click`） | 54 / 63 | **12 / 14** | 135 / 175 |
| 输入英文 `abc` | 87 / 118 | **12 / 14** | 41 / 45 |
| 输入中文 `你好abc` | 87 / 115 | **14 / 16** | 9060 / 10560 |
| 按键（`cmd+right` / `super+Right`） | 73 / 96 | **8 / 14** | 14 / 24 |

0.4.1 的截图每次都要重新截、编码 PNG 并写文件，所以窗口截图比 LCU 慢（68 vs 47 ms）。

</details>

<details>
<summary>历史版本对比（v0.2.0 → v0.3.0）</summary>

v0.3.0 新增常驻守护进程（`serve`）、窗口 / 区域截图、`--fast`、`find` / `click-el` / `wait`（提前停止的控件搜索，一次 IPC 取多个属性），以及 `run --continue-on-error`。

在 Apple Silicon Mac（macOS 26+）上用 `scripts/bench.py` 每项跑 15 次的中位数：

| 命令 | v0.2.0 | v0.3.0 | v0.3.0 + 守护进程 |
|---|---:|---:|---:|
| `check` | 31 ms | 29 ms | 22 ms |
| `apps` | 17 ms | 16 ms | 14 ms |
| `windows` | 50 ms | 52 ms | **9 ms** |
| `cursor` | 29 ms | 28 ms | **7 ms** |
| `move` | 63 ms | 60 ms | **9 ms** |
| `ax Finder --depth 3` | 48 ms | 49 ms | **16 ms** |
| `find Finder --role AXMenuBarItem --menu --index 2` | — | 47 ms | **12 ms** |
| `screenshot`（全尺寸 4112×2658 PNG） | 503 ms | 499 ms | 382 ms |
| `screenshot --scale 0.5`（PNG） | 250 ms | 266 ms | 136 ms |
| `screenshot --scale 0.5 --format jpg` | 190 ms | 194 ms | 71 ms |
| `screenshot --fast` | — | 202 ms | **67 ms** |
| `screenshot --region 100,100,400,300` | — | 184 ms | **60 ms** |
| `screenshot --window`（960×660 点窗口，`--scale 0.5`） | — | 212 ms | **80 ms** |

不用守护进程时，v0.3.0 和 v0.2.0 基本持平（差别在测量误差内），时间主要花在进程启动上。守护进程常驻后，查询类命令降到 7–22 毫秒，截图快 1.3–3 倍（省掉了 ScreenCaptureKit 的初始化，并缓存了显示器 / 窗口列表）。v0.2.0 相对 v0.1.0 的提升（`type` 128 字 222 → 73 毫秒、截图 750 → 251 毫秒等）见 v0.2.0 的发布说明。

</details>

## 坐标系

- 非锁定/后台模式下，坐标是**全局点坐标（point）**，原点在**主显示器左上角**，x 向右、y 向下。
- **点和像素**：Retina 屏 1 点 = 2 像素。截图是像素，`click` 用的是点。`screenshot` 会输出 `pixelsPerPoint`，换算方法：`点 = 像素 / pixelsPerPoint`。
- **`--scale`**：在 2 倍屏上用 `--scale 0.5`，图片像素正好等于点坐标，最省事，图片也更小。
- **多显示器**：`xyzlcu displays` 列出每块屏的 `x, y, w, h`（副屏的 x、y 可能是负数）。`screenshot --display 2` 截第 2 块屏，输出里的 `originX/originY` 就是这块屏左上角的全局坐标：`全局 x = originX + 像素x / pixelsPerPoint`。
- 把副屏上的窗口挪回主屏：`xyzlcu movewin "App" 200 100`。

## 退出码

| 码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 参数错误，或找不到应用 / 元素 / 显示器 |
| 2 | 缺少权限（辅助功能或屏幕录制） |
| 3 | 屏幕已锁定，键鼠操作被拒绝 |
| 4 | `find` / `click-el` 找不到控件，`wait` 超时，`type` / `key` 所有输入路径都没生效，或 `--window` 不符被拒绝 |
| 5 | 设置了 `XYZLCU_DAEMON=1` 但连不上守护进程 |
| 6 | 严格后台/全局输入拒绝，或争用断言失败 |

## 常见问题

**截图全黑，或者只有桌面、没有窗口？**
- 全黑：屏幕多半锁了，用 `xyzlcu check` 看 `screenLocked`。
- 只有桌面和菜单栏：负责 App 没有「屏幕与系统录音」权限。
- 某些窗口不在截图里：它可能在另一个桌面（Space）或另一块显示器上，试试 `--display 2`。

**点击、打字没反应？**
- 「辅助功能」权限没授给正确的 App。运行 `xyzlcu whoami`，看 `responsiblePath` 是哪个 App，给它打开开关，然后重启那个 App。
- 改过权限或更新过 App 之后，可能要把开关关掉再打开。
- 输入很久之后才出现、或者丢字：运行 `xyzlcu taps`。如果有 `listenOnly: false` 且 `avgLatencyMs` 很大（几百毫秒以上）的进程，说明它拦着输入事件处理得很慢，常见于屏幕共享（RFBEventHelperd）、语音助手或其他「电脑操控」工具。退出或重启那个程序后再试。
- 某些应用来不及处理快速输入时，加大间隔：`xyzlcu --delay 20 type …`。
- 键盘完全没反应、鼠标却正常：多半是某个拦截键盘的事件监听卡住了（`xyzlcu check` 里 `paths.events.healthy` 为 false，`xyzlcu taps` 里它 `blocking: true`）。`type` / `key` 默认会自动改走辅助功能、直接投递或菜单（见[多条输入路径](#多条输入路径键盘被卡住时)）。要彻底恢复，需要退出或重启那个进程（常见是 Siri 或屏幕共享的 RFBEventHelperd），或者注销重新登录。

**守护进程相关**
- `check` 里 `daemon` 一直是 false：守护进程没启动，或者是旧版本（版本不一致时会自动退回进程内执行）。运行 `xyzlcu serve --status` 看看。
- 守护进程里权限是 false：它是从另一个 App 启动的。`xyzlcu serve --stop` 后，在已授权的终端 / 智能体 shell 里重新 `xyzlcu serve --background`。
- 更新 xyzlcu 后记得 `xyzlcu serve --stop` 再重新启动（版本号不同时会自动退回进程内执行）。
- 进程内截图（`XYZLCU_DAEMON=0`）输出里有 `warning`、要 2 秒左右：同一个 xyzlcu 的守护进程正在运行时，macOS 不给进程内的 ScreenCaptureKit 截图回调，XYZLCU 等 1.5 秒后改用系统 `screencapture`。去掉 `XYZLCU_DAEMON=0` 走守护进程就好（9–31 毫秒）。
- 自己覆盖安装二进制时，先写到临时文件再 `mv` 过去（`build.sh --install` 就是这么做的）；直接 `cp` 覆盖正在使用的已签名二进制，新进程可能被系统直接杀掉（退出码 137）。

**中文输入法会干扰吗？**
- `type` 直接发送 Unicode 字符，不经过输入法，中文输入法开着也能输入正确的文字。
- 但 `key` 发的是物理按键：输入法处于中文模式时，单独按字母会进入候选框。快捷键（`cmd+…`）不受影响。

**`ax` 什么都没输出或很慢？**
- 有些应用（游戏、部分 Electron 应用）辅助功能支持很差。可以减小 `--depth`，或者改用截图定位。
- 每个应用的请求超时是 3 秒，最多输出 3000 个节点。

**按键发到了别的窗口？**
- 全局键盘事件发给当前前台应用。优先用锁定 + AX/pid。未锁定全局路线需要 `--app` / `--pid` 与每批事件前的前台应用一致，或显式 `--allow-global`；单独 `--expect-front` 不构成放行。明确目标与前台不同就拒绝全局输入；检查 `frontmostBefore` / `frontmostAfter`。

## 安全须知

- 有了辅助功能权限，就能模拟任何键鼠操作。只在你信任的环境里使用；不用时可以到系统设置里关掉开关。
- **未锁定全局输入（v0.7.1）**：全局键鼠事件及激活必须显式 `--allow-global`，或指定已经处于前台的 `--app` / `--pid`，并在每批事件前复核；否则创建事件前即返回 `GLOBAL_INPUT_REFUSED`，附实际前台应用。`XYZLCU_ALLOW_GLOBAL=1` 无效。MCP `allowGlobal` 默认 `false`，自动路线也遵守同一安全门；AX/pid 路线不受影响。
- **锁定失败保持拒绝**：`lock` 失败会在共享锁文件及守护进程写入 `lock-failed` 标记，之后输入返回 `LOCK_FAILED`，直到 `unlock` 或成功 `lock`；空/缺失选项值是硬参数错误。
- **被动诊断**：健康检查、`check` 和 probe 路径不会发送全局输入。
- **严格锁**：默认仅 AX/pid；全局输入、剪贴板、前台操作、应用级/未知菜单拒绝。`--allow-global` / `--allow-foreground` 为单条命令的锁策略显式放行，`lock --unsafe` 持续放宽。见[完整副作用审计](#单窗口后台控制single-window-background-control)。
- **输入证据**：输入 JSON 带 `frontmostBefore` / `frontmostAfter`；要同时检查 route 和读回值。`verified:false` 加 `reason` 不代表已确认送达，前台应用没变也不代表目标控件已改变。
- **锁屏保护**：锁屏时 `click / move / drag / scroll / type / key` 返回码 3 并拒绝执行。`--force` 可以强制执行，但不建议。
- **录制文件可能含有你打的字**：只存本机（权限 0600），密码框和锁屏时不录按键；用完删掉，不要分享。回放、`type`、`key` 前同样先确认前台窗口。
- 不要让智能体在付款、删除、发送这类确认框上自动点「确定」。
- XYZLCU 不联网、不收集任何数据，也不修改系统权限数据库。守护进程只监听本机 Unix 套接字，只接受同一用户。
- **不做反检测**：XYZLCU 发出的就是普通的合成键鼠事件，不会伪装成真人、不会随机化节奏、也不会绕过验证码或网站的机器人检测。遇到验证码、「确认你是真人」或其他反机器人检查时，智能体应该停下来交给人处理。

## 已知限制

- 只支持 macOS，只操作当前登录用户的图形会话。锁屏时没法操作，截图也是全黑。
- macOS 13 的整屏/区域截图可回退 `/usr/sbin/screencapture`；指定窗口改用单帧 ScreenCaptureKit SCStream（`method: "screencapturekit-window-stream-once"`），不可用时拒绝。该系统分支已编译，本轮未做运行验收。
- `press` 包含匹配标题、描述、值、identifier 和子文字（不区分大小写）；用角色 + `--list` + `--nth` 区分候选。异步成功表示 AX 动作已启动，不等于菜单项已选中。
- `type` 不经过输入法，需要输入法联想的场景不适用。
- 不支持其他桌面（Space）上的窗口的切换管理。
- 后台锁的限制见[开头章节](#单窗口后台控制single-window-background-control)：AX/pid 支持因应用而异、App Nap、禁用菜单、安全输入框和最小化/其他 Space 捕获受系统限制。
- 守护进程的应用表最多 10 秒刷新一次：后台进程刚变成普通应用、又没有被激活时，`apps` 最多晚 10 秒看到它（按名字找应用时找不到会立刻整体重扫，不受影响）。
- 指定窗口截图只用 ScreenCaptureKit 窗口捕获，圆角外不引入其他应用桌面像素。历史 display-stream-crop 测速描述旧版本。

## 卸载

```bash
xyzlcu serve --stop 2>/dev/null
rm -f ~/.local/bin/xyzlcu ~/.local/bin/xyzlcu-core ~/.local/bin/macctl
rm -rf ~/.xyzlcu
```

然后在「系统设置 > 隐私与安全性」的「辅助功能」和「屏幕与系统录音」里，把不再需要的 App 关掉或移除。

> 想继续用旧名字的话：`ln -sf ~/.local/bin/xyzlcu ~/.local/bin/macctl`

## 更新记录

- **0.7.1**：CLI/守护进程/MCP 未锁定全局输入安全门，显式 `--allow-global` / 前台目标复核、锁定失败标记及被动诊断。
- **0.7.0**：单窗口后台控制、默认严格锁、AX/pid 输入、单窗口截图、争用快照/断言与隔离 TextEdit 验收脚本；AX 聚焦写值、深层控件、滚动/文字等待、TCC 诊断。详见 [CHANGELOG.md](CHANGELOG.md)。

- **0.6.1**：锁定窗口的后台模式和若干修复。
  - **`lock` / `unlock` / `--background`**：锁定一个窗口；只截这个窗口（ScreenCaptureKit，被挡住也行），点击先走辅助功能（聚焦 / 按下 / 选中 / 弹菜单）再投递给进程，输入先走辅助功能再投递按键，⌘ 组合键走菜单，Esc / Return 按对话框的取消 / 默认按钮，滚动直接设滚动条。坐标相对窗口，每个结果带 `route`，每次操作后核对鼠标和前台应用。`drag` / `move` / `activate` 默认拒绝，`--allow-foreground` 放行。MCP 新增 `lock` 工具和 `background` 参数。
  - `screenshot -o` 等同 `--out`；以 `-` 开头的输出路径直接报错，不再生成名叫 `-o` 的文件。
  - 有别的进程托管的打开 / 存储面板时，`key` / `type --app` 发给面板进程。
  - `ax --compact` 先列内容区（网页、文稿、列表），并跳过滚出可视范围的控件（访达 183 → 43 行）。
  - 修复：`record --duration` / `--no-moves` 被当成输出路径；按 id 找窗口时把还开着的窗口误报为已关闭。
- **0.6.0**：守护进程查询更快，给智能体的控件列表更省 token。
  - **应用表**：守护进程自己维护运行中应用的表（启动 / 退出 / 激活 / 隐藏通知更新，最多 10 秒整体刷新一次），不再每次向 LaunchServices 逐个问。`apps` 9.5 → 3.2 毫秒，`ax` / `find` / `click-el` / `press` / 窗口截图都省掉 6–10 毫秒。
  - **控件树批量读**：`ax` 每个控件一次 IPC 取全部属性（文本编辑窗口 27 → 5 毫秒，`ax Finder --menu` 52 → 23 毫秒）。
  - **`ax --compact`**：只列可操作的控件，一行一个，带编号和中心点；`click-el --ref N` 按编号点（需要守护进程）。`ax Finder --menu` 13.7 KB → 0.4 KB。MCP 的 `ax` 工具加 `compact` / `menu` / `text` / `max`，`click_element` 加 `ref`。
  - **窗口截图从主屏流里裁**：窗口没被挡住时直接裁主屏常驻流的最新一帧，第一次截某个窗口 114 → 25 毫秒（`method: "display-stream-crop"`，`XYZLCU_WINDOW_CROP=0` 关闭）。新增 `--window-id N`（MCP `window_id`）。
  - **旧守护进程自动重启**：升级后客户端发现守护进程版本更旧，会停掉它并用新版本重启（只在当前进程有辅助功能 + 录屏权限时做，`XYZLCU_AUTO_RESTART=0` 关闭）；第一次调用多 1 秒左右。
  - 修复：版本不一致退回进程内执行时，`batch` 从标准输入读的脚本会丢失；`run` / `batch` 里有两张 `--stdout` 图时第二张会悄悄覆盖第一张，现在明确报错。
- **0.5.0**：速度大改。
  - **C 小客户端**：`xyzlcu` 变成一个很小的 C 程序，有守护进程时直接转发（空调用 8 → 3 毫秒），没有就 `exec` 同目录的 `xyzlcu-core`。权限归属不变（还是启动它的 App）。安装多了一个文件 `xyzlcu-core`。
  - **截图编码**：并行 PNG 编码（全尺寸 171 → 31 毫秒，保留 ICC 色彩描述），新增 `--format heic`，格式按 `--format` > 文件扩展名 > 默认（`--fast` / 内存里 JPEG，其余 PNG）决定。
  - **预热**：守护进程启动时预开主屏原尺寸和半尺寸截图流（第一次截图 190–220 → 24–37 毫秒），`XYZLCU_PREWARM=0` 关闭，`XYZLCU_PREWARM_SCALES` / `XYZLCU_PREWARM_IDLE` 可调。每个缩放比例一个流，GPU 缩放。
  - **二进制协议**：客户端和守护进程之间图片按原始字节传（长度前缀），不再 base64；对外的 JSON / MCP 不变。
  - **批量**：MCP 新增 `batch` 工具；`run` 一次 3 步 25 → 12 毫秒。
  - **`--diff`**：只返回变化的区域（命令行和 MCP 都支持，需要守护进程或 MCP）。
  - **守护进程启动**：文件锁保证只有一个守护进程，`serve` 重复运行直接返回 0，`kill -9` 留下的旧套接字自动处理，新增 `serve --background`；`serve --stop` 能停掉旧版本。
  - 修复：未知的 `--选项` 不再被当成截图文件名。
- **0.4.2**：截图更快、可以只在内存里出图：`--base64` / `--stdout` / `--out` / `--timing`；守护进程按需保持 ScreenCaptureKit 截图流（窗口截图 68 → 23–35 毫秒，比 LCU 的 51 毫秒快），缓存屏幕录制权限检查和窗口内容列表，输入读回的轮询间隔缩短到 5 毫秒。新增 `xyzlcu mcp`（stdio MCP 服务器，13 个工具，截图直接返回图片）。README 新增[支持的智能体](#支持的智能体)。修复：客户端只连上不发请求就断开（比如探测守护进程在不在）时，守护进程会因 SIGPIPE 退出。
- **0.4.1**：进程内截图等 ScreenCaptureKit 回调时会处理主线程事件；回调超时只等一次（1.5 秒）就改用 `screencapture` 并给出 `warning`，不再卡 10 秒以上。守护进程里的 `apps` 不再固定等 20 毫秒（42 → 17 ms）。新增和 LCU 的对比测试（`scripts/bench.py --lcu`、`scripts/bench_lcu.mjs`）。
- **0.4.0**：多条输入路径（辅助功能写值、直接投递、菜单、粘贴）、事件流健康检查、`insert` / `settext` / `value` / `menu` / `taps`、只监听的录制与回放。
- 更早的版本见 [Releases](https://github.com/brandy2015/XYZLCU/releases)。

## 致谢

XYZLCU 借鉴自 Amont Labs 的 **[LCU（Local Computer Use）](https://github.com/amontlabs/lcu)**：让本机上任何智能体都能看屏幕、点击、打字，用截图配合辅助功能树来定位，以及「Local Computer Use」这个名字本身，都受它启发。感谢 Amont Labs 把 LCU 开源出来。

XYZLCU 是独立实现，没有复制 LCU 的代码。LCU 以 MIT 许可证发布，Copyright (c) 2026 Amont Labs。

## 许可证

[MIT](LICENSE) © 2026 XYZTech
