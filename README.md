# XYZLCU

**中文** | [English](README.en.md)

**XYZLCU（XYZ Local Computer Use）** 是一个零依赖的 macOS 图形界面控制命令行工具。只要能执行 shell 命令，不管是 AI 智能体（Claude Code、Codex、任何会跑命令的 Agent）还是你自己写的脚本，就能看屏幕、点鼠标、打字、按快捷键、读取界面结构并按下按钮。整个工具只有一个 Swift 源文件和一个二进制，不用 Python、Node、Homebrew，也不需要任何第三方库。

> 灵感来自 [amontlabs/lcu](https://github.com/amontlabs/lcu) 的思路，但这是**独立实现**：没有共用任何代码，也**不需要 ChatGPT / Codex** 桌面应用或其运行时。

## 功能

- 📸 **截屏**：截主屏或指定显示器，可缩小；会输出点坐标与像素的换算关系
- 🖱 **鼠标**：单击、右键、双击、移动、拖拽、滚动
- ⌨️ **键盘**：直接输入 Unicode 文字（中文、emoji 都行，不经过输入法），支持组合键（`cmd+shift+4`）
- 🌳 **辅助功能树**：导出任意应用窗口的控件树（角色、标题、值、坐标），不截图也能找到按钮；可以按标题直接 `press`
- 🪟 **应用与窗口**：列出、打开、激活、隐藏应用；列出窗口；移动和调整窗口大小；列出显示器
- 🔒 **锁屏保护**：屏幕锁定时拒绝键鼠操作，防止把字打进锁屏密码框
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
| `check` | 权限和锁屏状态 | `xyzlcu check` |
| `request` | 弹出系统授权窗口 | `xyzlcu request` |
| `whoami` | 进程链与负责 App | `xyzlcu whoami` |
| `version` | 版本号 | `xyzlcu version` |
| `screenshot [path] [--scale S] [--display N] [--format png\|jpg] [--quality Q]` | 截屏（默认 PNG，JPEG 更快更小） | `xyzlcu screenshot /tmp/s.jpg --scale 0.5` |
| `displays` | 列出显示器及其坐标范围 | `xyzlcu displays` |
| `click x y [--right] [--double]` | 点击 | `xyzlcu click 500 300 --double` |
| `move x y` | 移动鼠标 | `xyzlcu move 800 600` |
| `drag x1 y1 x2 y2` | 按住左键拖动 | `xyzlcu drag 100 100 400 400` |
| `scroll dx dy` | 滚动，单位是行，正 dy 向上 | `xyzlcu scroll 0 -5` |
| `cursor` | 当前鼠标位置 | `xyzlcu cursor` |
| `type "文字"` | 输入 Unicode 文本 | `xyzlcu type "你好 Hello 😀"` |
| `key 组合…` | 按键 / 组合键，可以一次多个 | `xyzlcu key cmd+s` · `xyzlcu key cmd+c cmd+v` |
| `apps` | 正在运行的图形界面应用 | `xyzlcu apps` |
| `open "App"` | 打开应用 | `xyzlcu open "TextEdit"` |
| `activate "App"` | 切换到前台 | `xyzlcu activate Finder` |
| `hide "App"` | 隐藏应用（相当于 cmd+h） | `xyzlcu hide TextEdit` |
| `windows [--all]` | 屏幕上的窗口（所属应用、标题、位置） | `xyzlcu windows` |
| `movewin "App" x y [--w W --h H] [--title T]` | 移动 / 缩放窗口并置前 | `xyzlcu movewin "Safari" 200 100 --w 1200 --h 800` |
| `ax ["App"] [--depth N] [--menu]` | 导出界面控件树 | `xyzlcu ax TextEdit --depth 6` |
| `press "App" "标题"` | 按标题找到控件并按下 | `xyzlcu press TextEdit "取消"` |
| `wait 毫秒` | 等待 | `xyzlcu wait 500` |
| `taps` | 列出系统事件监听（排查输入卡顿/丢失） | `xyzlcu taps` |
| `run '命令; 命令; …'` | 一次启动执行多条命令（`;` 或换行分隔） | `xyzlcu run 'click 500 300; type 你好; key return'` |
| `batch [文件]` | 从文件或 stdin 逐行读命令执行 | `printf 'type a\nkey return\n' \| xyzlcu batch` |

补充：

- **应用名**可以写本地化名称（「访达」）、英文名（`Finder`）或 bundle ID（`com.apple.finder`）。
- **按键名**：`a–z`、`0–9`、常用符号、`return`/`enter`、`tab`、`space`、`delete`/`backspace`、`forwarddelete`、`esc`、`up`/`down`/`left`/`right`、`home`/`end`/`pageup`/`pagedown`、`f1–f12`。修饰键：`cmd`、`shift`、`opt`/`alt`、`ctrl`、`fn`。
- **`ax` 输出格式**：`角色(子角色) title="…" desc="…" value="…" id="…" [x,y 宽x高]`。中括号里的就是点坐标，中心点 = `(x + 宽/2, y + 高/2)`。
- **`press`** 优先执行 AXPress，按不了就点控件中心。
- **`run` / `batch`**：引号规则和 shell 一样（`"…"`、`'…'`、`\` 转义），`#` 开头的行是注释。遇到第一个出错的命令就停止，退出码同单条命令。
- **`--delay N`**：鼠标/键盘事件之间的间隔（毫秒，默认 2）。个别应用反应慢、丢字时调大，例如 `xyzlcu --delay 20 type …` 或 `XYZLCU_DELAY=20`。
- **截图**：macOS 14+ 走 ScreenCaptureKit（进程内截图，直接按 `--scale` 输出目标尺寸），否则或加 `--cli` 时退回系统 `screencapture`。输出里的 `method` 字段会告诉你走的哪条路。

## 完整示例：用文本编辑写一段中文并保存

```bash
# 0. 准备一个空文件，打开它（这样输入的文字肯定落在这个文件里）
: > ~/Documents/xyzlcu-demo.txt
open -a TextEdit ~/Documents/xyzlcu-demo.txt
xyzlcu wait 1500
xyzlcu activate TextEdit

# 1. 找到文本区域
xyzlcu ax TextEdit --depth 3 | grep AXTextArea
#   AXTextArea id="First Text View" [234,135 656x384]

# 2. 点进去（中心点 = 234+656/2, 135+384/2）
xyzlcu click 562 327

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
1. 开始前运行 `xyzlcu check`。如果 screenLocked 为 true 或权限缺失，停下来告诉用户。
2. 循环：观察 → 定位 → 操作 → 验证。
   - 观察：优先用 `xyzlcu ax "App" --depth 6` 读控件树；需要看画面时用 `xyzlcu screenshot /tmp/s.png --scale 0.5`。
   - 定位：用 ax 输出的 [x,y 宽x高] 算出中心点；用截图时按 pixelsPerPoint 和 originX/originY 换算成点坐标。
   - 操作：能 `xyzlcu press "App" "标题"` 就不用 click。
   - 验证：操作后重新 ax 或截图，确认结果。
3. 每次 `type` 或 `key` 之前先 `xyzlcu activate "目标App"`，再用 `xyzlcu apps` 确认它是前台（active: true）。键盘输入会发给当前前台应用。
4. 付款、删除、发送、提交这类不可撤销的操作，先征得用户同意。
5. 不要用 --force 绕过锁屏保护。
6. 已经确认过前台、要连续做几步时，可以合成一条 `xyzlcu run 'click 500 300; type 你好; key return'`，比分开调用快好几倍。
```

## 性能

v0.2.0 做了这些优化：去掉固定的 15–60 毫秒等待（改成 `--delay`，默认 2 毫秒）、复用同一个事件源、文字按 20 个 UTF-16 单元一段发送、截图改走 ScreenCaptureKit 并直接输出缩放后的尺寸、支持 JPEG、`-wmo` 编译，以及新增 `run`/`batch`，多步操作只启动一次进程。

在 Apple Silicon Mac（macOS 26+）上用 `scripts/bench.py` 测得的中位数：

| 命令 | v0.1.0 | v0.2.0 | 提升 |
|---|---:|---:|---:|
| `screenshot --scale 0.5`（PNG） | 750 ms | 251 ms | 3.0× |
| `screenshot --scale 0.5 --format jpg` | — | 197 ms | 3.8×（对比 v0.1.0 PNG） |
| `screenshot`（全尺寸 4112×2658 PNG） | 555 ms | 501 ms | 1.1× |
| `type`（128 个字符，中英混合） | 222 ms | 73 ms | 3.0× |
| `type`（5 个字符） | 84 ms | 58 ms | 1.4× |
| `key right` | 102 ms | 68 ms | 1.5× |
| `click` | 85 ms | 58 ms | 1.5× |
| `move` | 60 ms | 51 ms | 1.2× |
| 5 步操作（type/key 交替） | 约 310 ms（5 次调用） | 76 ms（一次 `batch`） | 4× |
| `check` / `apps` / `windows` / `cursor` / `ax` | 15–50 ms | 15–55 ms | 持平（主要是进程启动开销） |

自己测：`python3 scripts/bench.py build/xyzlcu`（加 `--gui` 会新建一个临时文本编辑文稿来测点击和输入，结束后自动关闭）。

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
- 不要让智能体在付款、删除、发送这类确认框上自动点「确定」。
- XYZLCU 不联网、不收集任何数据，也不修改系统权限数据库。

## 已知限制

- 只支持 macOS，只操作当前登录用户的图形会话。锁屏时没法操作，截图也是全黑。
- 截图用的是系统的 `/usr/sbin/screencapture`。
- `press` 只按完全匹配（不区分大小写）的标题、描述、值或 identifier 找控件，返回第一个匹配项。
- `type` 不经过输入法，需要输入法联想的场景不适用。
- 不支持其他桌面（Space）上的窗口的切换管理。

## 卸载

```bash
rm -f ~/.local/bin/xyzlcu ~/.local/bin/macctl
```

然后在「系统设置 > 隐私与安全性」的「辅助功能」和「屏幕与系统录音」里，把不再需要的 App 关掉或移除。

> 想继续用旧名字的话：`ln -sf ~/.local/bin/xyzlcu ~/.local/bin/macctl`

## 许可证

[MIT](LICENSE) © 2026 XYZTech
