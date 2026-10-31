// XYZLCU (XYZ Local Computer Use) — dependency-free macOS GUI control CLI
// 零依赖的 macOS 图形界面控制命令行工具
// MIT License, Copyright (c) 2026 XYZTech
import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import ImageIO
import ScreenCaptureKit

// MARK: - 工具函数
func out(_ obj: Any) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
       let s = String(data: d, encoding: .utf8) { print(s) } else { print(obj) }
}
func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(("error: " + msg + "\n").data(using: .utf8)!)
    exit(code)
}
func dbl(_ s: String) -> Double { guard let v = Double(s) else { fail("不是数字: \(s)") }; return v }

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }; return false
}
func option(_ name: String) -> String? {
    if let i = args.firstIndex(of: name), i + 1 < args.count { let v = args[i+1]; args.removeSubrange(i...i+1); return v }
    return nil
}
func need(_ n: Int, _ usage: String) { if args.count < n { fail("用法: xyzlcu \(usage)") } }
func sleepMs(_ ms: Int) { if ms > 0 { usleep(useconds_t(ms * 1000)) } }
/// 事件之间的间隔（毫秒），可用 --delay N 或环境变量 XYZLCU_DELAY 调整
var stepDelay: Int = Int(ProcessInfo.processInfo.environment["XYZLCU_DELAY"] ?? "") ?? 2
let eventSource = CGEventSource(stateID: .hidSystemState)

// MARK: - 权限
func axTrusted() -> Bool { AXIsProcessTrusted() }
func screenTrusted() -> Bool { CGPreflightScreenCaptureAccess() }
func screenLocked() -> Bool {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (d["CGSSessionScreenIsLocked"] as? Bool) ?? ((d["CGSSessionScreenIsLocked"] as? Int) == 1)
}
/// 锁屏时键鼠事件会落到登录窗口（密码框），默认拒绝执行
func guardUnlocked() {
    if screenLocked() && !flag("--force") { fail("屏幕已锁定，键鼠操作会进入锁屏密码框，已拒绝。解锁后再试（或加 --force）", code: 3) }
}

typealias RespFn = @convention(c) (pid_t) -> pid_t
func responsiblePid(_ pid: pid_t) -> pid_t? {
    guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "responsibility_get_pid_responsible_for_pid") else { return nil }
    let f = unsafeBitCast(sym, to: RespFn.self)
    let r = f(pid); return r > 0 ? r : nil
}
func pathOf(_ pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buf, UInt32(buf.count))
    return n > 0 ? String(cString: buf) : "?"
}

// MARK: - 鼠标
func mainDisplayHeight() -> CGFloat { CGDisplayBounds(CGMainDisplayID()).height }
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
func mouse(_ type: CGEventType, _ p: CGPoint, _ btn: CGMouseButton = .left, clicks: Int64 = 1) {
    let e = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: p, mouseButton: btn)
    e?.setIntegerValueField(.mouseEventClickState, value: clicks)
    post(e)
}
func click(_ p: CGPoint, right: Bool, double: Bool) {
    let (down, up, btn): (CGEventType, CGEventType, CGMouseButton) = right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
    mouse(.mouseMoved, p); sleepMs(stepDelay)
    mouse(down, p, btn, clicks: 1); mouse(up, p, btn, clicks: 1)
    if double { sleepMs(stepDelay); mouse(down, p, btn, clicks: 2); mouse(up, p, btn, clicks: 2) }
}

