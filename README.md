# XYZLCU

**中文** | [English](README.en.md)

**XYZLCU（XYZ Local Computer Use）** 是一个零依赖的 macOS 图形界面控制命令行工具。只要能执行 shell 命令，不管是 AI 智能体（Claude Code、Codex、任何会跑命令的 Agent）还是你自己写的脚本，就能看屏幕、点鼠标、打字、按快捷键、读取界面结构并按下按钮。整个工具只有一个 Swift 源文件和一个二进制，不用 Python、Node、Homebrew，也不需要任何第三方库。

> 灵感来自 [amontlabs/lcu](https://github.com/amontlabs/lcu) 的思路，但这是**独立实现**：没有共用任何代码，也**不需要 ChatGPT / Codex** 桌面应用或其运行时。

## 功能

- 📸 **截屏**：截整块屏、单个窗口（`--window`）或一块区域（`--region`），可缩小；`--fast` 一键出小 JPEG；会输出点坐标与像素的换算关系
- 🖱 **鼠标**：单击、右键、双击、移动、拖拽、滚动
- ⌨️ **键盘**：直接输入 Unicode 文字（中文、emoji 都行，不经过输入法），支持组合键（`cmd+shift+4`）
- 🌳 **辅助功能树**：导出任意应用窗口的控件树（角色、标题、值、坐标）；`find` 按角色/标题直接返回坐标和中心点，`click-el` 一步找到并按下，`wait` 等控件出现或消失
- 🪟 **应用与窗口**：列出、打开、激活、隐藏应用；列出窗口；移动和调整窗口大小；列出显示器
- 🛣 **多条输入路径**（v0.4.0）：先实测事件流是否卡住，再在辅助功能写值、键盘事件、直接投递进程、菜单粘贴之间自动挑一条走得通的，输出里写明实际走的路
- ⏺ **录制 / 回放**：只监听地录下键鼠操作（不拦截输入，密码框和锁屏时不录按键），按原节奏回放
- 🔒 **锁屏保护**：屏幕锁定时拒绝键鼠操作，防止把字打进锁屏密码框
- ⚡ **常驻守护进程**：`xyzlcu serve &` 之后，命令自动转发给它，省掉进程启动和权限检查开销，大部分命令 7–20 毫秒
- 🧾 **输出好解析**：结果是 JSON 或一行 `ok`，出错时返回明确的退出码

## 快速开始（3 步）

**1. 安装**（二选一）

```bash
# A. 下载编译好的 universal 二进制（Apple Silicon + Intel）
mkdir -p ~/.local/bin && curl -fsSL https://github.com/brandy2015/XYZLCU/releases/latest/download/xyzlcu-macos-universal.zip -o /tmp/xyzlcu.zip \
  && unzip -o /tmp/xyzlcu.zip -d ~/.local/bin && chmod +x ~/.local/bin/xyzlcu && xattr -d com.apple.quarantine ~/.local/bin/xyzlcu 2>/dev/null; rm -f /tmp/xyzlcu.zip

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

也可以用 Swift Package Manager 编译：`swift build -c release`，产物在 `.build/release/xyzlcu`。

## 系统要求

- macOS 13 Ventura 及以上（编译目标 `macos13`；在 macOS 27 上实测通过）
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

`xyzlcu request` 会主动弹出这两个系统授权窗口。XYZLCU 不会修改 TCC 数据库，也不会尝试绕过权限。

## 命令一览

| 命令 | 说明 | 示例 |
|---|---|---|
| `check [--probe]` | 权限、锁屏状态、各输入路径是否可用（见[多条输入路径](#多条输入路径键盘被卡住时)） | `xyzlcu check` |
| `request` | 弹出系统授权窗口 | `xyzlcu request` |
| `whoami` | 进程链与负责 App | `xyzlcu whoami` |
| `version` | 版本号 | `xyzlcu version` |
| `screenshot [path] [--scale S] [--display N] [--format png\|jpg] [--quality Q]` | 截屏（默认 PNG，JPEG 更快更小） | `xyzlcu screenshot /tmp/s.jpg --scale 0.5` |
| `screenshot … --fast` | 快速截图：JPEG、质量 0.6、缩放 0.5 | `xyzlcu screenshot --fast` |
| `screenshot … --window "App" [--title T]` | 只截某个应用的窗口（默认它最前面的窗口） | `xyzlcu screenshot /tmp/w.png --window Safari` |
| `screenshot … --region x,y,w,h` | 只截一块区域（全局点坐标） | `xyzlcu screenshot /tmp/r.png --region 100,100,400,300` |
| `displays` | 列出显示器及其坐标范围 | `xyzlcu displays` |
| `click x y [--right] [--double]` | 点击 | `xyzlcu click 500 300 --double` |
| `move x y` | 移动鼠标 | `xyzlcu move 800 600` |
| `drag x1 y1 x2 y2` | 按住左键拖动 | `xyzlcu drag 100 100 400 400` |
| `scroll dx dy` | 滚动，单位是行，正 dy 向上 | `xyzlcu scroll 0 -5` |
| `cursor` | 当前鼠标位置 | `xyzlcu cursor` |
| `type "文字" [--app "App"] [--window 标题] [--via auto\|ax\|events\|pid\|paste]` | 输入 Unicode 文本，输出 JSON（`path` = 实际走的路、`verified` = 是否读回核对过）。默认 auto 自动挑路 | `xyzlcu type --app TextEdit --window 笔记 "你好 😀"` |
| `insert "App" [定位] "文字"` | 用辅助功能在焦点处插入文字（写 AXSelectedText），不经过键盘事件，写完读回核对 | `xyzlcu insert TextEdit --window 笔记 "你好"` |
| `settext "App" [定位] "文字"` | 用辅助功能整体替换文本框内容（写 AXValue），写完读回核对 | `xyzlcu settext Safari --role AXTextField --title 搜索 "XYZLCU"` |
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
| `find "App" [--role R] [--title T] [--contains] [--index N\|--all] [--window T] [--menu]` | 找控件，返回 role、title、frame、center；找到就停 | `xyzlcu find TextEdit --role AXButton --title 保存` |
| `click-el "App" --role R --title T [--click] [--right] [--double]` | 找到控件并按下（AXPress，不行就点中心） | `xyzlcu click-el TextEdit --role AXButton --title 保存` |
| `press "App" "标题"` | 按标题找到控件并按下（旧写法；新脚本建议用 `click-el`） | `xyzlcu press TextEdit "取消"` |
| `wait "App" --title T [--role R] [--timeout 秒] [--gone]` | 等控件出现（或 `--gone` 消失），默认 5 秒超时 | `xyzlcu wait TextEdit --role AXSheet --timeout 3` |
| `wait 毫秒` / `sleep 毫秒` | 等待固定时间 | `xyzlcu sleep 300` |
| `taps` | 列出系统事件监听（排查输入卡顿/丢失），`blocking` 标出可疑的 | `xyzlcu taps` |
| `record [--out f.jsonl] [--duration 秒] [--no-moves]` | 只监听地录制键鼠，见[录制与回放](#录制与回放) | `xyzlcu record --duration 30` |
| `replay f.jsonl [--speed N] [--no-keys] [--force]` | 回放录制 | `xyzlcu replay rec.jsonl --no-keys` |
| `run [--continue-on-error] '命令; 命令; …'` | 一次执行多条命令（`;` 或换行分隔） | `xyzlcu run 'click-el TextEdit --title 保存; wait TextEdit --role AXSheet; key return'` |
| `batch [--continue-on-error] [文件]` | 从文件或 stdin 逐行读命令执行 | `printf 'type a\nkey return\n' \| xyzlcu batch` |
| `serve [--status\|--stop]` | 启动 / 查看 / 停止常驻守护进程，见[守护进程](#守护进程) | `xyzlcu serve &` |

补充：

- **应用名**可以写本地化名称（「访达」）、英文名（`Finder`）或 bundle ID（`com.apple.finder`）。
- **按键名**：`a–z`、`0–9`、常用符号、`return`/`enter`、`tab`、`space`、`delete`/`backspace`、`forwarddelete`、`esc`、`up`/`down`/`left`/`right`、`home`/`end`/`pageup`/`pagedown`、`f1–f12`。修饰键：`cmd`、`shift`、`opt`/`alt`、`ctrl`、`fn`。
- **`ax` 输出格式**：`角色(子角色) title="…" desc="…" value="…" id="…" [x,y 宽x高]`。中括号里的就是点坐标，中心点 = `(x + 宽/2, y + 高/2)`。
- **`find` / `click-el` / `wait`**：`--title` 也可以写成第二个参数（`xyzlcu find TextEdit 保存`）。标题按完全匹配（不区分大小写）比对 title、description、value 和 identifier，加 `--contains` 改为包含匹配。先搜当前焦点窗口，再搜其他窗口；`--menu` 才搜菜单栏。找到第 `--index` 个（默认第 1 个）就立刻停止，不会遍历整棵树。找不到返回退出码 4。
- **`click-el` / `press`** 优先执行 AXPress，按不了就点控件中心；加 `--click`（或 `--right`、`--double`）强制用鼠标点中心。
- **`wait "App" …`** 先 20 毫秒检查一次，间隔逐步加到 250 毫秒，超时返回退出码 4。
- **`type` / `key --app "App"`**：把键盘事件直接投递给这个应用的进程（`CGEventPostToPid`），而不是发给系统输入流。前台被别的窗口抢走时也不会打错地方，但仍然要先确认这个应用的焦点窗口是你要的。
- **`run` / `batch`**：引号规则和 shell 一样（`"…"`、`'…'`、`\` 转义），`#` 开头的行是注释。默认遇到第一个出错的命令就停止，退出码同那条命令，错误信息会写明是第几步；加 `--continue-on-error` 则继续执行后面的步骤，最后返回最后一个出错步骤的退出码（全部成功为 0）。里面可以混用 `find`、`click-el`、`wait`、`sleep`。
- **`--delay N`**：鼠标/键盘事件之间的间隔（毫秒，默认 2）。个别应用反应慢、丢字时调大，例如 `xyzlcu --delay 20 type …` 或 `XYZLCU_DELAY=20`。
- **截图**：macOS 14+ 走 ScreenCaptureKit（进程内截图，直接按 `--scale` 输出目标尺寸；`--window` 只截那个窗口，被挡住也能截到；`--region` 只截那块区域），否则或加 `--cli` 时退回系统 `screencapture`。输出里的 `method` 字段会告诉你走的哪条路，`originX/originY` 是图片左上角的全局点坐标。

## 多条输入路径（键盘被卡住时）

有时系统里某个进程的键盘事件监听（event tap）卡住了：键盘事件发出去迟迟不到应用，甚至排队到很久以后才一起冒出来，鼠标却正常。v0.4.0 起，`type`、`key` 会先检查事件流是否健康，再挑一条走得通的路，并在输出 JSON 的 `path` 里写明实际走的是哪条。

**健康检查**

- 读系统事件监听列表（`CGGetEventTapList`）：主动拦截（不是只监听）、平均延迟超过 1000 毫秒（`XYZLCU_TAP_THRESHOLD_MS` 可改）的监听算可疑。
- 这些统计是历史值：刚卡住的监听数字还很低，早已恢复的数字却可能一直很高。所以键盘每次都**实测**：发一个带标记的「右 Shift 松开」事件（对任何应用都没有效果），用排在最后的只监听监听计时，400 毫秒内走完整条事件流就算健康（正常 1–30 毫秒）。鼠标只在统计可疑时实测（原地发一个 mouseMoved）。统计偏高、实测正常的监听列在 `check` 的 `staleTapStats` 里，按健康处理。
- 守护进程里结果缓存 1.5 秒；`check` 总是重新检测，`check --probe` 连鼠标也实测。`XYZLCU_PROBE=0` 关闭实测，只看统计。
- `XYZLCU_EVENTS_HEALTH=bad` / `good` 强制当作卡住 / 正常，用来测试备用路径（守护进程模式下也生效，客户端会把这些环境变量随请求转发过去）。

**各条路**

| `path` | 做法 | 经过 HID 事件流的监听？ | 应用要在前台？ | 核对 |
|---|---|---|---|---|
| `ax-selected-text` | 辅助功能写焦点元素的 `AXSelectedText`（在光标处插入） | 否 | 否 | 读回 `AXValue` |
| `events-hid` | CGEvent 发到系统 HID 事件流（`type` / `key` 不带 `--app`） | 是 | 是 | 300 毫秒内读回 |
| `events-pid` | `CGEventPostToPid` 直接投递给应用进程（带 `--app`，或 `--via pid`） | 否 | 否 | 600 毫秒内读回 |
| `paste-menu` | 文字放进剪贴板，AXPress 应用的「编辑>粘贴」菜单项，核对后恢复剪贴板 | 否 | 否 | 读回 |
| `menu` | `key` 专用：在菜单栏里找快捷键相同的菜单项并 AXPress（如 `cmd+a` → 「编辑>全选」） | 否 | 见下文 | — |
| `ax-menu` | `menu` 命令：按菜单路径 AXPress | 否 | 见下文 | — |

**`type --via auto`（默认）**

- 事件流正常：焦点是标准文本框（`AXTextField` / `AXTextArea` / `AXComboBox` / `AXSearchField`）时走 `ax`，否则走 `events`。
- 事件流卡住：依次试 `ax` → `pid` → `paste`，每一步都读回核对，没生效才换下一条。卡住时**不会**用 `events-hid`，那些按键会排队，事件流恢复后突然打出来。
- 读不到输入框内容、没法核对时，就停在当前这条路，不再换路，避免同一段文字被输入两次。
- 所有路都没生效：退出码 4，错误里列出每条路的结果（`tried`）。
- `paste` 没核对成功时**不恢复剪贴板**（输出 `clipboardRestored: false`），避免排队中的粘贴贴出旧内容。
- `--via ax|events|pid|paste` 指定一条路；环境变量 `XYZLCU_TYPE_VIA` 改默认值。
- `--window 标题`：焦点元素不在标题含这段文字的窗口里就拒绝输入（退出码 4），防止打进别的文稿。

**`key --via auto`（默认）**

- 事件流正常：`events`（带 `--app` 时是 `events-pid`）。
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
xyzlcu settext TextEdit --role AXTextArea --window 我的笔记 "整体替换"   # 写 AXValue
xyzlcu value TextEdit --window 我的笔记                         # 读回核对
```

- 定位：默认是应用当前的焦点元素；也可以用 `--role` / `--subrole` / `--title`（或 `--id`）/ `--index` 指定。`--window 标题` 会检查元素所在窗口，不对就拒绝写入。
- 每次写完都会读回 `AXValue` 核对，`verified: true` 才算成功；不一致时退出码为 1。
- 原生 Cocoa 文本框（文本编辑、备忘录、大多数输入框）都支持；有些网页和自绘界面不支持写值，这时只能靠 `pid` / `paste`。

**`check` 输出**：`paths` 里列出 events / mouse / ax / menu / pid / paste / record 是否可用（events、mouse 带实测的 `probeMs`），`typeOrder` / `keyOrder` 是当前 auto 会按什么顺序试，`keyboardBlockedBy` 是卡住的监听。

**限制**：`events-pid`、`menu`、`paste` 绕开的是 HID 事件流上的监听；如果应用自己的主线程卡住了，哪条路都没用。要真正修好，需要重启卡住的进程（`xyzlcu taps` 里 `blocking: true` 的那个）或者注销/重启。XYZLCU 不会替你结束任何进程。

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
xyzlcu serve &          # 在智能体/终端自己的 shell 里启动
xyzlcu serve --status   # 查看：pid、版本、运行时长、权限、负责 App
xyzlcu check            # 输出里 "daemon": true 表示已经在走守护进程
xyzlcu serve --stop     # 停止
```

- 启动后，所有命令（包括 `run`、`batch`）**自动转发**给守护进程，用法和输出完全一样。连不上或版本不一致时自动退回进程内执行。
- `XYZLCU_DAEMON=0`：不用守护进程；`XYZLCU_DAEMON=1`：必须用守护进程，连不上就返回退出码 5。
- 套接字在 `~/.xyzlcu/sock`（目录权限 0700，套接字 0600），只接受**同一用户**的连接（`getpeereid` 校验），不监听网络端口。可以用 `XYZLCU_SOCKET` 改路径。
- 守护进程里同样有锁屏保护和权限检查，相对路径按调用方的当前目录解析。
- **权限（TCC）**：守护进程使用的是**启动它的那个 App** 的权限，所以要在智能体或终端自己的 shell 里运行 `xyzlcu serve &`，这样负责 App 和直接运行命令时一样。用 `xyzlcu serve --status` 看 `responsibleProcess`。
- 想开机自动启动，可以自己写一个 LaunchAgent（`~/Library/LaunchAgents/*.plist`，`ProgramArguments` 为 `xyzlcu serve`）。注意这时负责进程是 launchd 启动的 xyzlcu 本身，要在系统设置里单独给 xyzlcu 二进制授权。XYZLCU 不会替你安装 LaunchAgent。

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

## 配合 AI 智能体使用

任何会执行 shell 命令的智能体都能用，比如 Claude Code、Codex CLI，或者你自己的 Agent。可以把下面这段放进系统提示词或 `AGENTS.md` / `CLAUDE.md`：

```text
你可以用 `xyzlcu` 操作这台 Mac 的图形界面。规则：
0. 会话开始时运行一次 `xyzlcu serve &`，之后每条命令都更快（`xyzlcu check` 里 daemon 为 true）。
1. 开始前运行 `xyzlcu check`。如果 screenLocked 为 true 或权限缺失，停下来告诉用户。
2. 循环：观察 → 定位 → 操作 → 验证。
   - 观察：优先用 `xyzlcu find "App" --role AXButton --title 保存` 或 `xyzlcu ax "App" --depth 6`；需要看画面时用 `xyzlcu screenshot --fast`，只看一个窗口用 `--window "App"`，只看一块用 `--region x,y,w,h`。
   - 定位：find 直接给出 center；用截图时按 pixelsPerPoint 和 originX/originY 换算成点坐标。
   - 操作：能 `xyzlcu click-el "App" --role R --title T` 就不用 click 坐标。
   - 等待：用 `xyzlcu wait "App" --title T --timeout 5` 等界面变化，不要固定 sleep。
   - 验证：操作后重新 find / ax 或截图，确认结果。
3. 每次 `type` 或 `key` 之前先 `xyzlcu activate "目标App"`，再用 `xyzlcu apps` 确认它是前台（active: true）。键盘输入会发给当前前台应用。打字优先用 `xyzlcu type --app "App" --window "窗口标题" "文字"`：焦点不在那个窗口就拒绝；看输出的 path 和 verified 确认结果。
4. 付款、删除、发送、提交这类不可撤销的操作，先征得用户同意。
5. 不要用 --force 绕过锁屏保护。
6. 已经确认过前台、要连续做几步时，可以合成一条 `xyzlcu run 'click-el App --title 搜索; type 你好; key return; wait App --title 结果'`，比分开调用快好几倍。
7. 遇到验证码、「确认你是真人」或其他反机器人检查时，停下来交给用户处理，不要尝试绕过。
```

## 性能

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

自己测：`python3 scripts/bench.py build/xyzlcu`；加 `--daemon` 会先启动守护进程再测；加 `--gui` 会新建一个临时文本编辑文稿来测点击和输入，结束后自动关闭。

## 坐标系

- 所有坐标都是**全局点坐标（point）**，原点在**主显示器左上角**，x 向右、y 向下。
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
- 守护进程里权限是 false：它是从另一个 App 启动的。`xyzlcu serve --stop` 后，在已授权的终端 / 智能体 shell 里重新 `xyzlcu serve &`。
- 更新 xyzlcu 后记得 `xyzlcu serve --stop` 再重新启动（版本号不同时会自动退回进程内执行）。
- 自己覆盖安装二进制时，先写到临时文件再 `mv` 过去（`build.sh --install` 就是这么做的）；直接 `cp` 覆盖正在使用的已签名二进制，新进程可能被系统直接杀掉（退出码 137）。

**中文输入法会干扰吗？**
- `type` 直接发送 Unicode 字符，不经过输入法，中文输入法开着也能输入正确的文字。
- 但 `key` 发的是物理按键：输入法处于中文模式时，单独按字母会进入候选框。快捷键（`cmd+…`）不受影响。

**`ax` 什么都没输出或很慢？**
- 有些应用（游戏、部分 Electron 应用）辅助功能支持很差。可以减小 `--depth`，或者改用截图定位。
- 每个应用的请求超时是 3 秒，最多输出 3000 个节点。

**按键发到了别的窗口？**
- 键盘事件发给当前前台应用。先 `activate`，再用 `apps` 确认。

## 安全须知

- 有了辅助功能权限，就能模拟任何键鼠操作。只在你信任的环境里使用；不用时可以到系统设置里关掉开关。
- **`type` / `key` 前一定确认前台应用**，否则文字可能打进别的文档，快捷键也可能关掉别的窗口。
- **锁屏保护**：锁屏时 `click / move / drag / scroll / type / key` 返回码 3 并拒绝执行。`--force` 可以强制执行，但不建议。
- **录制文件可能含有你打的字**：只存本机（权限 0600），密码框和锁屏时不录按键；用完删掉，不要分享。回放、`type`、`key` 前同样先确认前台窗口。
- 不要让智能体在付款、删除、发送这类确认框上自动点「确定」。
- XYZLCU 不联网、不收集任何数据，也不修改系统权限数据库。守护进程只监听本机 Unix 套接字，只接受同一用户。
- **不做反检测**：XYZLCU 发出的就是普通的合成键鼠事件，不会伪装成真人、不会随机化节奏、也不会绕过验证码或网站的机器人检测。遇到验证码、「确认你是真人」或其他反机器人检查时，智能体应该停下来交给人处理。

## 已知限制

- 只支持 macOS，只操作当前登录用户的图形会话。锁屏时没法操作，截图也是全黑。
- macOS 13 上没有 ScreenCaptureKit 截图，会退回 `/usr/sbin/screencapture`（`--window` 用 `-l 窗口号`，`--region` 用 `-R`）。
- `press` 只按完全匹配（不区分大小写）的标题、描述、值或 identifier 找控件，返回第一个匹配项；需要更精确时用 `find` / `click-el` 的 `--role`、`--index`、`--window`。
- `type` 不经过输入法，需要输入法联想的场景不适用。
- 不支持其他桌面（Space）上的窗口的切换管理。

## 卸载

```bash
xyzlcu serve --stop 2>/dev/null
rm -f ~/.local/bin/xyzlcu ~/.local/bin/macctl
rm -rf ~/.xyzlcu
```

然后在「系统设置 > 隐私与安全性」的「辅助功能」和「屏幕与系统录音」里，把不再需要的 App 关掉或移除。

> 想继续用旧名字的话：`ln -sf ~/.local/bin/xyzlcu ~/.local/bin/macctl`

## 许可证

[MIT](LICENSE) © 2026 XYZTech
