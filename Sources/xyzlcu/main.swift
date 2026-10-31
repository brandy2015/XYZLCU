// XYZLCU (XYZ Local Computer Use) — dependency-free macOS GUI control CLI
// 零依赖的 macOS 图形界面控制命令行工具
// MIT License, Copyright (c) 2026 XYZTech
import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

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
func sleepMs(_ ms: Int) { usleep(useconds_t(ms * 1000)) }

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
    let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: p, mouseButton: btn)
    e?.setIntegerValueField(.mouseEventClickState, value: clicks)
    post(e)
}
func click(_ p: CGPoint, right: Bool, double: Bool) {
    let (down, up, btn): (CGEventType, CGEventType, CGMouseButton) = right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
    mouse(.mouseMoved, p); sleepMs(30)
    mouse(down, p, btn, clicks: 1); mouse(up, p, btn, clicks: 1)
    if double { sleepMs(60); mouse(down, p, btn, clicks: 2); mouse(up, p, btn, clicks: 2) }
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
    let src = CGEventSource(stateID: .hidSystemState)
    let d = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: true); d?.flags = flags; post(d)
    let u = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: false); u?.flags = flags; post(u)
}
func typeText(_ text: String) {
    let src = CGEventSource(stateID: .hidSystemState)
    let units = Array(text.utf16)
    var i = 0
    while i < units.count {
        var end = min(i + 16, units.count)
        if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 } // 不拆开代理对
        var chunk = Array(units[i..<end])
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
            e?.flags = []
            e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            post(e)
        }
        sleepMs(15); i = end
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
func screenshot(path: String, scale: Double?, display: Int) {
    let displays = activeDisplays()
    guard display >= 1 && display <= displays.count else { fail("没有第 \(display) 块显示器（共 \(displays.count) 块，见 xyzlcu displays）") }
    let b = CGDisplayBounds(displays[display - 1])
    let url = URL(fileURLWithPath: path)
    var method = "screencapture"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-D", String(display), "-t", "png", path]
    try? p.run(); p.waitUntilExit()
    guard FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOf: url),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("截图失败（多半是没有屏幕录制权限）", code: 2)
    }
    var w = cg.width, h = cg.height
    if let s = scale, s > 0, s != 1 {
        w = Int(Double(cg.width) * s); h = Int(Double(cg.height) * s)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        method += "+scaled"
    }
    // 锁屏时截图全黑；没有屏幕录制权限时只能拍到桌面和菜单栏
    out(["path": path, "display": display, "pixelWidth": w, "pixelHeight": h,
         "originX": Int(b.origin.x), "originY": Int(b.origin.y), "pointWidth": Int(b.width), "pointHeight": Int(b.height),
         "pixelsPerPoint": Double(w) / Double(b.width), "method": method, "screenRecordingGranted": screenTrusted(), "screenLocked": screenLocked(),
         "note": "全局点坐标 x = originX + x_pixel / pixelsPerPoint，y = originY + y_pixel / pixelsPerPoint"])
}

// MARK: - 主命令
let usage = """
xyzlcu — XYZ Local Computer Use：macOS 图形界面控制
  check | request | whoami
  screenshot [path] [--scale 0.5] [--display N]
  click x y [--right] [--double] | move x y | drag x1 y1 x2 y2 | scroll dx dy
  type "文字" | key cmd+shift+4
  apps | open "App" | activate "App" | hide "App" | windows [--all]
  displays | movewin "App" x y [--w W --h H] [--title 标题]
  ax ["App"] [--depth N] [--menu] | press "App" "按钮标题"
  cursor | wait 毫秒
"""
let version = "0.1.0"
guard !args.isEmpty else { print(usage); exit(0) }
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
    let path = args.first ?? (NSTemporaryDirectory() + "xyzlcu-\(Int(Date().timeIntervalSince1970)).png")
    screenshot(path: path, scale: scale, display: display)
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
    mouse(.mouseMoved, a); sleepMs(50); mouse(.leftMouseDown, a); sleepMs(50)
    for i in 1...20 { let t = CGFloat(i) / 20; mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)); sleepMs(15) }
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
    need(1, "key cmd+shift+4"); for c in args { pressCombo(c); sleepMs(30) }; print("ok")
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
                "w": Int(b.width), "h": Int(b.height), "pixelWidth": CGDisplayPixelsWide(d), "pixelHeight": CGDisplayPixelsHigh(d)]
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
default:
    print(usage); exit(1)
}