// MARK: - 键盘
let keyMap: [String: CGKeyCode] = [
    "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
    "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,
    "i":34,"p":35,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"`":50,
    "return":36,"enter":36,"tab":48,"space":49,"delete":51,"backspace":51,"esc":53,"escape":53,"forwarddelete":117,
    "home":115,"end":119,"pageup":116,"pagedown":121,"left":123,"right":124,"down":125,"up":126,
    "f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,"f9":101,"f10":109,"f11":103,"f12":111,
    "capslock":57,"kpenter":76,
]
let modMap: [String: CGEventFlags] = [
    "cmd":.maskCommand,"command":.maskCommand,"shift":.maskShift,"opt":.maskAlternate,"option":.maskAlternate,"alt":.maskAlternate,
    "ctrl":.maskControl,"control":.maskControl,"fn":.maskSecondaryFn,
]
func pressCombo(_ combo: String) {
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    var flags: CGEventFlags = []
    var key: CGKeyCode? = nil
    for p in parts {
        if let m = modMap[p] { flags.insert(m) }
        else if let k = keyMap[p] { key = k }
        else { fail("未知按键: \(p)") }
    }
    guard let k = key else { fail("组合键里没有主键: \(combo)") }
    let src = eventSource
    let d = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: true); d?.flags = flags; post(d)
    let u = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: false); u?.flags = flags; post(u)
}
func typeText(_ text: String) {
    let src = eventSource
    let units = Array(text.utf16)
    var i = 0
    while i < units.count {
        var end = min(i + 20, units.count)
        if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 } // 不拆开代理对
        var chunk = Array(units[i..<end])
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
            e?.flags = []
            e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            post(e)
        }
        i = end; if i < units.count { sleepMs(stepDelay) }
    }
}

// MARK: - 应用 / 窗口
func findApp(_ name: String) -> NSRunningApplication? {
    let l = name.lowercased()
    let apps = NSWorkspace.shared.runningApplications
    func fileName(_ a: NSRunningApplication) -> String { a.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() ?? "" }
    return apps.first { $0.localizedName?.lowercased() == l || $0.bundleIdentifier?.lowercased() == l || fileName($0) == l }
        ?? apps.first { ($0.localizedName?.lowercased().contains(l) ?? false) && $0.activationPolicy == .regular }
}
func appInfo(_ a: NSRunningApplication) -> [String: Any] {
    ["name": a.localizedName ?? "", "bundleId": a.bundleIdentifier ?? "", "pid": Int(a.processIdentifier), "active": a.isActive, "hidden": a.isHidden]
}

// MARK: - 辅助功能树
func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?; return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}
func str(_ el: AXUIElement, _ name: String) -> String? {
    guard let v = attr(el, name) else { return nil }
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}
func frame(_ el: AXUIElement) -> [String: Int]? {
    guard let pv = attr(el, kAXPositionAttribute), let sv = attr(el, kAXSizeAttribute) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return ["x": Int(p.x), "y": Int(p.y), "w": Int(s.width), "h": Int(s.height)]
}
func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func label(_ el: AXUIElement) -> String {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, "AXIdentifier", kAXHelpAttribute]
        .compactMap { str(el, $0) }.first ?? ""
}
func dump(_ el: AXUIElement, depth: Int, max: Int, indent: String = "", count: inout Int) {
    if count > 3000 { return }
    count += 1
    let role = str(el, kAXRoleAttribute) ?? "?"
    var line = indent + role
    if let sub = str(el, kAXSubroleAttribute) { line += "(\(sub))" }
    for (k, a) in [("title", kAXTitleAttribute), ("desc", kAXDescriptionAttribute), ("value", kAXValueAttribute), ("id", "AXIdentifier")] {
        if var s = str(el, a) { if s.count > 80 { s = String(s.prefix(80)) + "…" }; line += " \(k)=\"\(s.replacingOccurrences(of: "\n", with: " "))\"" }
    }
    if let f = frame(el) { line += " [\(f["x"]!),\(f["y"]!) \(f["w"]!)x\(f["h"]!)]" }
    print(line)
    if depth < max { for c in children(el) { dump(c, depth: depth + 1, max: max, indent: indent + "  ", count: &count) } }
}
func axRoot(_ appName: String?) -> (AXUIElement, NSRunningApplication) {
    guard axTrusted() else { fail("没有辅助功能权限，先运行 xyzlcu check / xyzlcu request", code: 2) }
    let app: NSRunningApplication
    if let n = appName { guard let a = findApp(n) else { fail("找不到应用: \(n)") }; app = a }
    else { guard let a = NSWorkspace.shared.frontmostApplication else { fail("没有前台应用") }; app = a }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 3)
    return (ax, app)
}
func findElement(_ el: AXUIElement, _ target: String, depth: Int = 0) -> AXUIElement? {
    if depth > 40 { return nil }
    let t = target.lowercased()
    for a in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, "AXIdentifier"] {
        if let s = str(el, a), s.lowercased() == t { return el }
    }
    for c in children(el) { if let r = findElement(c, target, depth: depth + 1) { return r } }
    return nil
}

