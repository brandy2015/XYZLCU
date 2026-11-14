# XYZLCU TODO

> 0.7.0：已勾选表示实现完成；本轮仅做无 GUI 自测和编译，真实应用回归仍需在已授权的 macOS 会话验收。`responsibleProcess` 保留旧路径字符串，结构化名称/路径/bundle id 在 `responsibleProcessInfo`。

> 来源：2026-11-14 在 LM Studio 0.4.28（Electron）里接入 `xyzlcu mcp` 的实测。只记录，不代表已排期。

## P0 · 0.7.0 单窗口后台控制验收

- [x] 默认严格 `lock` / MCP `lock`，目标 pid/window 不一致拒绝；全局输入、剪贴板、前台操作和作用域不明菜单无静默回退。
- [x] 单条命令 `--allow-global` / `--allow-foreground`、持久 `lock --unsafe`；严格锁下无显式放行不能 `--no-lock`；锁损坏拒绝执行，目标退出保留锁直到显式恢复。
- [x] 审计 type/key/click/drag/scroll/menu/set-text/press/select/paste/screenshot/open/activate/hide/movewin/replay/request/check --probe，双语 README 列出副作用与拒绝策略。
- [x] 指定窗口仅用 ScreenCaptureKit 桌面独立窗口过滤器；覆盖窗口、pid/id 定位、窗口相对坐标；禁止显示流裁剪/全局截图回退，`--cli` 窗口目标明确拒绝。
- [x] 公开 `CGEvent.postToPid`，窗口号、坐标换算、独立事件源和 down/up 时间；目标内 AX 聚焦、写值/选区/pid Unicode；route / verified / reason 证据。
- [x] JSON 对象带 frontmostBefore/frontmostAfter/contention；`--assert-no-contention` 检测到变化则失败（仅前后快照）。
- [x] 隔离 socket/锁的 `scripts/bg_selftest.sh`：`open -g` TextEdit、AX 输入、pid 输入、AX 编辑菜单、窗口截图与内容/前台/鼠标断言，PASS/FAIL 表。
- [ ] 在获 AX/录屏授权的真实 Mac 执行 `./scripts/bg_selftest.sh`；本轮沙盒不运行 GUI，不能据编译/纯逻辑测试勾选。
- [ ] 手工测试两个同进程窗口：锁定一个并覆盖，确认输入/AX 值/截图均不落到另一窗口；关闭目标后必须拒绝而非改找窗口。
- [ ] 对 Safari/WKWebView、Electron、原生 Cocoa 分别记录 AX/pid 支持、verified/reason 和 App Nap 延迟；被忽略的 pid 事件不算成功。
- [ ] 覆盖窗口、部分屏外、最小化、其他 Space、受保护内容逐项核对图像及明确失败；不切 Space、不取消最小化；macOS 13 单帧 SCStream 与 14+ 捕获路线分别验收。
- [ ] 检查每个拒绝路径无 HID、指针移动、激活、共享剪贴板改动；确认普通 check 不发探针、严格 check --probe 拒绝。
- [ ] 手工验证 contention 断言及 MCP 宿主 TCC 归属；记录前后快照无法发现短暂切换、异步 worker 完成及之后延迟效果/争用未被父进程监测这些限制。

## P0 · 点击 / 按键在 Electron（Chromium）里不生效

**现象**：LM Studio 聊天框的发送按钮，用 `click x y`、`click-el --click`（events-hid）、`--double`、`lock` 后的 pid-mouse、`press`（AXPress）、`drag` 都点不发；回车、⌘回车只插入换行。
用一段最简单的 Swift CGEvent（moved → 等 150 ms → down → 等 90 ms → up，`.hidSystemState` + `.cghidEventTap`，clickState=1）**一次就发出去了**。

**怀疑根因**（`Sources/xyzlcu/main.swift`）：
- `click()`（~L104）：`mouse(down)` 和 `mouse(up)` 之间 **没有任何间隔**，move 后也只等 `stepDelay`（默认 2 ms）。Chromium 很可能把 0 ms 的 down/up 当成无效点击，或者 hover 还没更新、按钮还不是 pressed 状态。
- `key()`（~L140）：keyDown / keyUp 同样是紧挨着发出的，回车不触发提交，多半是同一个原因。