// MARK: - 截图
func activeDisplays() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetActiveDisplayList(n, &ids, &n)
    // 主屏排第一，与 screencapture -D 1 一致
    let main = CGMainDisplayID()
    return ids.filter { $0 == main } + ids.filter { $0 != main }
}
func writeImage(_ img: CGImage, to url: URL, jpeg: Bool, quality: Double) -> Bool {
    let type = (jpeg ? "public.jpeg" : "public.png") as CFString
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { return false }
    let props: [CFString: Any] = jpeg ? [kCGImageDestinationLossyCompressionQuality: quality] : [:]
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    return CGImageDestinationFinalize(dest)
}
func scaled(_ img: CGImage, _ s: Double) -> CGImage {
    let w = max(1, Int(Double(img.width) * s)), h = max(1, Int(Double(img.height) * s))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return img }
    ctx.interpolationQuality = .medium
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? img
}
/// 快路径：ScreenCaptureKit（macOS 14+），在进程内截图，直接按目标尺寸输出
func captureSCK(_ did: CGDirectDisplayID, pixelWidth: Int, pixelHeight: Int) -> CGImage? {
    guard #available(macOS 14.0, *) else { return nil }
    let sem = DispatchSemaphore(value: 0)
    var result: CGImage?
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
        guard let content = content, let d = content.displays.first(where: { $0.displayID == did }) else { sem.signal(); return }
        let filter = SCContentFilter(display: d, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = pixelWidth; cfg.height = pixelHeight
        cfg.showsCursor = false
        cfg.captureResolution = .best
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { img, _ in
            result = img; sem.signal()
        }
    }
    return sem.wait(timeout: .now() + 5) == .timedOut ? nil : result
}
/// 慢路径：/usr/sbin/screencapture
func captureCLI(display: Int, tmp: String) -> CGImage? {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-D", String(display), "-t", "png", tmp]
    try? p.run(); p.waitUntilExit()
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: tmp) as CFURL, nil) else { return nil }
    // 立即解码，否则 defer 删掉临时文件后图像会是全黑
    return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
}
func screenshot(path: String, scale: Double?, display: Int, jpeg: Bool, quality: Double, forceCLI: Bool) {
    let displays = activeDisplays()
    guard display >= 1 && display <= displays.count else { fail("没有第 \(display) 块显示器（共 \(displays.count) 块，见 xyzlcu displays）") }
    let did = displays[display - 1]
    let b = CGDisplayBounds(did)
    let nativeW = CGDisplayCopyDisplayMode(did)?.pixelWidth ?? Int(b.width)
    let nativeH = CGDisplayCopyDisplayMode(did)?.pixelHeight ?? Int(b.height)
    let s = (scale ?? 1) > 0 ? (scale ?? 1) : 1
    let tw = max(1, Int(Double(nativeW) * s)), th = max(1, Int(Double(nativeH) * s))
    var method = "screencapturekit"
    var img: CGImage? = (forceCLI || !screenTrusted()) ? nil : captureSCK(did, pixelWidth: tw, pixelHeight: th)
    if img == nil {
        method = "screencapture"
        img = captureCLI(display: display, tmp: NSTemporaryDirectory() + "xyzlcu-raw-\(getpid()).png")
        if let i = img, i.width != tw { img = scaled(i, Double(tw) / Double(i.width)); method += "+scaled" }
    }
    guard let cg = img, writeImage(cg, to: URL(fileURLWithPath: path), jpeg: jpeg, quality: quality) else {
        fail("截图失败（多半是没有屏幕录制权限）", code: 2)
    }
    // 锁屏时截图全黑；没有屏幕录制权限时只能拍到桌面和菜单栏
    out(["path": path, "display": display, "pixelWidth": cg.width, "pixelHeight": cg.height,
         "originX": Int(b.origin.x), "originY": Int(b.origin.y), "pointWidth": Int(b.width), "pointHeight": Int(b.height),
         "pixelsPerPoint": Double(cg.width) / Double(b.width), "method": method, "screenLocked": screenLocked(),
         "note": "全局点坐标 x = originX + x_pixel / pixelsPerPoint，y = originY + y_pixel / pixelsPerPoint"])
}

// MARK: - 主命令
let usage = """
xyzlcu — XYZ Local Computer Use：macOS 图形界面控制
  check | request | whoami
  screenshot [path] [--scale 0.5] [--display N] [--format png|jpg] [--quality 0.7] [--cli]
  click x y [--right] [--double] | move x y | drag x1 y1 x2 y2 | scroll dx dy
  type "文字" | key cmd+shift+4
  apps | open "App" | activate "App" | hide "App" | windows [--all]
  displays | movewin "App" x y [--w W --h H] [--title 标题]
  ax ["App"] [--depth N] [--menu] | press "App" "按钮标题"
  cursor | wait 毫秒 | version | taps（诊断输入卡顿）
  batch [脚本文件]  （从 stdin 或文件逐行读取命令，一次启动执行多步）
  run 'click 10 20; type 你好; key return'
  通用选项: --delay N  事件间隔毫秒（默认 2，也可用环境变量 XYZLCU_DELAY）
"""
let version = "0.2.0"
var inBatch = false

func execute(_ argv: [String]) {
args = argv
if let d = option("--delay") { stepDelay = Int(dbl(d)) }
guard !args.isEmpty else { return }
let cmd = args.removeFirst()

switch cmd {
case "help", "-h", "--help": print(usage)
case "version", "--version", "-v": print("xyzlcu \(version)")
case "check":
    out(["accessibility": axTrusted(), "screenRecording": screenTrusted(), "screenLocked": screenLocked(), "binary": pathOf(getpid()),
         "responsibleProcess": responsiblePid(getpid()).map { pathOf($0) } ?? "unknown"])
case "request":
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let ax = AXIsProcessTrustedWithOptions(opts)
    let sr = CGRequestScreenCaptureAccess()
    out(["accessibility": ax, "screenRecording": sr, "note": "如弹出系统窗口，请到 系统设置 > 隐私与安全性 中打开对应开关"])
case "whoami":
    var chain: [[String: Any]] = []; var p = getpid()
    while p > 1 {
        var info = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.size; var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, p]
        sysctl(&mib, 4, &info, &size, nil, 0)
        chain.append(["pid": Int(p), "path": pathOf(p)]); p = info.kp_eproc.e_ppid
    }
    let r = responsiblePid(getpid())
    out(["chain": chain, "responsiblePid": r.map { Int($0) } ?? -1, "responsiblePath": r.map { pathOf($0) } ?? "unknown"])
case "screenshot":
    let scale = option("--scale").map(dbl)
    let display = Int(option("--display") ?? "1") ?? 1
    let fmt = (option("--format") ?? "png").lowercased()
    let quality = option("--quality").map(dbl) ?? 0.7
    let forceCLI = flag("--cli")
    let jpeg = fmt == "jpg" || fmt == "jpeg" || (args.first?.lowercased().hasSuffix(".jpg") ?? false) || (args.first?.lowercased().hasSuffix(".jpeg") ?? false)
    let path = args.first ?? (NSTemporaryDirectory() + "xyzlcu-\(Int(Date().timeIntervalSince1970)).\(jpeg ? "jpg" : "png")")
    screenshot(path: path, scale: scale, display: display, jpeg: jpeg, quality: quality, forceCLI: forceCLI)
case "click":
    guardUnlocked(); let right = flag("--right"), double = flag("--double")
    need(2, "click x y [--right] [--double]")
    click(CGPoint(x: dbl(args[0]), y: dbl(args[1])), right: right, double: double); print("ok")
case "move":
    guardUnlocked()
    need(2, "move x y")
    let p = CGPoint(x: dbl(args[0]), y: dbl(args[1]))
    CGWarpMouseCursorPosition(p); CGAssociateMouseAndMouseCursorPosition(1)
    mouse(.mouseMoved, p); print("ok")
case "drag":
    guardUnlocked()
    need(4, "drag x1 y1 x2 y2")
    let a = CGPoint(x: dbl(args[0]), y: dbl(args[1])), b = CGPoint(x: dbl(args[2]), y: dbl(args[3]))
    let dd = max(stepDelay, 8)  // 拖拽需要一点时间让应用识别
    mouse(.mouseMoved, a); sleepMs(dd); mouse(.leftMouseDown, a); sleepMs(dd)
    for i in 1...12 { let t = CGFloat(i) / 12; mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)); sleepMs(dd) }
    mouse(.leftMouseUp, b); print("ok")