**要做**：
- [x] down 和 up 之间默认留 40–80 ms 的间隔，move 后等 hover 生效（约 50–100 ms）；加 `--hold ms` 参数和环境变量 `XYZLCU_CLICK_HOLD`。
- [x] keyDown 和 keyUp 之间默认留 20–40 ms；加 `--hold ms` 参数。
- [x] AX/pid 点击后有界核对 AX 状态变化，输出 `verified` / `reason`；无法核对不等于未送达。严格锁绝不回退 HID，已报告执行但读回不明时不盲目重试。
- [ ] 写回归测试：LM Studio、VS Code、Slack、Chrome 网页里的 `<button>`、Electron 里的 textarea 提交。
- [ ] 用 `--double` 和多次点击后，LM Studio 里整页文字被选中了，怀疑有 mouseUp 丢失或 clickState 不对；排查有没有残留的按下状态。

## P1 · 由 MCP 宿主拉起时的权限问题（TCC）

**现象**：由 LM Studio 拉起的 `xyzlcu-core mcp` 截图失败；`check` 显示屏幕录制、辅助功能、输入监控都是 false，因为 TCC 的“负责进程”是 LM Studio，不是 xyzlcu。终端里跑同一个二进制，这三项权限都是好的。

- [x] 截图、点击等工具失败时，在 MCP 返回里直接写明原因：“负责进程 = LM Studio，请在 系统设置 › 隐私与安全性 › 屏幕录制 / 辅助功能 里打开 LM Studio，然后重启它”。现在模型要再调一次 `check` 才能知道原因。
- [x] `check` 输出加一个 `responsibleProcess` 字段（名称、路径、bundle id）。
- [x] 加 `xyzlcu request --open`：直接打开对应的系统设置页。
- [ ] 评估“守护进程模式”：MCP 只是一个薄客户端，真正干活的是用户在终端授权过的 `xyzlcu serve`，这样就不用给每个宿主（LM Studio、Claude Desktop、Cursor…）分别授权。客户端和 serve 之间已经有 `~/.xyzlcu/sock` 可用。

## P1 · MCP 模式体验

- [x] MCP 模式下自动启动或复用守护进程。现在提示“没有守护进程，编号不会保留，--ref 用不了”，导致 `click-el --ref` 在 MCP 里基本用不上；也可以直接在 MCP 进程内存里保存 ref 表。
- [x] `screenshot` 在 MCP 里默认走 `--fast`（jpg、0.5 缩放），并加 `max_tokens` 或 `max_side` 参数。本地模型上下文常只有 8K–32K，一张原图就会撑爆上下文。
- [x] 加一个只返回文字的观察工具（比如 `observe`：前台应用、窗口标题、`ax --compact --text` 摘要），给不支持视觉的本地模型用。
- [x] 工具描述写短一些、写清楚：少量工具配上清楚的参数说明，27B 级别的本地模型调用起来更稳。
- [x] `check` 报“键盘被 Siri 进程拦截”，但同一时刻终端里的键盘输入是正常的，排查是不是误报。

## P2 · AX / 坐标

- [x] `ax --compact` 和 `find` 输出 `AXEnabled`、`AXFocused`，模型就能分辨按钮是禁用了还是点没生效。
- [x] 截图结果里 pixel 和 point 两套坐标容易混。可以在 MCP 截图结果里直接给出“图上 (x,y) → 全局点坐标”的换算公式，或者让 `click` 接受 `--image-coords` 参数自动换算。
- [x] `type` 走 `ax-selected-text` 时 Electron textarea 会报“写入后内容没变”，再回退到 events-pid。Electron 优先 AX 聚焦后 `set-text`，再试 pid Unicode；严格锁不自动走 paste。

## P2 · 文档

- [ ] README 增加 LM Studio 接入一节：`~/.lmstudio/mcp.json` 示例（command 要写绝对路径）、在聊天里开启 `mcp/xyzlcu`、给 LM Studio 授权、需要支持工具调用的模型、上下文建议 ≥32K、每次调用前的 Proceed 确认，以及“Always allow”的风险。
- [ ] 安全提示：LM Studio 的 API 默认可能监听 `0.0.0.0` 且不需要 token。如果在服务器设置里打开“允许 API 使用插件”，局域网里任何人（以及开了 CORS 的网页）都能通过 xyzlcu 控制这台电脑。建议只监听本机、开 token，或者干脆不打开。