case "scroll":
    guardUnlocked()
    need(2, "scroll dx dy  （正 dy 向上滚，单位：行）")
    post(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(dbl(args[1])), wheel2: Int32(dbl(args[0])), wheel3: 0)); print("ok")
case "type":
    guardUnlocked()
    need(1, "type \"文字\""); typeText(args.joined(separator: " ")); print("ok")
case "key":
    guardUnlocked()
    need(1, "key cmd+shift+4"); for (i, c) in args.enumerated() { if i > 0 { sleepMs(stepDelay) }; pressCombo(c) }; print("ok")
case "cursor":
    let p = CGEvent(source: nil)?.location ?? .zero; out(["x": Int(p.x), "y": Int(p.y)])
case "wait":
    need(1, "wait 毫秒"); sleepMs(Int(dbl(args[0]))); print("ok")
case "apps":
    out(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(appInfo))
case "open":
    need(1, "open \"App\"")
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", args[0]]
    try? p.run(); p.waitUntilExit()
    if p.terminationStatus != 0 { fail("打开失败: \(args[0])") }; print("ok")
case "activate":
    need(1, "activate \"App\"")
    guard let a = findApp(args[0]) else { fail("没在运行: \(args[0])，可先 xyzlcu open") }
    a.unhide(); a.activate(options: [.activateAllWindows]); print("ok")
case "hide":
    need(1, "hide \"App\"")
    guard let a = findApp(args[0]) else { fail("没在运行: \(args[0])") }
    a.hide(); print("ok")
case "displays":
    out(activeDisplays().enumerated().map { (i, d) -> [String: Any] in
        let b = CGDisplayBounds(d)
        return ["index": i + 1, "id": Int(d), "main": d == CGMainDisplayID(), "x": Int(b.origin.x), "y": Int(b.origin.y),
                "w": Int(b.width), "h": Int(b.height), "pixelWidth": CGDisplayCopyDisplayMode(d)?.pixelWidth ?? 0, "pixelHeight": CGDisplayCopyDisplayMode(d)?.pixelHeight ?? 0]
    })
case "movewin":
    let wOpt = option("--w").map(dbl), hOpt = option("--h").map(dbl), titleOpt = option("--title")
    need(3, "movewin \"App\" x y [--w W --h H] [--title 窗口标题]")
    let (root, app) = axRoot(args[0])
    var win: AXUIElement? = nil
    if let t = titleOpt {
        win = ((attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first { (str($0, kAXTitleAttribute) ?? "").localizedCaseInsensitiveContains(t) }
    } else {
        win = (attr(root, kAXFocusedWindowAttribute) as! AXUIElement?) ?? (attr(root, kAXMainWindowAttribute) as! AXUIElement?)
            ?? ((attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first
    }
    guard let w = win else { fail("找不到 \(app.localizedName ?? args[0]) 的窗口") }
    var pt = CGPoint(x: dbl(args[1]), y: dbl(args[2]))
    if let v = AXValueCreate(.cgPoint, &pt) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) }
    if wOpt != nil || hOpt != nil {
        let cur = frame(w) ?? ["w": 800, "h": 600]
        var sz = CGSize(width: wOpt ?? Double(cur["w"]!), height: hOpt ?? Double(cur["h"]!))
        if let v = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v) }
    }
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    app.activate(options: [])
    var res: [String: Any] = ["app": app.localizedName ?? "", "title": str(w, kAXTitleAttribute) ?? ""]
    if let f = frame(w) { res["frame"] = f }
    out(res)
case "windows":
    let all = flag("--all")
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    let rows: [[String: Any]] = list.compactMap { w in
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        if !all && layer != 0 { return nil }
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        return ["owner": w[kCGWindowOwnerName as String] as? String ?? "", "pid": w[kCGWindowOwnerPID as String] as? Int ?? 0,
                "title": w[kCGWindowName as String] as? String ?? "", "id": w[kCGWindowNumber as String] as? Int ?? 0, "layer": layer,
                "x": b["X"] ?? 0, "y": b["Y"] ?? 0, "w": b["Width"] ?? 0, "h": b["Height"] ?? 0]
    }
    out(rows)
case "ax":
    let depth = Int(option("--depth") ?? "12") ?? 12
    let withMenu = flag("--menu")
    let (root, app) = axRoot(args.first)
    print("# \(app.localizedName ?? "?") pid=\(app.processIdentifier)")
    let win = (attr(root, kAXFocusedWindowAttribute) as! AXUIElement?) ?? (attr(root, kAXMainWindowAttribute) as! AXUIElement?)
    var n = 0
    if let w = win { dump(w, depth: 0, max: depth, count: &n) } else { dump(root, depth: 0, max: depth, count: &n) }
    if let mb = attr(root, kAXMenuBarAttribute), withMenu { dump(mb as! AXUIElement, depth: 0, max: 3, count: &n) }
case "press":
    need(2, "press \"App\" \"按钮标题\"")
    let (root, _) = axRoot(args[0])
    guard let el = findElement(root, args[1]) else { fail("找不到元素: \(args[1])") }
    let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
    if r != .success {
        if let f = frame(el) { click(CGPoint(x: f["x"]! + f["w"]! / 2, y: f["y"]! + f["h"]! / 2), right: false, double: false); print("ok (AXPress 失败，已改为点击中心)") }
        else { fail("AXPress 失败: \(r.rawValue)") }
    } else { print("ok") }
case "taps":
    // 诊断：列出系统里的事件监听（event tap）。主动拦截型（listenOnly=false）且延迟很高的 tap 会让键盘/鼠标输入卡住或丢失
    var n: UInt32 = 0; CGGetEventTapList(0, nil, &n)
    var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(n)); CGGetEventTapList(n, &list, &n)
    out(list.prefix(Int(n)).map { t -> [String: Any] in
        var buf = [CChar](repeating: 0, count: 4096); proc_pidpath(t.tappingProcess, &buf, 4096)
        return ["process": String(cString: buf), "pid": Int(t.tappingProcess), "enabled": t.enabled,
                "listenOnly": t.options == .listenOnly, "eventsMask": String(t.eventsOfInterest, radix: 16),
                "avgLatencyMs": Double(t.avgUsecLatency) / 1000, "maxLatencyMs": Double(t.maxUsecLatency) / 1000]
    })
case "batch", "run":
    fail("batch/run 不能嵌套")
default:
    fail("未知命令: \(cmd)（xyzlcu help 查看用法）")
}
fflush(stdout)
}

/// 把脚本拆成命令：换行或不在引号内的 ; 分隔，支持 "…" '…' 和 \ 转义，# 开头为注释
func parseScript(_ text: String) -> [[String]] {
    var cmds: [[String]] = [], cur: [String] = [], tok = "", hasTok = false
    var quote: Character? = nil, escape = false, comment = false
    func endTok() { if hasTok { cur.append(tok) }; tok = ""; hasTok = false }
    func endCmd() { endTok(); if !cur.isEmpty { cmds.append(cur) }; cur = [] }
    for ch in text {
        if comment { if ch == "\n" { comment = false; endCmd() }; continue }
        if escape { tok.append(ch == "n" ? "\n" : ch); hasTok = true; escape = false; continue }
        if let q = quote {
            if ch == q { quote = nil } else if ch == "\\" && q == "\"" { escape = true } else { tok.append(ch) }
            continue
        }
        switch ch {
        case "\\": escape = true
        case "\"", "'": quote = ch; hasTok = true
        case " ", "\t": endTok()
        case "\n", ";": endCmd()
        case "#" where !hasTok && cur.isEmpty: comment = true
        default: tok.append(ch); hasTok = true
        }
    }
    endCmd()
    return cmds
}

let top = Array(CommandLine.arguments.dropFirst())
if top.isEmpty { print(usage); exit(0) }
if top[0] == "batch" || top[0] == "run" {
    inBatch = true
    var rest = Array(top.dropFirst())
    if let i = rest.firstIndex(of: "--delay"), i + 1 < rest.count { stepDelay = Int(dbl(rest[i + 1])); rest.removeSubrange(i...i+1) }
    let text: String
    if top[0] == "run" { text = rest.joined(separator: " ") }
    else if let f = rest.first { guard let t = try? String(contentsOfFile: f, encoding: .utf8) else { fail("读不到脚本: \(f)") }; text = t }
    else { text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? "" }
    for c in parseScript(text) { execute(c) }
} else {
    execute(top)
}
