// XYZLCU (XYZ Local Computer Use) — dependency-free macOS GUI control CLI
// 零依赖的 macOS 图形界面控制命令行工具
// MIT License, Copyright (c) 2026 XYZTech
import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import CoreMedia
import VideoToolbox
import Carbon.HIToolbox
import zlib
import Accelerate

// MARK: - 工具函数
/// 守护进程模式下输出写进缓冲区再回传给客户端；普通模式直接打印
var outBuf: String? = nil
func emit(_ s: String) { if outBuf != nil { outBuf! += s; outBuf! += "\n" } else { print(s) } }
func out(_ obj: Any) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
       let s = String(data: d, encoding: .utf8) { emit(s) } else { emit("\(obj)") }
}
struct XErr: Error { let msg: String; let code: Int32 }
/// 出错时抛出，由最外层决定退出码（守护进程里不能直接 exit）
func fail(_ msg: String, code: Int32 = 1) throws -> Never { throw XErr(msg: msg, code: code) }
func dbl(_ s: String) throws -> Double { guard let v = Double(s) else { try fail("不是数字: \(s)") }; return v }

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }; return false
}
func option(_ name: String) -> String? {
    if let i = args.firstIndex(of: name), i + 1 < args.count { let v = args[i+1]; args.removeSubrange(i...i+1); return v }
    return nil
}
func need(_ n: Int, _ usage: String) throws { if args.count < n { try fail("用法: xyzlcu \(usage)") } }
func sleepMs(_ ms: Int) { if ms > 0 { usleep(useconds_t(ms * 1000)) } }
/// 事件之间的间隔（毫秒），可用 --delay N 或环境变量 XYZLCU_DELAY 调整
var stepDelay: Int = Int(ProcessInfo.processInfo.environment["XYZLCU_DELAY"] ?? "") ?? 2
let eventSource = CGEventSource(stateID: .hidSystemState)

// MARK: - 权限
func axTrusted() -> Bool { AXIsProcessTrusted() }
/// CGPreflightScreenCaptureAccess 一次要 10 毫秒左右；守护进程里把「已授权」缓存 30 秒（没授权不缓存，授权后立刻生效）
var screenTrustedAt = Date.distantPast
func screenTrusted() -> Bool {
    if daemonMode, Date().timeIntervalSince(screenTrustedAt) < 30 { return true }
    let ok = CGPreflightScreenCaptureAccess()
    if ok && daemonMode { screenTrustedAt = Date() }
    return ok
}
func screenLocked() -> Bool {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (d["CGSSessionScreenIsLocked"] as? Bool) ?? ((d["CGSSessionScreenIsLocked"] as? Int) == 1)
}
/// 锁屏时键鼠事件会落到登录窗口（密码框），默认拒绝执行；没有辅助功能权限时事件会被系统静默丢弃，直接报错
func guardUnlocked() throws {
    if !axTrusted() { try fail("没有辅助功能权限，键鼠事件会被系统丢弃。先运行 xyzlcu check / xyzlcu request", code: 2) }
    if screenLocked() && !flag("--force") { try fail("屏幕已锁定，键鼠操作会进入锁屏密码框，已拒绝。解锁后再试（或加 --force）", code: 3) }
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
/// 键盘事件的目标：nil = 系统 HID 事件流（发给前台应用）；设了 pid 就直接投递给该进程（--app）
var keyTargetPid: pid_t? = nil
func post(_ e: CGEvent?) { lastInputAt = Date(); e?.post(tap: .cghidEventTap) }
func postKey(_ e: CGEvent?) { lastInputAt = Date(); if let p = keyTargetPid { e?.postToPid(p) } else { e?.post(tap: .cghidEventTap) } }
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
/// 解析 cmd+shift+s 这样的组合键，返回（键码、修饰键、主键名）
func parseCombo(_ combo: String) throws -> (CGKeyCode, CGEventFlags, String) {
    // 单独的 "+" 键写成 cmd++ 时最后一段为空，这里不支持，用 shift+= 代替
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    var flags: CGEventFlags = []
    var key: CGKeyCode? = nil, name = ""
    for p in parts {
        if let m = modMap[p] { flags.insert(m) }
        else if let k = keyMap[p] { key = k; name = p }
        else { try fail("未知按键: \(p)") }
    }
    guard let k = key else { try fail("组合键里没有主键: \(combo)") }
    return (k, flags, name)
}
func postCombo(_ k: CGKeyCode, _ flags: CGEventFlags) {
    let d = CGEvent(keyboardEventSource: eventSource, virtualKey: k, keyDown: true); d?.flags = flags; postKey(d)
    let u = CGEvent(keyboardEventSource: eventSource, virtualKey: k, keyDown: false); u?.flags = flags; postKey(u)
}
func pressCombo(_ combo: String) throws { let (k, f, _) = try parseCombo(combo); postCombo(k, f) }
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
            postKey(e)
        }
        i = end; if i < units.count { sleepMs(stepDelay) }
    }
}

// MARK: - 应用 / 窗口
func findAppOnce(_ name: String) -> NSRunningApplication? {
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
    emit(line)
    if depth < max { for c in children(el) { dump(c, depth: depth + 1, max: max, indent: indent + "  ", count: &count) } }
}
func axRoot(_ appName: String?) throws -> (AXUIElement, NSRunningApplication) {
    guard axTrusted() else { try fail("没有辅助功能权限，先运行 xyzlcu check / xyzlcu request", code: 2) }
    let app: NSRunningApplication
    if let n = appName { guard let a = findApp(n) else { try fail("找不到应用: \(n)") }; app = a }
    else { guard let a = NSWorkspace.shared.frontmostApplication else { try fail("没有前台应用") }; app = a }
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

/// 守护进程里应用列表靠主 runloop 更新；找不到时让 runloop 转一下再找一次
var daemonMode = false
func pumpRunLoop() { if daemonMode { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02)) } }
/// 只处理已经排队的 runloop 事件，不等待（apps 用；原来固定等 20 毫秒）
func drainRunLoop() {
    guard daemonMode else { return }
    var n = 0
    while n < 64, CFRunLoopRunInMode(.defaultMode, 0, true) == .handledSource { n += 1 }
}
func findApp(_ name: String) -> NSRunningApplication? {
    if let a = findAppOnce(name) { return a }
    if daemonMode { pumpRunLoop(); return findAppOnce(name) }
    return nil
}

// MARK: - 快速查找元素（一次 IPC 取多个属性，广度优先，找到即停）
struct Query {
    var role: String?, subrole: String?, title: String?, contains = false, index = 1, all = false, limit = 50
    var windowTitle: String?, menu = false, maxNodes = 20000
}
func parseQuery() throws -> Query {
    var q = Query()
    q.role = option("--role"); q.subrole = option("--subrole"); q.title = option("--title")
    q.windowTitle = option("--window"); q.contains = flag("--contains"); q.all = flag("--all"); q.menu = flag("--menu")
    if let i = option("--index") { q.index = max(1, Int(try dbl(i))) }
    if let l = option("--limit") { q.limit = max(1, Int(try dbl(l))) }
    if let m = option("--max-nodes") { q.maxNodes = max(1, Int(try dbl(m))) }
    // 位置参数：App [标题]
    if q.title == nil && args.count >= 2 { q.title = args[1] }
    if q.role == nil && q.title == nil && q.subrole == nil { try fail("至少给出 --role、--subrole 或 --title 之一") }
    return q
}
let findAttrs = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, "AXIdentifier", kAXValueAttribute, kAXChildrenAttribute] as CFArray
func clean(_ v: AnyObject?) -> AnyObject? {
    guard let v = v else { return nil }
    if CFGetTypeID(v) == AXValueGetTypeID() { return nil }  // AXValue 在这里只可能是错误占位
    return v
}
func axs(_ v: AnyObject?) -> String? {
    if let x = v as? String { return x.isEmpty ? nil : x }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}
func axFind(_ appName: String?, _ q: Query) throws -> (matches: [[String: Any]], els: [AXUIElement], visited: Int, app: NSRunningApplication) {
    let (root, app) = try axRoot(appName)
    var queue: [AXUIElement] = []
    // 先搜焦点窗口，再搜其它窗口；菜单栏很大，只有 --menu 时才搜
    var wins = (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    if let fw = attr(root, kAXFocusedWindowAttribute), CFGetTypeID(fw) == AXUIElementGetTypeID() {
        let f = fw as! AXUIElement
        wins.removeAll { CFEqual($0, f) }; wins.insert(f, at: 0)
    }
    if let wt = q.windowTitle { wins = wins.filter { (str($0, kAXTitleAttribute) ?? "").localizedCaseInsensitiveContains(wt) } }
    queue.append(contentsOf: wins)
    if q.menu, let mb = attr(root, kAXMenuBarAttribute) { queue.append(mb as! AXUIElement) }
    if wins.isEmpty && !q.menu && q.windowTitle == nil { queue.append(root) }
    let tl = q.title?.lowercased(), rl = q.role?.lowercased(), sl = q.subrole?.lowercased()
    var head = 0, visited = 0, seen = 0
    var matches: [[String: Any]] = [], els: [AXUIElement] = []
    while head < queue.count && visited < q.maxNodes {
        let el = queue[head]; head += 1; visited += 1
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, findAttrs, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let vals = raw as? [AnyObject], vals.count == 7 else { continue }
        let role = axs(clean(vals[0])), sub = axs(clean(vals[1]))
        let texts = [vals[2], vals[3], vals[4], vals[5]].map { axs(clean($0)) }
        var ok = true
        if let r = rl, role?.lowercased() != r { ok = false }
        if ok, let r = sl, sub?.lowercased() != r { ok = false }
        if ok, let t = tl {
            ok = texts.contains { x in guard let x = x?.lowercased() else { return false }; return q.contains ? x.contains(t) : x == t }
        }
        if ok {
            seen += 1
            if q.all || seen == q.index {
                var m: [String: Any] = ["role": role ?? "", "title": (texts.prefix(3).compactMap { $0 }.first ?? texts[3].map { String($0.prefix(80)) } ?? "")]
                if let sub = sub { m["subrole"] = sub }
                if let f = frame(el) {
                    m["frame"] = f; m["center"] = ["x": f["x"]! + f["w"]! / 2, "y": f["y"]! + f["h"]! / 2]
                }
                matches.append(m); els.append(el)
                if !q.all || matches.count >= q.limit { break }
            }
        }
        if let kids = clean(vals[6]) as? [AXUIElement] { queue.append(contentsOf: kids) }
    }
    return (matches, els, visited, app)
}
func findOutput(_ r: (matches: [[String: Any]], els: [AXUIElement], visited: Int, app: NSRunningApplication), all: Bool, t0: Date, extra: [String: Any] = [:]) {
    var o: [String: Any] = ["app": r.app.localizedName ?? "", "pid": Int(r.app.processIdentifier), "visited": r.visited, "ms": Int(Date().timeIntervalSince(t0) * 1000)]
    if all { o["matches"] = r.matches } else { o.merge(r.matches[0]) { a, _ in a } }
    o.merge(extra) { a, _ in a }
    out(o)
}

// MARK: - 不经过键盘事件流的输入：辅助功能写值 / 剪贴板 + 菜单「粘贴」/ 菜单项
// 用途：系统里有卡住的键盘事件监听（event tap）时，合成的键盘事件送不到应用，这些路径完全不走事件流
func axElement(_ v: AnyObject?) -> AXUIElement? {
    guard let v = v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}
func axSettable(_ el: AXUIElement, _ a: String) -> Bool {
    var b: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(el, a as CFString, &b) == .success && b.boolValue
}
func axStringValue(_ el: AXUIElement) -> String? { attr(el, kAXValueAttribute) as? String }
func windowTitle(of el: AXUIElement) -> String? {
    if let w = axElement(attr(el, kAXWindowAttribute)) { return str(w, kAXTitleAttribute) }
    return nil
}
// MARK: - 输入路径健康检查（多条路自动选择）
/// 环境变量。守护进程模式下用客户端随请求转发过来的值（守护进程自己的环境可能是旧的）
var envOverlay: [String: String] = [:]
func envv(_ k: String) -> String? { daemonMode ? envOverlay[k] : ProcessInfo.processInfo.environment[k] }
// 改这个列表时同时改 Sources/client/xyzlcu.c 里的 FORWARDED_ENV
let forwardedEnv = ["XYZLCU_EVENTS_HEALTH", "XYZLCU_TAP_THRESHOLD_MS", "XYZLCU_TYPE_VIA", "XYZLCU_KEY_VIA", "XYZLCU_PROBE", "XYZLCU_PNG", "XYZLCU_PNG_LEVEL"]

struct TapInfo { let pid: pid_t; let process: String; let enabled: Bool; let listenOnly: Bool; let mask: UInt64; let avgMs: Double; let maxMs: Double }
func eventTaps() -> [TapInfo] {
    var n: UInt32 = 0; CGGetEventTapList(0, nil, &n)
    guard n > 0 else { return [] }
    var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(n)); CGGetEventTapList(n, &list, &n)
    return list.prefix(Int(n)).map { t in
        TapInfo(pid: t.tappingProcess, process: pathOf(t.tappingProcess), enabled: t.enabled, listenOnly: t.options == .listenOnly,
                mask: t.eventsOfInterest, avgMs: Double(t.avgUsecLatency) / 1000, maxMs: Double(t.maxUsecLatency) / 1000)
    }
}
func evBit(_ t: CGEventType) -> UInt64 { 1 << UInt64(t.rawValue) }
let keyboardEventsMask = evBit(.keyDown) | evBit(.keyUp) | evBit(.flagsChanged)
let mouseEventsMask = evBit(.leftMouseDown) | evBit(.leftMouseUp) | evBit(.rightMouseDown) | evBit(.rightMouseUp) |
    evBit(.mouseMoved) | evBit(.leftMouseDragged) | evBit(.scrollWheel)
func tapThresholdMs() -> Double { Double(envv("XYZLCU_TAP_THRESHOLD_MS") ?? "") ?? 1000 }
/// 会挡住输入的监听：已启用、主动拦截（不是只监听）、平均延迟超过阈值（默认 1000 毫秒）
func isBlockingTap(_ t: TapInfo) -> Bool { t.enabled && !t.listenOnly && t.avgMs > tapThresholdMs() }
struct InputHealth {
    var keyboardOK = true, mouseOK = true
    var keyboardBlockedBy: [[String: Any]] = [], mouseBlockedBy: [[String: Any]] = []
    var override: String? = nil
    /// 主动探测耗时（毫秒）；nil = 没探测，-1 = 建不了监听（没有输入监控权限），infinity = 超时
    var keyboardProbeMs: Double? = nil, mouseProbeMs: Double? = nil
    /// 系统统计显示延迟很高、但实测事件能正常走完的监听（统计是历史值，可能早已恢复）
    var staleBlockers: [[String: Any]] = []
    var at = Date()
    var blockerNames: [String] { keyboardBlockedBy.compactMap { ($0["process"] as? String)?.split(separator: "/").last.map(String.init) } }
}
var cachedHealth: InputHealth? = nil
var forceProbe = false
let probeMagic: Int64 = 0x58595A4C
var probeHit: Double? = nil
/// 主动探测事件流：发一个没有副作用的带标记事件（键盘：右 Shift 松开的 flagsChanged；鼠标：原地 mouseMoved），
/// 用排在最后的只监听监听计时，看它多久走完整条事件流。返回毫秒；超时 = infinity；建不了监听 = -1
func probeStream(keyboard: Bool, timeoutMs: Int) -> Double {
    let type: CGEventType = keyboard ? .flagsChanged : .mouseMoved
    let cb: CGEventTapCallBack = { _, _, ev, _ in
        if probeHit == nil && ev.getIntegerValueField(.eventSourceUserData) == probeMagic {
            probeHit = CFAbsoluteTimeGetCurrent(); CFRunLoopStop(CFRunLoopGetCurrent())
        }
        return Unmanaged.passUnretained(ev)
    }
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                      eventsOfInterest: evBit(type), callback: cb, userInfo: nil) else { return -1 }
    let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    defer { CGEvent.tapEnable(tap: tap, enable: false); CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes); CFMachPortInvalidate(tap) }
    probeHit = nil
    let e: CGEvent?
    if keyboard { e = CGEvent(keyboardEventSource: nil, virtualKey: 0x3C, keyDown: false); e?.type = .flagsChanged; e?.flags = [] }
    else { e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero, mouseButton: .left) }
    e?.setIntegerValueField(.eventSourceUserData, value: probeMagic)
    let t0 = CFAbsoluteTimeGetCurrent(), deadline = t0 + Double(timeoutMs) / 1000
    e?.post(tap: .cghidEventTap)
    while probeHit == nil && CFAbsoluteTimeGetCurrent() < deadline {
        _ = CFRunLoopRunInMode(.defaultMode, deadline - CFAbsoluteTimeGetCurrent(), true)
    }
    return probeHit.map { ($0 - t0) * 1000 } ?? .infinity
}
/// 读取系统事件监听列表判断键盘 / 鼠标事件流是否健康。守护进程里缓存 1.5 秒
/// XYZLCU_EVENTS_HEALTH=bad 可模拟「事件流卡住」（测试备用路径），=good 忽略检测
func inputHealth() -> InputHealth {
    let ov = envv("XYZLCU_EVENTS_HEALTH")?.lowercased()
    if ov == nil, !forceProbe, daemonMode, let h = cachedHealth, Date().timeIntervalSince(h.at) < 1.5 { return h }
    let blocking = eventTaps().filter(isBlockingTap)
    func desc(_ t: TapInfo) -> [String: Any] { ["process": t.process, "pid": Int(t.pid), "avgLatencyMs": t.avgMs] }
    var h = InputHealth()
    h.keyboardBlockedBy = blocking.filter { $0.mask & keyboardEventsMask != 0 }.map(desc)
    h.mouseBlockedBy = blocking.filter { $0.mask & mouseEventsMask != 0 }.map(desc)
    h.keyboardOK = h.keyboardBlockedBy.isEmpty; h.mouseOK = h.mouseBlockedBy.isEmpty
    // 系统统计里的延迟是历史值（刚卡住的监听统计还是低的，早已恢复的统计却可能还很高），所以键盘每次都实测：
    // 发一个带标记的「右 Shift 松开」事件，400 毫秒内走完整条事件流就算健康（正常 1–30 毫秒）。XYZLCU_PROBE=0 关闭
    // 鼠标只在统计说卡住时（或 check --probe）才实测
    if ov == nil && envv("XYZLCU_PROBE") != "0" {
        do {
            let ms = probeStream(keyboard: true, timeoutMs: 400); h.keyboardProbeMs = ms
            if ms >= 0 && ms.isFinite { h.staleBlockers += h.keyboardBlockedBy; h.keyboardBlockedBy = []; h.keyboardOK = true }
            else if ms.isInfinite && h.keyboardOK { h.keyboardOK = false; h.keyboardBlockedBy = [["process": "unknown", "pid": 0, "avgLatencyMs": -1, "note": "探测事件 400 毫秒内没走完"]] }
        }
        if !h.mouseOK || forceProbe {
            let ms = probeStream(keyboard: false, timeoutMs: 400); h.mouseProbeMs = ms
            if ms >= 0 && ms.isFinite { h.mouseBlockedBy = []; h.mouseOK = true }
            else if ms.isInfinite && h.mouseOK { h.mouseOK = false }
        }
    }
    if ov == "bad" { h.keyboardOK = false; h.mouseOK = false } else if ov == "good" { h.keyboardOK = true; h.mouseOK = true }
    h.override = ov
    if ov == nil { cachedHealth = h }
    return h
}

/// 解析输入目标：给了 --role/--subrole/--title/--id 就按条件找，否则用应用当前的焦点元素。--window 限定所在窗口标题
func inputTarget(_ appName: String?, role: String?, subrole: String?, title: String?, window: String?, index: Int) throws -> (AXUIElement, NSRunningApplication) {
    if role != nil || subrole != nil || title != nil {
        var q = Query(); q.role = role; q.subrole = subrole; q.title = title; q.windowTitle = window; q.index = index
        let r = try axFind(appName, q)
        guard let el = r.els.first else { try fail("找不到要输入的元素（搜索了 \(r.visited) 个节点）", code: 4) }
        return (el, r.app)
    }
    let (root, app) = try axRoot(appName)
    guard let el = axElement(attr(root, kAXFocusedUIElementAttribute)) else {
        try fail("\(app.localizedName ?? "应用") 没有焦点元素。先 click-el 点进输入框，或用 --role/--title 指定", code: 4)
    }
    if let w = window {
        let wt = windowTitle(of: el) ?? ""
        guard wt.localizedCaseInsensitiveContains(w) else { try fail("焦点元素在窗口「\(wt)」里，不是「\(w)」，已拒绝输入", code: 4) }
    }
    return (el, app)
}

/// 剪贴板快照：保存所有条目的所有类型，事后原样恢复
func snapshotPasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        var d: [NSPasteboard.PasteboardType: Data] = [:]
        for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
        return d
    }
}
func restorePasteboard(_ snap: [[NSPasteboard.PasteboardType: Data]]) {
    let pb = NSPasteboard.general
    pb.clearContents()
    let items = snap.map { d -> NSPasteboardItem in
        let it = NSPasteboardItem(); for (t, v) in d { it.setData(v, forType: t) }; return it
    }
    if !items.isEmpty { pb.writeObjects(items) }
}

/// 菜单路径匹配：每一级可写「编辑|Edit」多个候选；比较时忽略大小写和结尾的 … / ...
func menuNorm(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespaces).lowercased()
    for suf in ["…", "..."] where t.hasSuffix(suf) { t = String(t.dropLast(suf.count)) }
    return t.trimmingCharacters(in: .whitespaces)
}
var lastMenuWasDisabled = false
func pressMenu(_ appName: String?, _ path: [[String]]) throws -> [String] {
    let (root, _) = try axRoot(appName)
    guard let bar = axElement(attr(root, kAXMenuBarAttribute)) else { try fail("这个应用没有菜单栏") }
    var level: [AXUIElement] = children(bar)
    var picked: [String] = []
    for (i, cands) in path.enumerated() {
        let want = Set(cands.map(menuNorm))
        guard let hit = level.first(where: { el in
            guard let t = str(el, kAXTitleAttribute) else { return false }
            return want.contains(menuNorm(t))
        }) else {
            let have = level.compactMap { str($0, kAXTitleAttribute) }.filter { !$0.isEmpty }
            try fail("菜单里找不到「\(cands.joined(separator: "|"))」。这一级有：\(have.joined(separator: "、"))", code: 4)
        }
        picked.append(str(hit, kAXTitleAttribute) ?? "")
        if i == path.count - 1 {
            // AXEnabled 可能是上次打开菜单时的旧状态（应用不在前台时尤其如此），所以只记录、仍然尝试按下
            if let en = attr(hit, kAXEnabledAttribute) as? Bool, !en { lastMenuWasDisabled = true } else { lastMenuWasDisabled = false }
            let r = AXUIElementPerformAction(hit, kAXPressAction as CFString)
            guard r == .success else { try fail("按下菜单项失败: AXError \(r.rawValue)") }
        } else {
            // 菜单栏项 / 子菜单项的唯一子元素是 AXMenu，里面才是菜单项
            level = children(hit).flatMap { c -> [AXUIElement] in str(c, kAXRoleAttribute) == kAXMenuRole ? children(c) : [c] }
        }
    }
    return picked
}
func parseMenuPath(_ s: String) -> [[String]] {
    s.components(separatedBy: ">").map { $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        .filter { !$0.isEmpty }
}
let menuPaste: [[String]] = [["编辑", "Edit"], ["粘贴", "Paste"]]
let menuSelectAll: [[String]] = [["编辑", "Edit"], ["全选", "Select All"]]

/// 用辅助功能直接写文字。replaceAll=false 写 AXSelectedText（在光标处插入 / 替换选中），true 写 AXValue（整体替换）
/// 写完读回 AXValue 核对；返回 nil 表示这条路走不通
func axWrite(_ el: AXUIElement, _ text: String, replaceAll: Bool) -> [String: Any]? {
    let a = replaceAll ? kAXValueAttribute : kAXSelectedTextAttribute
    guard axSettable(el, a) else { return nil }
    let before = axStringValue(el)
    let selLen = (attr(el, kAXSelectedTextAttribute) as? String)?.utf16.count ?? 0
    guard AXUIElementSetAttributeValue(el, a as CFString, text as CFString) == .success else { return nil }
    let after = axStringValue(el)
    let verified: Bool
    if replaceAll { verified = after == text }
    else if let a2 = after {
        verified = a2.contains(text) && a2.utf16.count == (before?.utf16.count ?? 0) - selLen + text.utf16.count
    } else { verified = false }
    return ["method": replaceAll ? "ax-value" : "ax-selected-text", "verified": verified, "length": (after ?? "").count]
}
/// 剪贴板 + 菜单「编辑>粘贴」：不用 cmd+v，不经过键盘事件；结束后恢复剪贴板
func pasteWrite(_ appName: String?, _ el: AXUIElement?, _ text: String, replaceAll: Bool) throws -> [String: Any] {
    let snap = snapshotPasteboard()
    var restore = true
    defer { if restore { restorePasteboard(snap) } }
    let before = el.flatMap(axStringValue)
    if replaceAll { _ = try pressMenu(appName, menuSelectAll); sleepMs(50) }
    let pb = NSPasteboard.general
    pb.clearContents(); pb.setString(text, forType: .string)
    _ = try pressMenu(appName, menuPaste)
    // 等应用真正读走剪贴板再恢复，否则会粘贴成旧内容
    var verified = false
    if let el = el {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 2 {
            if let v = axStringValue(el), v != before, v.contains(text) { verified = true; break }
            sleepMs(5)
        }
    } else { sleepMs(300) }
    // 没核对上时，菜单动作可能排队到以后才执行；这时不恢复剪贴板，免得以后粘贴出旧内容
    restore = verified || el == nil
    var o: [String: Any] = ["method": "paste-menu", "verified": verified, "length": (el.flatMap(axStringValue) ?? "").count, "clipboardRestored": restore]
    if !restore { o["note"] = "粘贴没有立即生效，可能会在事件流恢复后才执行；剪贴板里保留了要输入的文字" }
    return o
}

/// 先试辅助功能写值，不行（或 --via paste）再走剪贴板 + 菜单粘贴
func writeText(_ appName: String?, _ el: AXUIElement?, _ text: String, replaceAll: Bool, via: String) throws -> [String: Any] {
    if via != "paste", let el = el {
        let before = axStringValue(el)
        if let r = axWrite(el, text, replaceAll: replaceAll) {
            // 已核对成功，或者值确实变了（不重复粘贴，避免写两遍）
            if (r["verified"] as? Bool) == true || via == "ax" || axStringValue(el) != before { return r }
        } else if via == "ax" {
            try fail("这个元素不支持用辅助功能写入（\(replaceAll ? "AXValue" : "AXSelectedText") 不可写），试试 --via paste")
        }
    }
    if via == "ax" { try fail("没有可写入的焦点元素") }
    return try pasteWrite(appName, el, text, replaceAll: replaceAll)
}
// MARK: - 多条输入路径：type / key 自动选路
// type：辅助功能写值（ax）→ 键盘事件（events，事件流健康时）→ 直接投递给应用进程（pid）→ 剪贴板 + 菜单「粘贴」（paste）
// key ：键盘事件（events，事件流健康时）→ 按快捷键对应的菜单项（menu）→ 直接投递给应用进程（pid）
let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
/// 等输入框的值变化并包含 text。读不到值时返回 nil（无法核对）
func waitValueChange(_ el: AXUIElement?, from before: String?, contains text: String, ms: Int) -> Bool? {
    guard let el = el, before != nil else { return nil }
    let t0 = Date()
    repeat {
        if let v = axStringValue(el), v != before, v.contains(text) { return true }
        sleepMs(5)
    } while Date().timeIntervalSince(t0) * 1000 < Double(ms)
    return false
}
func jsonText(_ o: Any) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "\(o)" }
    return String(data: d, encoding: .utf8) ?? "\(o)"
}
func typeChain(_ appOpt: String?, _ text: String, via: String, window: String? = nil) throws -> [String: Any] {
    guard ["auto", "ax", "events", "pid", "paste"].contains(via) else { try fail("--via 只能是 auto、ax、events、pid、paste") }
    let h = inputHealth()
    let (root, app) = try axRoot(appOpt)
    let el = axElement(attr(root, kAXFocusedUIElementAttribute))
    let role = el.flatMap { str($0, kAXRoleAttribute) } ?? ""
    // --window：焦点元素必须在标题含该文字的窗口里，否则拒绝输入（防止打进别的文稿）
    if let w = window {
        let wt = el.flatMap(windowTitle(of:)) ?? ""
        guard el != nil, wt.localizedCaseInsensitiveContains(w) else { try fail("焦点元素在窗口「\(wt)」里，不是「\(w)」，已拒绝输入", code: 4) }
    }
    let appKey = app.bundleIdentifier ?? app.localizedName ?? ""
    var order: [String]
    if via == "auto" {
        order = []
        // 标准文本框总是先走辅助功能（不经过事件流，最快且能核对）；事件流卡住时任何焦点元素都先试一下
        if el != nil && (textRoles.contains(role) || !h.keyboardOK) { order.append("ax") }
        order += h.keyboardOK ? ["events"] : ["pid", "paste"]
    } else { order = [via] }
    var tried: [[String: Any]] = []
    func result(_ path: String, _ verified: Any, _ extra: [String: Any] = [:]) -> [String: Any] {
        var o: [String: Any] = ["ok": true, "path": path, "verified": verified, "app": app.localizedName ?? "", "pid": Int(app.processIdentifier),
                                "role": role, "eventsHealthy": h.keyboardOK, "tried": tried]
        if let el = el, let w = windowTitle(of: el) { o["window"] = w }
        if !h.keyboardOK { o["blockedBy"] = h.blockerNames }
        if let ov = h.override { o["healthOverride"] = ov }
        o.merge(extra) { a, _ in a }
        return o
    }
    for p in order {
        let before = el.flatMap(axStringValue)
        switch p {
        case "ax":
            guard let el = el else {
                if via == "ax" { try fail("\(app.localizedName ?? "应用") 没有焦点元素，无法用辅助功能输入", code: 4) }
                tried.append(["path": "ax", "result": "没有焦点元素"]); continue
            }
            if let r = axWrite(el, text, replaceAll: false) {
                if (r["verified"] as? Bool) == true || axStringValue(el) != before { return result("ax-selected-text", r["verified"] ?? false) }
                tried.append(["path": "ax-selected-text", "result": "写入后内容没变"])
            } else { tried.append(["path": "ax-selected-text", "result": "AXSelectedText 不可写"]) }
        case "events":
            keyTargetPid = appOpt == nil ? nil : app.processIdentifier
            typeText(text); keyTargetPid = nil
            let v = waitValueChange(el, from: before, contains: text, ms: 300)
            return result(appOpt == nil ? "events-hid" : "events-pid", v.map { $0 as Any } ?? "unknown")
        case "pid":
            // CGEventPostToPid：直接投递到应用进程的事件队列，不经过系统 HID 事件流上的监听
            keyTargetPid = app.processIdentifier
            typeText(text); keyTargetPid = nil
            let v = waitValueChange(el, from: before, contains: text, ms: 600)
            if v == true || via == "pid" { return result("events-pid", v.map { $0 as Any } ?? "unknown") }
            if v == nil { return result("events-pid", "unknown", ["note": "读不到输入框内容，无法核对；为避免重复输入，不再尝试其它路径"]) }
            tried.append(["path": "events-pid", "result": "600 毫秒内没有生效（事件可能在排队，稍后才出现）"])
        case "paste":
            let r = try pasteWrite(appKey, el, text, replaceAll: false)
            if (r["verified"] as? Bool) == true || el == nil || via == "paste" { return result("paste-menu", r["verified"] ?? false, r) }
            tried.append(["path": "paste-menu", "result": "菜单「粘贴」后内容没变", "clipboardRestored": r["clipboardRestored"] ?? true])
        default: break
        }
    }
    try fail("所有输入路径都没有生效（事件流\(h.keyboardOK ? "正常" : "卡住: " + h.blockerNames.joined(separator: ", "))）。尝试过: \(jsonText(tried))。可用 insert/settext 指定输入框，或 xyzlcu taps 排查", code: 4)
}

/// AXMenuItemCmdGlyph 的取值（Carbon 菜单字形常量），用来匹配回车、删除、方向键等特殊键的快捷键
let menuGlyphs: [String: Int] = ["tab": 2, "enter": 4, "kpenter": 4, "space": 9, "forwarddelete": 10, "return": 11, "delete": 23, "backspace": 23,
    "esc": 27, "escape": 27, "pageup": 98, "left": 100, "right": 101, "home": 102, "up": 104, "end": 105, "down": 106, "pagedown": 107,
    "f1": 111, "f2": 112, "f3": 113, "f4": 114, "f5": 115, "f6": 116, "f7": 117, "f8": 118, "f9": 119, "f10": 120, "f11": 121, "f12": 122]
let menuScanAttrs = [kAXRoleAttribute, kAXTitleAttribute, "AXMenuItemCmdChar", "AXMenuItemCmdVirtualKey", "AXMenuItemCmdModifiers",
                     kAXChildrenAttribute, kAXEnabledAttribute, "AXMenuItemCmdGlyph"] as CFArray
/// 在应用菜单栏里找快捷键等于 combo 的菜单项（按 pid 读取，不激活应用）。优先返回可用的菜单项
func menuItemForShortcut(_ root: AXUIElement, keyName: String, keycode: CGKeyCode, flags: CGEventFlags) -> (AXUIElement, String, Bool)? {
    guard let bar = axElement(attr(root, kAXMenuBarAttribute)) else { return nil }
    let want = (flags.contains(.maskCommand), flags.contains(.maskShift), flags.contains(.maskAlternate), flags.contains(.maskControl))
    var queue: [(AXUIElement, String)] = children(bar).map { ($0, "") }
    var head = 0
    var fallback: (AXUIElement, String, Bool)? = nil
    while head < queue.count && head < 6000 {
        let (el, prefix) = queue[head]; head += 1
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(el, menuScanAttrs, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let v = raw as? [AnyObject], v.count == 8 else { continue }
        let role = axs(clean(v[0])) ?? "", title = axs(clean(v[1])) ?? ""
        let path = title.isEmpty ? prefix : (prefix.isEmpty ? title : prefix + ">" + title)
        if role == "AXMenuItem" {
            let ch = axs(clean(v[2])) ?? ""
            let vk = (clean(v[3]) as? NSNumber)?.intValue
            let mods = (clean(v[4]) as? NSNumber)?.intValue ?? 0
            let glyph = (clean(v[7]) as? NSNumber)?.intValue
            var keyOK = false
            if !ch.isEmpty && keyName.count == 1 { keyOK = ch.uppercased() == keyName.uppercased() }
            if !keyOK, let g = glyph, g != 0, let wg = menuGlyphs[keyName] { keyOK = g == wg }
            if !keyOK, ch.isEmpty, let vk = vk, vk != 0 { keyOK = vk == Int(keycode) }
            // kAXMenuItemModifier：Shift=1、Option=2、Control=4、NoCommand=8（不带 8 表示含 Command）
            let have = (mods & 8 == 0, mods & 1 != 0, mods & 2 != 0, mods & 4 != 0)
            if keyOK && have == want && (!ch.isEmpty || glyph != nil || vk != nil) {
                let enabled = (clean(v[6]) as? Bool) ?? true
                if enabled { return (el, path, true) }
                if fallback == nil { fallback = (el, path, false) }
            }
        }
        if let kids = clean(v[5]) as? [AXUIElement] { queue.append(contentsOf: kids.map { ($0, path) }) }
    }
    return fallback
}
func keyChain(_ appOpt: String?, _ combos: [String], via: String) throws -> [String: Any] {
    guard ["auto", "events", "menu", "pid"].contains(via) else { try fail("--via 只能是 auto、events、menu、pid") }
    let h = inputHealth()
    let app: NSRunningApplication
    if let a = appOpt { guard let x = findApp(a) else { try fail("找不到应用: \(a)") }; app = x }
    else { guard let x = NSWorkspace.shared.frontmostApplication else { try fail("没有前台应用") }; app = x }
    let order: [String] = via == "auto" ? (h.keyboardOK ? ["events"] : ["menu", "pid"]) : [via]
    var results: [[String: Any]] = []
    for (i, c) in combos.enumerated() {
        if i > 0 { sleepMs(stepDelay) }
        let (k, f, name) = try parseCombo(c)
        var tried: [[String: Any]] = []
        var done: [String: Any]? = nil
        paths: for p in order {
            switch p {
            case "events":
                keyTargetPid = appOpt == nil ? nil : app.processIdentifier
                postCombo(k, f); keyTargetPid = nil
                done = ["key": c, "path": appOpt == nil ? "events-hid" : "events-pid"]
            case "menu":
                let ax = AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(ax, 3)
                if let (el, path, enabled) = menuItemForShortcut(ax, keyName: name, keycode: k, flags: f) {
                    let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
                    if r == .success { done = ["key": c, "path": "menu", "menuItem": path, "enabledBefore": enabled] }
                    else { tried.append(["path": "menu", "menuItem": path, "result": "AXPress 失败: AXError \(r.rawValue)"]) }
                } else { tried.append(["path": "menu", "result": "\(app.localizedName ?? "应用") 的菜单栏里没有快捷键为 \(c) 的菜单项"]) }
            case "pid":
                keyTargetPid = app.processIdentifier
                postCombo(k, f); keyTargetPid = nil
                done = ["key": c, "path": "events-pid", "note": "按键已直接投递给应用进程，无法核对是否生效"]
            default: break
            }
            if done != nil { break paths }
        }
        guard var d = done else {
            try fail("快捷键 \(c) 没有可用路径（事件流\(h.keyboardOK ? "正常" : "卡住")）。尝试过: \(jsonText(tried))。可用 menu \"App\" \"菜单>菜单项\" 指定", code: 4)
        }
        if !tried.isEmpty { d["tried"] = tried }
        results.append(d)
    }
    var o: [String: Any] = ["ok": true, "app": app.localizedName ?? "", "pid": Int(app.processIdentifier), "eventsHealthy": h.keyboardOK, "keys": results]
    if !h.keyboardOK { o["blockedBy"] = h.blockerNames }
    if let ov = h.override { o["healthOverride"] = ov }
    return o
}
/// 不激活应用，把它的某个窗口设为主窗口（菜单动作作用于主窗口 / 关键窗口）
func setMainWindow(_ appName: String, _ title: String) throws -> String {
    let (root, app) = try axRoot(appName)
    let wins = (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    guard let w = wins.first(where: { (str($0, kAXTitleAttribute) ?? "").localizedCaseInsensitiveContains(title) }) else {
        try fail("\(app.localizedName ?? appName) 没有标题含「\(title)」的窗口", code: 4)
    }
    AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    return str(w, kAXTitleAttribute) ?? ""
}

// MARK: - 录制 / 回放（只监听的事件监听：不拦截、不修改任何输入，卡住也不会挡键盘）
let recNames: [(String, CGEventType)] = [("leftMouseDown", .leftMouseDown), ("leftMouseUp", .leftMouseUp), ("rightMouseDown", .rightMouseDown),
    ("rightMouseUp", .rightMouseUp), ("otherMouseDown", .otherMouseDown), ("otherMouseUp", .otherMouseUp), ("mouseMoved", .mouseMoved),
    ("leftMouseDragged", .leftMouseDragged), ("rightMouseDragged", .rightMouseDragged), ("otherMouseDragged", .otherMouseDragged),
    ("scrollWheel", .scrollWheel), ("keyDown", .keyDown), ("keyUp", .keyUp), ("flagsChanged", .flagsChanged)]
var recOut: FileHandle? = nil
var recStart: CFAbsoluteTime = 0
var recCount = 0, recSecureSkipped = 0
var recLastMove: CFAbsoluteTime = 0
var recMoves = true
var recTap: CFMachPort? = nil
var recStopReason = ""
func recWrite(_ o: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
    recOut?.write(d); recOut?.write(Data("\n".utf8))
}
func recordEvent(_ type: CGEventType, _ e: CGEvent) {
    guard let name = recNames.first(where: { $0.1 == type })?.0 else { return }
    let now = CFAbsoluteTimeGetCurrent()
    let isKey = type == .keyDown || type == .keyUp || type == .flagsChanged
    if isKey {
        // 密码框等安全输入开启时、或锁屏时，不记录按键
        if IsSecureEventInputEnabled() || screenLocked() { recSecureSkipped += 1; return }
    }
    let isMove = type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged
    if isMove {
        if type == .mouseMoved && !recMoves { return }
        if now - recLastMove < 0.015 { return }  // 移动事件最多约 66 次/秒
        recLastMove = now
    }
    var o: [String: Any] = ["t": Int((now - recStart) * 1000), "type": name]
    let p = e.location
    o["x"] = (p.x * 10).rounded() / 10; o["y"] = (p.y * 10).rounded() / 10
    if isKey {
        o["keycode"] = Int(e.getIntegerValueField(.keyboardEventKeycode)); o["flags"] = e.flags.rawValue
        if type == .keyDown {
            var len = 0; var buf = [UniChar](repeating: 0, count: 8)
            e.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: &buf)
            if len > 0 { o["chars"] = String(utf16CodeUnits: buf, count: len) }
            if e.getIntegerValueField(.keyboardEventAutorepeat) != 0 { o["repeat"] = true }
        }
    } else if type == .scrollWheel {
        o["dy"] = Int(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)); o["dx"] = Int(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
    } else {
        o["button"] = Int(e.getIntegerValueField(.mouseEventButtonNumber)); o["clicks"] = Int(e.getIntegerValueField(.mouseEventClickState))
        if e.flags.rawValue & 0x00FF0000 != 0 { o["flags"] = e.flags.rawValue }
    }
    recWrite(o); recCount += 1
}
func recordSession(outPath: String, duration: Double, moves: Bool) throws {
    if daemonMode { try fail("record 要在前台进程里运行（不经过守护进程）") }
    if screenLocked() { try fail("屏幕已锁定，拒绝录制", code: 3) }
    var mask: CGEventMask = 0
    for (_, t) in recNames { mask |= evBit(t) }
    let dir = (outPath as NSString).deletingLastPathComponent
    if !dir.isEmpty { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
    guard FileManager.default.createFile(atPath: outPath, contents: nil, attributes: [.posixPermissions: 0o600]),
          let fh = FileHandle(forWritingAtPath: outPath) else { try fail("无法写入: \(outPath)") }
    recOut = fh; recMoves = moves; recCount = 0; recSecureSkipped = 0; recStopReason = ""
    recStart = CFAbsoluteTimeGetCurrent()
    let disp: [[String: Int]] = activeDisplays().map { d in let b = CGDisplayBounds(d); return ["x": Int(b.minX), "y": Int(b.minY), "w": Int(b.width), "h": Int(b.height)] }
    recWrite(["kind": "header", "xyzlcu": version, "startedAt": ISO8601DateFormatter().string(from: Date()), "displays": disp])
    let cb: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = recTap { CGEvent.tapEnable(tap: t, enable: true) }
        } else { recordEvent(type, event) }
        return Unmanaged.passUnretained(event)
    }
    // listenOnly：只看不拦，回调慢了也不会耽误任何输入；只在 record 运行期间存在
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                      eventsOfInterest: mask, callback: cb, userInfo: nil) else {
        fh.closeFile(); recOut = nil; try? FileManager.default.removeItem(atPath: outPath)
        try fail("创建只监听的事件监听失败：需要「输入监控」或「辅助功能」权限（系统设置 > 隐私与安全性）", code: 2)
    }
    recTap = tap
    let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    var sigs: [DispatchSourceSignal] = []
    for sg in [SIGINT, SIGTERM, SIGHUP] {
        signal(sg, SIG_IGN)
        let d = DispatchSource.makeSignalSource(signal: sg, queue: .main)
        d.setEventHandler { recStopReason = "interrupted"; CFRunLoopStop(CFRunLoopGetMain()) }
        d.resume(); sigs.append(d)
    }
    let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
        if screenLocked() { recStopReason = "screen-locked"; CFRunLoopStop(CFRunLoopGetMain()) }
        else if CFAbsoluteTimeGetCurrent() - recStart >= duration { recStopReason = "duration"; CFRunLoopStop(CFRunLoopGetMain()) }
    }
    RunLoop.main.add(timer, forMode: .common)
    FileHandle.standardError.write("录制中（只监听，不拦截输入）… 最长 \(Int(duration)) 秒，Ctrl-C 提前结束\n".data(using: .utf8)!)
    CFRunLoopRun()
    timer.invalidate()
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
    CFMachPortInvalidate(tap); recTap = nil
    for d in sigs { d.cancel() }
    for sg in [SIGINT, SIGTERM, SIGHUP] { signal(sg, SIG_DFL) }
    fh.closeFile(); recOut = nil
    out(["path": outPath, "events": recCount, "durationMs": Int((CFAbsoluteTimeGetCurrent() - recStart) * 1000),
         "stoppedBy": recStopReason, "skippedSecureKeys": recSecureSkipped, "tap": "listenOnly"])
}
func numv(_ o: [String: Any], _ k: String) -> Double? { (o[k] as? NSNumber)?.doubleValue }
func replaySession(path: String, speed: Double, force: Bool, noKeys: Bool) throws {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { try fail("读不到录制文件: \(path)") }
    let evs = text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        .filter { $0["kind"] == nil && $0["type"] is String }
    let keyTypes: Set<String> = ["keyDown", "keyUp", "flagsChanged"]
    let hasKeys = !noKeys && evs.contains { keyTypes.contains($0["type"] as! String) }
    let hasMouse = evs.contains { !keyTypes.contains($0["type"] as! String) }
    let h = inputHealth()
    if !force {
        // 事件流卡住时回放的事件会排队，以后才一股脑执行，所以默认拒绝
        if hasKeys && !h.keyboardOK { try fail("键盘事件流卡住（\(h.blockerNames.joined(separator: ", "))），回放的按键会排队到以后才执行，已拒绝。加 --force 强制", code: 4) }
        if hasMouse && !h.mouseOK { try fail("鼠标事件流卡住，已拒绝回放。加 --force 强制", code: 4) }
    }
    let sp = speed > 0 ? speed : 1
    let t0 = CFAbsoluteTimeGetCurrent(); var n = 0
    for ev in evs {
        let name = ev["type"] as! String
        if noKeys && keyTypes.contains(name) { continue }
        guard let type = recNames.first(where: { $0.0 == name })?.1 else { continue }
        let due = (numv(ev, "t") ?? 0) / 1000 / sp
        let wait = due - (CFAbsoluteTimeGetCurrent() - t0)
        if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
        if screenLocked() { try fail("屏幕被锁定，回放已停止（已回放 \(n) / \(evs.count) 个事件）", code: 3) }
        let p = CGPoint(x: numv(ev, "x") ?? 0, y: numv(ev, "y") ?? 0)
        var e: CGEvent?
        switch type {
        case .keyDown, .keyUp:
            e = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(numv(ev, "keycode") ?? 0), keyDown: type == .keyDown)
            // 录到的字符（含程序以 Unicode 字符串发出的输入）原样带回去
            if let c = ev["chars"] as? String, !c.isEmpty {
                let u = Array(c.utf16); e?.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u)
            }
        case .flagsChanged:
            e = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(numv(ev, "keycode") ?? 0), keyDown: true); e?.type = .flagsChanged
        case .scrollWheel:
            e = CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel, wheelCount: 2, wheel1: Int32(numv(ev, "dy") ?? 0), wheel2: Int32(numv(ev, "dx") ?? 0), wheel3: 0)
            e?.location = p
        default:
            let btn = CGMouseButton(rawValue: UInt32(numv(ev, "button") ?? 0)) ?? .left
            e = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: p, mouseButton: btn)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(numv(ev, "clicks") ?? 1))
        }
        if let f = ev["flags"] as? NSNumber { e?.flags = CGEventFlags(rawValue: f.uint64Value) }
        e?.post(tap: .cghidEventTap); n += 1
    }
    out(["path": path, "events": n, "ms": Int((CFAbsoluteTimeGetCurrent() - t0) * 1000), "speed": sp, "keysSkipped": noKeys])
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
func pixelsPerPoint(_ did: CGDirectDisplayID) -> Double {
    let b = CGDisplayBounds(did)
    guard let m = CGDisplayCopyDisplayMode(did), b.width > 0 else { return 1 }
    return Double(m.pixelWidth) / Double(b.width)
}
enum ImgFormat: String {
    case png, jpeg, heic
    var ext: String { self == .jpeg ? "jpg" : rawValue }
    static func parse(_ s: String) throws -> ImgFormat {
        switch s.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        default: try fail("--format 只支持 png / jpg / heic")
        }
    }
    static func fromPath(_ p: String) -> ImgFormat? {
        switch (p as NSString).pathExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        default: return nil
        }
    }
}
/// 已知格式（RGBX、每像素 4 字节）的像素缓冲：PNG 编码和截图差异比较都用它。
/// 保留原图的色彩空间（不做色彩转换，省时间），PNG 里用 iCCP 块带上它的 ICC 描述
final class Pixels {
    let w: Int, h: Int, bpr: Int
    let ctx: CGContext
    let p: UnsafeMutablePointer<UInt8>
    let space: CGColorSpace
    init?(_ img: CGImage) {
        w = img.width; h = img.height; bpr = w * 4
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        space = img.colorSpace.flatMap { $0.model == .rgb && $0.copyICCData() != nil ? $0 : nil } ?? srgb
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let d = c.data else { return nil }
        c.interpolationQuality = .none
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx = c; p = d.assumingMemoryBound(to: UInt8.self)
    }
}
/// 多线程 PNG 编码：按行分块，每块独立做 Sub 过滤 + deflate（压缩级别 1），块之间用 Z_SYNC_FLUSH 接起来，
/// 校验和用 adler32_combine 合并。结果是标准的无损 PNG（RGB 8 位、sRGB）。
/// 4112×2658 的整屏：ImageIO 约 160 毫秒，这里约 20 毫秒，文件还小一些。
func fastPNG(_ px: Pixels, level: Int32) -> Data? {
    let w = px.w, h = px.h, base = px.p, bpr = px.bpr
    let bands = min(h, max(1, ProcessInfo.processInfo.activeProcessorCount * 2))
    let rowsPer = (h + bands - 1) / bands
    let nb = (h + rowsPer - 1) / rowsPer          // 实际块数（每块至少一行）
    let rowLen = 1 + w * 3
    var outs = [Data](repeating: Data(), count: nb)
    var adlers = [uLong](repeating: 0, count: nb)
    var lens = [Int](repeating: 0, count: nb)
    var ok = true
    outs.withUnsafeMutableBufferPointer { outP in
    adlers.withUnsafeMutableBufferPointer { adP in
    lens.withUnsafeMutableBufferPointer { lnP in
    DispatchQueue.concurrentPerform(iterations: nb) { b in
        let y0 = b * rowsPer, y1 = min(h, y0 + rowsPer)
        let n = (y1 - y0) * rowLen
        let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: n); defer { raw.deallocate() }
        for y in y0..<y1 {
            let src = base + y * bpr, o = raw + (y - y0) * rowLen
            o[0] = 1   // Sub 过滤
            var pr: UInt8 = 0, pg: UInt8 = 0, pb: UInt8 = 0, j = 1, i = 0
            for _ in 0..<w {
                let r = src[i], g = src[i + 1], bl = src[i + 2]
                o[j] = r &- pr; o[j + 1] = g &- pg; o[j + 2] = bl &- pb
                pr = r; pg = g; pb = bl; i += 4; j += 3
            }
        }
        lnP[b] = n
        adP[b] = adler32(1, raw, uInt(n))
        var zs = z_stream()
        guard deflateInit2_(&zs, level, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { ok = false; return }
        let cap = Int(deflateBound(&zs, uLong(n))) + 64
        let ob = UnsafeMutablePointer<UInt8>.allocate(capacity: cap); defer { ob.deallocate() }
        zs.next_in = raw; zs.avail_in = uInt(n); zs.next_out = ob; zs.avail_out = uInt(cap)
        let r = deflate(&zs, b == nb - 1 ? Z_FINISH : Z_SYNC_FLUSH)
        if (b == nb - 1 && r != Z_STREAM_END) || (b < nb - 1 && r != Z_OK) || zs.avail_in != 0 { ok = false }
        outP[b] = Data(bytes: ob, count: cap - Int(zs.avail_out))
        deflateEnd(&zs)
    }}}}
    guard ok else { return nil }
    var ad = adlers[0]
    for b in 1..<nb { ad = adler32_combine(ad, adlers[b], lens[b]) }
    func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    png.reserveCapacity(outs.reduce(64) { $0 + $1.count })
    func chunk(_ type: String, _ parts: [Data]) {
        png.append(contentsOf: be32(UInt32(parts.reduce(0) { $0 + $1.count })))
        let t = Data(type.utf8)
        var crc = t.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, 4) }
        png.append(t)
        for d in parts {
            crc = d.withUnsafeBytes { crc32(crc, $0.bindMemory(to: UInt8.self).baseAddress, uInt(d.count)) }
            png.append(d)
        }
        png.append(contentsOf: be32(UInt32(crc)))
    }
    chunk("IHDR", [Data(be32(UInt32(w)) + be32(UInt32(h)) + [8, 2, 0, 0, 0])])
    let isSRGB = (px.space.name as String?) == (CGColorSpace.sRGB as String)
    if !isSRGB, let icc = px.space.copyICCData() as Data?, let z = zlibCompress(icc) {
        chunk("iCCP", [Data("ICC Profile".utf8) + [0, 0], z])
    } else {
        chunk("sRGB", [Data([0])])
    }
    chunk("IDAT", [Data([0x78, 0x01])] + outs + [Data(be32(UInt32(ad)))])
    chunk("IEND", [])
    return png
}
func zlibCompress(_ d: Data) -> Data? {
    var n = compressBound(uLong(d.count))
    var o = [UInt8](repeating: 0, count: Int(n))
    let r = d.withUnsafeBytes { compress2(&o, &n, $0.bindMemory(to: UInt8.self).baseAddress, uLong(d.count), 6) }
    return r == Z_OK ? Data(o[0..<Int(n)]) : nil
}
/// 在内存里编码（不落盘）；需要文件时再一次性写出。PNG 默认走上面的多线程编码（XYZLCU_PNG=imageio 改回系统编码器）
func encodeImage(_ img: CGImage, format: ImgFormat, quality: Double, pixels: Pixels? = nil) -> Data? {
    if format == .png, envv("XYZLCU_PNG") != "imageio" {
        let level = Int32(envv("XYZLCU_PNG_LEVEL") ?? "") ?? 1
        if let px = pixels ?? Pixels(img), let d = fastPNG(px, level: max(1, min(9, level))) { return d }
    }
    let type = (format == .png ? "public.png" : format == .jpeg ? "public.jpeg" : "public.heic") as CFString
    let buf = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(buf as CFMutableData, type, 1, nil) else { return nil }
    let props: [CFString: Any] = format == .png ? [:] : [kCGImageDestinationLossyCompressionQuality: quality]
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    return CGImageDestinationFinalize(dest) ? buf as Data : nil
}
/// --stdout 时的原始图像字节（守护进程里随回复带回客户端）和放到 stderr 的元数据
var binOut: Data? = nil
var binMeta: String? = nil
func scaled(_ img: CGImage, _ s: Double) -> CGImage {
    let w = max(1, Int(Double(img.width) * s)), h = max(1, Int(Double(img.height) * s))
    // 用原图的色彩空间：不做色彩转换，快很多（色彩描述照样跟着图走）
    let space = img.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return img }
    ctx.interpolationQuality = .medium
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage() ?? img
}
// MARK: - 截图差异（--diff）：守护进程记住每个目标上一次的画面，只返回变了的区域
final class PrevFrame { let px: Pixels; var used = Date(); init(_ p: Pixels) { px = p } }
var prevFrames: [String: PrevFrame] = [:]
/// 按 32 像素的格子比较，相连（含对角）的变化格子合成一个矩形；矩形太多就合成一个总的外框
func diffRects(_ a: Pixels, _ b: Pixels, tile: Int = 32) -> (rects: [CGRect], changedTiles: Int, totalTiles: Int) {
    let w = b.w, h = b.h, tw = (w + tile - 1) / tile, th = (h + tile - 1) / tile
    var grid = [Bool](repeating: false, count: tw * th)
    grid.withUnsafeMutableBufferPointer { g in
        DispatchQueue.concurrentPerform(iterations: th) { ty in
            let y0 = ty * tile, y1 = min(h, y0 + tile)
            for tx in 0..<tw {
                let x0 = tx * tile, n = (min(w, x0 + tile) - x0) * 4
                for y in y0..<y1 where memcmp(a.p + y * a.bpr + x0 * 4, b.p + y * b.bpr + x0 * 4, n) != 0 { g[ty * tw + tx] = true; break }
            }
        }
    }
    var seen = [Bool](repeating: false, count: tw * th)
    var rects: [CGRect] = []; var changed = 0
    for start in 0..<(tw * th) where grid[start] && !seen[start] {
        var stack = [start]; seen[start] = true
        var minX = tw, minY = th, maxX = 0, maxY = 0
        while let c = stack.popLast() {
            changed += 1
            let cx = c % tw, cy = c / tw
            minX = min(minX, cx); maxX = max(maxX, cx); minY = min(minY, cy); maxY = max(maxY, cy)
            for dy in -1...1 { for dx in -1...1 {
                let nx = cx + dx, ny = cy + dy
                if nx < 0 || ny < 0 || nx >= tw || ny >= th { continue }
                let k = ny * tw + nx
                if grid[k] && !seen[k] { seen[k] = true; stack.append(k) }
            } }
        }
        rects.append(CGRect(x: minX * tile, y: minY * tile, width: min(w, (maxX + 1) * tile) - minX * tile, height: min(h, (maxY + 1) * tile) - minY * tile))
    }
    if rects.count > 12 { rects = [rects.dropFirst().reduce(rects[0]) { $0.union($1) }] }
    return (rects.sorted { $0.minY == $1.minY ? $0.minX < $1.minX : $0.minY < $1.minY }, changed, tw * th)
}
/// 等待回调。在主线程上等时要同时转主运行循环：命令行（不经守护进程）时 ScreenCaptureKit 的回调
/// 需要主运行循环才会到，干等信号量会一直等到超时（实测每次 5 秒）。
func waitSignal(_ sem: DispatchSemaphore, timeout: Double) -> Bool {
    guard Thread.isMainThread else { return sem.wait(timeout: .now() + timeout) == .success }
    let deadline = Date(timeIntervalSinceNow: timeout)
    while sem.wait(timeout: .now() + 0.001) == .timedOut {
        if Date() >= deadline { return false }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
    }
    return true
}
/// ScreenCaptureKit 回调超时过一次就不再重试，直接改用 screencapture。
/// 实测：同一路径的 xyzlcu 守护进程在运行时，XYZLCU_DAEMON=0 的进程内截图拿不到回调。
var sckTimedOut = false
var sckTimeout: Double { daemonMode ? 5 : 1.5 }
/// SCShareableContent 取一次要几十毫秒；守护进程里缓存起来复用
var cachedContent: AnyObject? = nil
var cachedAt = Date.distantPast
@available(macOS 14.0, *)
func shareableContent(maxAge: Double) -> SCShareableContent? {
    if maxAge > 0, daemonMode, let c = cachedContent as? SCShareableContent, Date().timeIntervalSince(cachedAt) < maxAge { return c }
    let sem = DispatchSemaphore(value: 0)
    var result: SCShareableContent?
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, _ in result = c; sem.signal() }
    if !waitSignal(sem, timeout: sckTimeout) { sckTimedOut = true; return nil }
    if let r = result { cachedContent = r; cachedAt = Date() }
    return result
}
@available(macOS 14.0, *)
func grab(_ filter: SCContentFilter, _ cfg: SCStreamConfiguration) -> CGImage? {
    let sem = DispatchSemaphore(value: 0)
    var result: CGImage?
    SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { img, _ in result = img; sem.signal() }
    if !waitSignal(sem, timeout: sckTimeout) { sckTimedOut = true; return nil }
    return result
}
enum Target { case display(CGDirectDisplayID), region(CGDirectDisplayID, CGRect), window(CGWindowID, CGRect) }
// MARK: - 常驻截图流（只在守护进程里）
// 同一目标、同一缩放第一次截图走 SCScreenshotManager，同时在后台开一路 SCStream（由 GPU 缩放到目标尺寸）；
// 之后的截图直接取流里最新的一帧（内存里，几毫秒）。同一目标已有原始分辨率的流时，新的缩放先从它缩（vImage），同时开新流。
// 画面不变时流不出新帧、几乎不占资源；闲置 XYZLCU_STREAM_IDLE 秒（默认 20）自动关掉。XYZLCU_STREAM=0 关闭这个功能。
// 预热：守护进程启动时就给主屏开流（XYZLCU_PREWARM_SCALES，默认 "1,0.5"：原始分辨率 + --fast 用的一半；XYZLCU_PREWARM=0 关闭），
// 预热的流闲置 XYZLCU_PREWARM_IDLE 秒（默认 600）才关。
// 代价：流开着时菜单栏会一直显示屏幕录制指示；画面变化时每路每秒最多收 60 帧（GPU 拷贝，CPU 很少），原始分辨率一路约占 45 MB 显存/内存。
var lastInputAt = Date.distantPast
var streamsEnabled: Bool { daemonMode && ProcessInfo.processInfo.environment["XYZLCU_STREAM"] != "0" }
@available(macOS 14.0, *)
final class LiveStream: NSObject, SCStreamOutput, SCStreamDelegate {
    let key: String, rect: CGRect
    var stream: SCStream?
    let queue = DispatchQueue(label: "xyzlcu.stream")
    let lock = NSLock()
    var latest: CVPixelBuffer?
    var latestAt = Date.distantPast
    var lastUsed = Date()
    var failed = false
    init(key: String, rect: CGRect) { self.key = key; self.rect = rect }
    func start(_ filter: SCContentFilter, _ cfg: SCStreamConfiguration) {
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        do { try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue) } catch { failed = true; return }
        stream = s
        s.startCapture { [weak self] e in if e != nil { self?.failed = true } }
    }
    func stop() { stream?.stopCapture { _ in }; stream = nil }
    func stream(_ stream: SCStream, didStopWithError error: Error) { failed = true }
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = atts.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        lock.lock(); latest = pb; latestAt = Date(); lock.unlock()
    }
    /// 最新一帧。刚发过鼠标/键盘事件时，最多再等 maxWait 秒看有没有新帧（画面没变就不会有，直接用旧帧）
    func frame(maxWait: Double, scale: Double = 1) -> CGImage? {
        if failed { return nil }
        let deadline = Date(timeIntervalSinceNow: maxWait)
        while true {
            lock.lock(); let pb = latest, at = latestAt; lock.unlock()
            if pb != nil && (at > lastInputAt || Date() >= deadline) {
                var img: CGImage?
                VTCreateCGImageFromCVPixelBuffer(pb!, options: nil, imageOut: &img)
                lastUsed = Date()
                if abs(scale - 1) > 0.001, let i = img { return vScaled(pb!, i, scale) ?? scaled(i, scale) }
                return img
            }
            if pb == nil && Date() >= deadline { return nil }
            usleep(2000)
        }
    }
}
/// 直接在流的像素缓冲上用 vImage 缩放（多线程，比 CGContext 重画快）
func vScaled(_ pb: CVPixelBuffer, _ ref: CGImage, _ s: Double) -> CGImage? {
    guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else { return nil }
    CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
    var src = vImage_Buffer(data: base, height: vImagePixelCount(CVPixelBufferGetHeight(pb)), width: vImagePixelCount(CVPixelBufferGetWidth(pb)),
                            rowBytes: CVPixelBufferGetBytesPerRow(pb))
    let w = max(1, Int(Double(src.width) * s)), h = max(1, Int(Double(src.height) * s)), rb = w * 4
    let out = UnsafeMutableRawPointer.allocate(byteCount: rb * h, alignment: 64)
    var dst = vImage_Buffer(data: out, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rb)
    guard vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { out.deallocate(); return nil }
    guard let prov = CGDataProvider(dataInfo: nil, data: out, size: rb * h, releaseData: { _, p, _ in p.deallocate() }),
          let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rb,
                            space: ref.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                            provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
    return img
}
var liveStreams: [String: AnyObject] = [:]
var prewarmKeys: Set<String> = []
var lastCaptureMethod: String? = nil
var streamReaper: Timer? = nil
@available(macOS 14.0, *)
func liveFrame(_ key: String, rect: CGRect, scale: Double = 1) -> CGImage? {
    guard streamsEnabled, let s = liveStreams[key] as? LiveStream else { return nil }
    if s.failed || s.rect != rect { s.stop(); liveStreams[key] = nil; return nil }
    return s.frame(maxWait: Date().timeIntervalSince(lastInputAt) < 1 ? 0.12 : 0, scale: scale)
}
@available(macOS 14.0, *)
func startLiveStream(_ key: String, rect: CGRect, _ filter: SCContentFilter, _ cfg: SCStreamConfiguration) {
    guard streamsEnabled, liveStreams[key] == nil else { return }
    // 最多同时 4 路，超出关掉最久没用的（先关非预热的）
    let all = liveStreams.values.compactMap { $0 as? LiveStream }
    let pool = all.filter { !prewarmKeys.contains($0.key) }
    if all.count >= 4, let old = (pool.isEmpty ? all : pool).min(by: { $0.lastUsed < $1.lastUsed }) { old.stop(); liveStreams[old.key] = nil }
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    cfg.queueDepth = 4
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    let s = LiveStream(key: key, rect: rect)
    s.start(filter, cfg)
    liveStreams[key] = s
    if streamReaper == nil {
        let idle = Double(ProcessInfo.processInfo.environment["XYZLCU_STREAM_IDLE"] ?? "") ?? 20
        let longIdle = Double(ProcessInfo.processInfo.environment["XYZLCU_PREWARM_IDLE"] ?? "") ?? 600
        streamReaper = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            for case let s as LiveStream in liveStreams.values where Date().timeIntervalSince(s.lastUsed) > (prewarmKeys.contains(s.key) ? longIdle : idle) || s.failed {
                s.stop(); liveStreams[s.key] = nil
            }
        }
    }
}

/// 常驻流的键（不含缩放：流总是原始分辨率）
func liveKeyOf(_ target: Target) -> (String, CGRect) {
    switch target {
    case .display(let did): return ("d\(did)", CGDisplayBounds(did))
    case .region(let did, let r): return ("r\(did):\(r.minX),\(r.minY),\(r.width),\(r.height)", r)
    case .window(let wid, let r): return ("w\(wid)", r)
    }
}
/// 快路径：ScreenCaptureKit（macOS 14+），在进程内截图，直接按目标尺寸输出
func captureSCK(_ target: Target, scale: Double, startOnly: Bool = false) -> (CGImage, CGRect)? {
    guard #available(macOS 14.0, *) else { return nil }
    let (baseKey, liveRect) = liveKeyOf(target)
    let native = abs(scale - 1) < 0.001
    let liveKey = native ? baseKey : baseKey + "@\(scale)"
    // 有这个缩放的常驻流就直接取最新一帧
    if let img = liveFrame(liveKey, rect: liveRect) {
        lastCaptureMethod = "screencapturekit-stream"
        return (img, liveRect)
    }
    // 没有，但有原始分辨率的流：先从它缩，同时开这个缩放的流（下次就直接取）
    var bridge: CGImage? = nil
    if !native, let img = liveFrame(baseKey, rect: liveRect, scale: scale) { bridge = img }
    func config(_ w: Double, _ h: Double) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.showsCursor = false; c.captureResolution = .best
        c.width = max(1, Int(w * scale)); c.height = max(1, Int(h * scale))
        return c
    }
    for attempt in 0..<2 {
        if sckTimedOut { return nil }
        // 窗口也用缓存：下面会拿缓存里的窗口位置和 CGWindowList 的实时位置比对，不一致才重新取
        guard let content = shareableContent(maxAge: attempt == 1 ? 0 : 30) else { return nil }
        let filter: SCContentFilter, cfg: SCStreamConfiguration, rect: CGRect
        switch target {
        case .display(let did), .region(let did, _):
            guard let d = content.displays.first(where: { $0.displayID == did }) else { continue }
            let b = CGDisplayBounds(did), pps = pixelsPerPoint(did)
            rect = { if case .region(_, let r) = target { return r }; return b }()
            cfg = config(rect.width * pps, rect.height * pps)
            if case .region(_, let r) = target { cfg.sourceRect = CGRect(x: r.minX - b.minX, y: r.minY - b.minY, width: r.width, height: r.height) }
            filter = SCContentFilter(display: d, excludingWindows: [])
        case .window(let wid, let want):
            guard let w = content.windows.first(where: { $0.windowID == wid }) else { continue }
            let f = w.frame
            if attempt == 0, abs(f.minX - want.minX) > 0.5 || abs(f.minY - want.minY) > 0.5 || abs(f.width - want.width) > 0.5 || abs(f.height - want.height) > 0.5 { continue }
            filter = SCContentFilter(desktopIndependentWindow: w)
            let r = filter.contentRect, pps = Double(filter.pointPixelScale)
            cfg = config(r.width * pps, r.height * pps)
            rect = w.frame
        }
        if startOnly || bridge != nil {
            startLiveStream(liveKey, rect: liveRect, filter, cfg)
            if let b = bridge { lastCaptureMethod = "screencapturekit-stream+scaled"; return (b, rect) }
            return nil
        }
        if let img = grab(filter, cfg) { startLiveStream(liveKey, rect: liveRect, filter, cfg); return (img, rect) }
        if attempt == 0 { continue }; return nil
    }
    return bridge.map { ($0, liveRect) }
}
/// 守护进程启动时给主屏开常驻流（不截图，只开流）
func prewarmMainDisplay() {
    guard #available(macOS 14.0, *), streamsEnabled, ProcessInfo.processInfo.environment["XYZLCU_PREWARM"] != "0", screenTrusted() else { return }
    let did = CGMainDisplayID()
    let scales = (ProcessInfo.processInfo.environment["XYZLCU_PREWARM_SCALES"] ?? "1,0.5").split(separator: ",")
        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 && $0 <= 1 }
    for sc in scales {
        let base = liveKeyOf(.display(did)).0
        prewarmKeys.insert(abs(sc - 1) < 0.001 ? base : base + "@\(sc)")
        _ = captureSCK(.display(did), scale: sc, startOnly: true)
    }
}
/// 慢路径：/usr/sbin/screencapture
func captureCLI(_ extra: [String], tmp: String) -> CGImage? {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x"] + extra + ["-t", "png", tmp]
    try? p.run(); p.waitUntilExit()
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: tmp) as CFURL, nil) else { return nil }
    // 立即解码，否则 defer 删掉临时文件后图像会是全黑
    return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
}
/// 找应用最前面的普通窗口（可按标题过滤）
func appWindow(_ appName: String, title: String?) throws -> (CGWindowID, CGRect, String) {
    guard let app = findApp(appName) else { try fail("找不到应用: \(appName)") }
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    for w in list where (w[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier) && (w[kCGWindowLayer as String] as? Int ?? 0) == 0 {
        let t = w[kCGWindowName as String] as? String ?? ""
        if let want = title, !t.localizedCaseInsensitiveContains(want) { continue }
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let r = CGRect(x: b["X"] as? Double ?? 0, y: b["Y"] as? Double ?? 0, width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
        if r.width < 2 || r.height < 2 { continue }
        return (CGWindowID(w[kCGWindowNumber as String] as? Int ?? 0), r, t)
    }
    try fail("\(app.localizedName ?? appName) 没有可见窗口" + (title.map { "（标题含 \($0)）" } ?? ""))
}
func screenshot(path: String?, scale: Double?, display: Int, region: CGRect?, window: (String, String?)?, format: ImgFormat, quality: Double, forceCLI: Bool,
                base64: Bool = false, toStdout: Bool = false, timing: Bool = false, diff: Bool = false) throws {
    let t0 = Date(); var marks: [String: Int] = [:]
    func mark(_ k: String) { marks[k] = Int(Date().timeIntervalSince(t0) * 1000) }
    let displays = activeDisplays()
    let s = (scale ?? 1) > 0 ? (scale ?? 1) : 1
    var target: Target
    var cliArgs: [String]
    var rect: CGRect
    var extra: [String: Any] = [:]
    if let (app, title) = window {
        let (wid, r, t) = try appWindow(app, title: title)
        target = .window(wid, r); cliArgs = ["-o", "-l", String(wid)]; rect = r
        extra = ["window": t, "windowId": Int(wid)]
    } else if let r = region {
        let did = displays.first { CGDisplayBounds($0).contains(CGPoint(x: r.midX, y: r.midY)) } ?? CGMainDisplayID()
        target = .region(did, r); rect = r
        cliArgs = ["-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"]
    } else {
        guard display >= 1 && display <= displays.count else { try fail("没有第 \(display) 块显示器（共 \(displays.count) 块，见 xyzlcu displays）") }
        let did = displays[display - 1]
        target = .display(did); rect = CGDisplayBounds(did); cliArgs = ["-D", String(display)]
        extra["display"] = display
    }
    var method = "screencapturekit"
    var img: CGImage? = nil
    lastCaptureMethod = nil
    mark("resolved")
    if !forceCLI && screenTrusted(), let (i, _) = captureSCK(target, scale: s) { img = i; method = lastCaptureMethod ?? method }
    if img == nil {
        method = "screencapture"
        img = captureCLI(cliArgs, tmp: NSTemporaryDirectory() + "xyzlcu-raw-\(getpid()).png")
        if let i = img, s != 1 { img = scaled(i, s); method += "+scaled" }
    }
    mark("captured")
    guard let cg0 = img else { try fail("截图失败（多半是没有屏幕录制权限）", code: 2) }
    // 锁屏时截图全黑；没有屏幕录制权限时只能拍到桌面和菜单栏
    let pps0 = rect.width > 0 ? Double(cg0.width) / Double(rect.width) : 1
    var o: [String: Any] = ["pixelWidth": cg0.width, "pixelHeight": cg0.height,
         "originX": Int(rect.minX), "originY": Int(rect.minY), "pointWidth": Int(rect.width), "pointHeight": Int(rect.height),
         "pixelsPerPoint": pps0, "method": method, "screenLocked": screenLocked(),
         "note": "全局点坐标 x = originX + x_pixel / pixelsPerPoint，y = originY + y_pixel / pixelsPerPoint"]
    var cg = cg0
    var px: Pixels? = nil
    if diff {
        // 和这个目标上一次 --diff 的画面比：没变就不出图；变了只出变化区域的外框（坐标照样按上面的公式换算）
        let key = liveKeyOf(target).0 + "@\(s)"
        guard let cur = Pixels(cg0) else { try fail("截图差异：无法读取像素") }
        var d: [String: Any] = [:]
        if let prev = prevFrames[key], prev.px.w == cur.w, prev.px.h == cur.h {
            let r = diffRects(prev.px, cur)
            d["changedPercent"] = NSDecimalNumber(string: String(format: "%.1f", Double(r.changedTiles) / Double(max(1, r.totalTiles)) * 100))
            func pt(_ q: CGRect) -> [String: Any] {
                ["x": Double(rect.minX) + Double(q.minX) / pps0, "y": Double(rect.minY) + Double(q.minY) / pps0,
                 "w": Double(q.width) / pps0, "h": Double(q.height) / pps0]
            }
            d["changed"] = !r.rects.isEmpty
            d["rects"] = r.rects.map(pt)
            d["pixelRects"] = r.rects.map { ["x": Int($0.minX), "y": Int($0.minY), "w": Int($0.width), "h": Int($0.height)] }
            if let first = r.rects.first {
                let bb = r.rects.dropFirst().reduce(first) { $0.union($1) }
                if let c = cg0.cropping(to: bb) {
                    cg = c
                    let q = pt(bb)
                    o["originX"] = q["x"]; o["originY"] = q["y"]; o["pointWidth"] = q["w"]; o["pointHeight"] = q["h"]
                    o["pixelWidth"] = c.width; o["pixelHeight"] = c.height
                    d["crop"] = ["x": Int(bb.minX), "y": Int(bb.minY), "w": Int(bb.width), "h": Int(bb.height)]
                }
            } else {
                o["pixelWidth"] = 0; o["pixelHeight"] = 0
            }
        } else {
            d["changed"] = true; d["baseline"] = true
            d["note"] = daemonMode ? "第一次（或尺寸变了）：返回整张图作为基准" : "不经过守护进程时没有上一张图可比，总是返回整张图（先 xyzlcu serve）"
            px = cur
        }
        if daemonMode {
            prevFrames[key] = PrevFrame(cur)
            if prevFrames.count > 4, let old = prevFrames.min(by: { $0.value.used < $1.value.used }) { prevFrames[old.key] = nil }
        }
        o["diff"] = d
        mark("diffed")
        if d["changed"] as? Bool == false {
            if timing { mark("total"); o["timingMs"] = marks }
            if toStdout {
                let meta = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                if outBuf != nil { binOut = nil; binMeta = meta } else { FileHandle.standardError.write((meta + "\n").data(using: .utf8)!) }
                return
            }
            out(o); return
        }
    }
    guard let data = encodeImage(cg, format: format, quality: quality, pixels: px) else {
        try fail("图像编码失败（\(format.rawValue)）", code: 2)
    }
    mark("encoded")
    if let path = path {
        do { try data.write(to: URL(fileURLWithPath: path)) } catch { try fail("写不了文件 \(path): \(error.localizedDescription)") }
        mark("written")
    }
    if sckTimedOut {
        o["warning"] = "ScreenCaptureKit 没有响应，已改用 screencapture（较慢）。守护进程在运行时用 XYZLCU_DAEMON=0 截图会这样，去掉它走守护进程即可"
    }
    o.merge(extra) { a, _ in a }
    o["format"] = format.rawValue; o["bytes"] = data.count
    if let path = path { o["path"] = path }
    if timing { mark("total"); o["timingMs"] = marks }
    if toStdout {
        let meta = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // 输出被收集时（守护进程 / MCP）随回复带回，否则直接写标准输出
        if outBuf != nil { binOut = data; binMeta = meta } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardError.write((meta + "\n").data(using: .utf8)!)
        }
        return
    }
    if base64 { o["base64"] = data.base64EncodedString() }
    out(o)
}

// MARK: - 主命令
let usage = """
xyzlcu — XYZ Local Computer Use：macOS 图形界面控制
  check [--probe] | request | whoami
  screenshot [path] [--scale 0.5] [--display N] [--format png|jpg|heic] [--quality 0.7] [--fast] [--cli]
             [--window "App" [--title 标题]] [--region x,y,w,h]      （--fast = jpg、质量 0.6、缩放 0.5，给智能体用最快）
             [--base64 | --stdout] [--out path] [--timing]   --base64/--stdout 在内存里出图（默认 jpg），不写文件
             [--diff]  只返回和上一次 --diff 截图相比变了的区域（没变就不出图；需要守护进程）
  click x y [--right] [--double] | move x y | drag x1 y1 x2 y2 | scroll dx dy
  type "文字" [--app "App"] [--window 标题] [--via auto|ax|events|pid|paste]   （输出 JSON，path = 实际走的路）
  key cmd+shift+4 [--app "App"] [--via auto|events|menu|pid]    （auto：事件流卡住时改按对应菜单项 / 直接投递给进程）
  insert "App" "文字" | settext "App" [--role R] [--title T|--id I] [--window 窗口] "文字" | value "App" [...]
                        （辅助功能直接写值，不经过键盘事件；--via paste = 剪贴板 + 菜单「粘贴」，会恢复剪贴板）
  menu "App" "文件>存储" [--window 标题] [--activate]   按菜单项（AXPress，按 pid，默认不激活应用；每级可写 文件|File）
  record [--out f.jsonl] [--duration 60] [--no-moves]   只监听地录制键鼠（不拦截输入，Ctrl-C 结束）
  replay f.jsonl [--speed 2] [--no-keys] [--force]       回放录制（事件流卡住时默认拒绝）
  apps | open "App" | activate "App" | hide "App" | windows [--all]
  displays | movewin "App" x y [--w W --h H] [--title 标题]
  ax ["App"] [--depth N] [--menu] | press "App" "按钮标题"
  find "App" [--role AXButton] [--title 保存] [--contains] [--index N|--all] [--window 标题] [--menu]
  click-el "App" --role AXButton --title 保存 [--click] [--right] [--double]
  wait "App" --title X [--role R] [--timeout 5] [--gone]   |   wait 毫秒 | sleep 毫秒
  cursor | version | taps（诊断输入卡顿） | check（权限 + 各输入路径健康状态）
  batch [--continue-on-error] [脚本文件]  （从 stdin 或文件逐行读取命令，一次启动执行多步）
  run [--continue-on-error] 'click 10 20; type 你好; key return'
  serve [--background | --status | --stop]  常驻守护进程（~/.xyzlcu/sock），之后的命令自动转发给它，更快
                             （已经在运行时直接返回 0；--background 在后台启动并等它就绪）
  mcp                        以 stdio MCP 服务器运行（给只支持 MCP 的客户端，如 Claude Desktop）
  通用选项: --delay N  事件间隔毫秒（默认 2，也可用环境变量 XYZLCU_DELAY）
  环境变量: XYZLCU_DAEMON=0 不用守护进程；=1 必须用守护进程
            XYZLCU_EVENTS_HEALTH=bad 模拟事件流卡住（测试备用路径）；XYZLCU_TAP_THRESHOLD_MS 卡住阈值（默认 1000）
            XYZLCU_PREWARM=0 守护进程启动时不预开主屏截图流；XYZLCU_PREWARM_SCALES 预开哪些缩放（默认 1,0.5）
            XYZLCU_PREWARM_IDLE 预开的流闲置多少秒关闭（默认 600）
            XYZLCU_STREAM=0 不用常驻截图流；XYZLCU_STREAM_IDLE 闲置多少秒关闭（默认 20）
            XYZLCU_PNG=imageio 用系统 PNG 编码器；XYZLCU_PNG_LEVEL 压缩级别 1–9（默认 1）
            XYZLCU_CONNECT_WAIT_MS 守护进程正在启动时最多等多久（默认 3000）；XYZLCU_CORE 客户端调用的主程序路径
"""
let version = "0.5.0"
var inBatch = false
let startedAt = Date()

func execute(_ argv: [String]) throws {
args = argv
if let d = option("--delay") { stepDelay = Int(try dbl(d)) }
guard !args.isEmpty else { return }
let cmd = args.removeFirst()

switch cmd {
case "help", "-h", "--help": emit(usage)
case "version", "--version", "-v": emit("xyzlcu \(version)")
case "check":
    forceProbe = flag("--probe")
    cachedHealth = nil  // check 总是重新检测
    let h = inputHealth(), ax = axTrusted()
    forceProbe = false
    var o: [String: Any] = ["accessibility": ax, "screenRecording": CGPreflightScreenCaptureAccess(), "screenLocked": screenLocked(), "binary": pathOf(getpid()),
         "inputMonitoring": CGPreflightListenEventAccess(), "version": version,
         "responsibleProcess": responsiblePid(getpid()).map { pathOf($0) } ?? "unknown", "daemon": daemonMode,
         "keyboardBlockedBy": h.keyboardBlockedBy, "tapThresholdMs": tapThresholdMs()]
    o["paths"] = [
        "events": ["healthy": h.keyboardOK, "probeMs": h.keyboardProbeMs.map { $0.isFinite ? ($0 * 10).rounded() / 10 : -2 } as Any,
                   "desc": "CGEvent 发到系统 HID 事件流（会经过所有主动拦截的事件监听）"],
        "mouse": ["healthy": h.mouseOK, "blockedBy": h.mouseBlockedBy, "probeMs": h.mouseProbeMs.map { $0.isFinite ? ($0 * 10).rounded() / 10 : -2 } as Any],
        "ax": ["available": ax, "desc": "辅助功能直接写值 / 按按钮（insert、settext、press、type --via ax），不经过事件流"],
        "menu": ["available": ax, "desc": "按 pid 读菜单栏并 AXPress 菜单项，不激活应用（menu、key --via menu）"],
        "pid": ["available": ax, "desc": "CGEventPostToPid 直接投递到应用进程（type/key --via pid、--app）"],
        "paste": ["available": ax, "desc": "剪贴板 + 菜单「编辑>粘贴」，用后恢复剪贴板（--via paste）"],
        "record": ["available": CGPreflightListenEventAccess() || ax, "desc": "只监听的事件监听，不会挡住输入"],
    ] as [String: Any]
    o["typeOrder"] = h.keyboardOK ? ["ax（标准文本框）", "events"] : ["ax", "pid", "paste"]
    o["keyOrder"] = h.keyboardOK ? ["events"] : ["menu", "pid"]
    if let ov = h.override { o["healthOverride"] = ov }
    if !h.staleBlockers.isEmpty { o["staleTapStats"] = h.staleBlockers; o["note"] = "这些监听的延迟统计偏高，但实测事件能正常走完（统计是历史值），按健康处理" }
    out(o)
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
    out(["chain": chain, "responsiblePid": r.map { Int($0) } ?? -1, "responsiblePath": r.map { pathOf($0) } ?? "unknown", "daemon": daemonMode])
case "screenshot":
    let fast = flag("--fast")
    let scale = try option("--scale").map(dbl) ?? (fast ? 0.5 : nil)
    let display = Int(option("--display") ?? "1") ?? 1
    let fmtOpt = try option("--format").map(ImgFormat.parse)
    let quality = try option("--quality").map(dbl) ?? (fast ? 0.6 : 0.7)
    let forceCLI = flag("--cli")
    let winApp = option("--window"), winTitle = option("--title")
    var region: CGRect? = nil
    if let r = option("--region") {
        let v = try r.split(separator: ",").map { try dbl(String($0).trimmingCharacters(in: .whitespaces)) }
        guard v.count == 4, v[2] > 0, v[3] > 0 else { try fail("--region 格式: x,y,w,h（全局点坐标）") }
        region = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }
    // --base64：图像放进 JSON；--stdout：原始字节写到标准输出（元数据到标准错误）。两者都不落盘，除非另给路径
    let b64 = flag("--base64"), toStdout = flag("--stdout"), timing = flag("--timing"), diff = flag("--diff")
    let given = option("--out") ?? args.first
    if let g = given, g.hasPrefix("--") { try fail("未知选项: \(g)") }
    // 格式：--format > 文件扩展名 > --fast / 内存出图用 jpg > png（无损，多线程编码）
    let format = fmtOpt ?? given.flatMap(ImgFormat.fromPath) ?? ((fast || ((b64 || toStdout) && given == nil)) ? .jpeg : .png)
    let path = given ?? ((b64 || toStdout) ? nil : NSTemporaryDirectory() + "xyzlcu-\(Int(Date().timeIntervalSince1970 * 1000)).\(format.ext)")
    try screenshot(path: path, scale: scale, display: display, region: region, window: winApp.map { ($0, winTitle) },
                   format: format, quality: quality, forceCLI: forceCLI, base64: b64, toStdout: toStdout, timing: timing, diff: diff)
case "click":
    try guardUnlocked(); let right = flag("--right"), double = flag("--double")
    try need(2, "click x y [--right] [--double]")
    click(CGPoint(x: try dbl(args[0]), y: try dbl(args[1])), right: right, double: double); emit("ok")
case "move":
    try guardUnlocked()
    try need(2, "move x y")
    let p = CGPoint(x: try dbl(args[0]), y: try dbl(args[1]))
    CGWarpMouseCursorPosition(p); CGAssociateMouseAndMouseCursorPosition(1)
    mouse(.mouseMoved, p); emit("ok")
case "drag":
    try guardUnlocked()
    try need(4, "drag x1 y1 x2 y2")
    let a = CGPoint(x: try dbl(args[0]), y: try dbl(args[1])), b = CGPoint(x: try dbl(args[2]), y: try dbl(args[3]))
    let dd = max(stepDelay, 8)  // 拖拽需要一点时间让应用识别
    mouse(.mouseMoved, a); sleepMs(dd); mouse(.leftMouseDown, a); sleepMs(dd)
    for i in 1...12 { let t = CGFloat(i) / 12; mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)); sleepMs(dd) }
    mouse(.leftMouseUp, b); emit("ok")
case "scroll":
    try guardUnlocked()
    try need(2, "scroll dx dy  （正 dy 向上滚，单位：行）")
    post(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(try dbl(args[1])), wheel2: Int32(try dbl(args[0])), wheel3: 0)); emit("ok")
case "type", "key":
    try guardUnlocked()
    // --app "App"：目标应用（默认前台应用）。--via 选路，默认 auto：按事件流健康状态自动选择并逐条回退，输出 JSON 里的 path 是实际走的路
    let appOpt = option("--app")
    if cmd == "type" {
        let via = (option("--via") ?? envv("XYZLCU_TYPE_VIA") ?? "auto").lowercased()
        let win = option("--window")
        try need(1, "type \"文字\" [--app App] [--window 窗口标题] [--via auto|ax|events|pid|paste]")
        out(try typeChain(appOpt, args.joined(separator: " "), via: via, window: win))
    } else {
        let via = (option("--via") ?? envv("XYZLCU_KEY_VIA") ?? "auto").lowercased()
        try need(1, "key cmd+shift+4 [--app App] [--via auto|events|menu|pid]")
        out(try keyChain(appOpt, args, via: via))
    }
case "insert", "settext":
    // insert：在焦点处插入（写 AXSelectedText）；settext：整体替换（写 AXValue）。都不经过键盘事件
    try guardUnlocked()
    let replaceAll = cmd == "settext"
    let via = (option("--via") ?? "auto").lowercased()
    guard ["auto", "ax", "paste"].contains(via) else { try fail("--via 只能是 auto、ax、paste") }
    let role = option("--role"), subrole = option("--subrole"), title = option("--title") ?? option("--id"), win = option("--window")
    let idx = Int(try option("--index").map(dbl) ?? 1)
    try need(2, "\(cmd) \"App\" [--role R] [--title T|--id I] [--window 窗口标题] [--via auto|ax|paste] \"文字\"")
    let t0 = Date()
    let appName = args[0], text = args.dropFirst().joined(separator: " ")
    let (el, app) = try inputTarget(appName, role: role, subrole: subrole, title: title, window: win, index: idx)
    var r = try writeText(appName, el, text, replaceAll: replaceAll, via: via)
    r["app"] = app.localizedName ?? ""; r["role"] = str(el, kAXRoleAttribute) ?? ""; r["window"] = windowTitle(of: el) ?? ""
    r["ms"] = Int(Date().timeIntervalSince(t0) * 1000)
    out(r)
    if (r["verified"] as? Bool) != true { try fail("写入后读回的内容和预期不一致（verified=false），请用 xyzlcu value 检查", code: 1) }
case "value":
    // 读回元素的值（默认焦点元素），用来核对 insert / settext / type 的结果
    let role = option("--role"), subrole = option("--subrole"), title = option("--title") ?? option("--id"), win = option("--window")
    let idx = Int(try option("--index").map(dbl) ?? 1)
    try need(1, "value \"App\" [--role R] [--title T|--id I] [--window 窗口标题]")
    let (el, app) = try inputTarget(args[0], role: role, subrole: subrole, title: title, window: win, index: idx)
    var o: [String: Any] = ["app": app.localizedName ?? "", "role": str(el, kAXRoleAttribute) ?? "", "window": windowTitle(of: el) ?? ""]
    if let v = attr(el, kAXValueAttribute) { o["value"] = (v as? String) ?? (v as? NSNumber)?.stringValue ?? "\(v)" }
    if let s = attr(el, kAXSelectedTextAttribute) as? String { o["selectedText"] = s }
    out(o)
case "menu":
    // 按菜单路径按下菜单项（AXPress），代替 cmd+s / cmd+w 等快捷键；每级可写多个候选：编辑|Edit>粘贴|Paste
    try guardUnlocked()
    let winOpt = option("--window")
    let doActivate = flag("--activate")
    try need(2, "menu \"App\" \"文件>存储\" [--window 窗口标题] [--activate]   （每级可写 文件|File）")
    let t0 = Date()
    let wasActive = findApp(args[0])?.isActive ?? false
    var activated = false
    if doActivate && !wasActive, let a = findApp(args[0]) {
        a.activate()
        // isActive 靠 KVO 更新，需要跑 run loop 才会刷新；以前台应用的 pid 为准
        for _ in 0..<20 where NSWorkspace.shared.frontmostApplication?.processIdentifier != a.processIdentifier {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        activated = NSWorkspace.shared.frontmostApplication?.processIdentifier == a.processIdentifier
    }
    var mainWin: String? = nil
    if let w = winOpt { mainWin = try setMainWindow(args[0], w) }
    let path = parseMenuPath(args.dropFirst().joined(separator: " "))
    guard !path.isEmpty else { try fail("菜单路径为空，例如 \"文件>存储\" 或 \"File>Save\"") }
    let picked = try pressMenu(args[0], path)
    var o: [String: Any] = ["app": findApp(args[0])?.localizedName ?? args[0], "pressed": picked.joined(separator: ">"), "ms": Int(Date().timeIntervalSince(t0) * 1000),
                            "path": "ax-menu", "activated": activated, "appWasActive": wasActive]
    if let w = mainWin { o["window"] = w }
    if lastMenuWasDisabled {
        o["note"] = (wasActive || activated) ? "按下前该菜单项显示为不可用（可能是旧状态），请确认效果"
            : "按下前该菜单项显示为不可用：应用在后台时，作用于文稿/输入焦点的菜单项（全选、粗体等）通常不会生效，应用级菜单项（新建、打开等）照常可用；需要时加 --activate"
    }
    let h = inputHealth()
    if !h.keyboardOK { o["warning"] = "检测到卡住的事件监听（\(h.blockerNames.joined(separator: ", "))），请确认菜单动作的效果" }
    out(o)
case "cursor":
    let p = CGEvent(source: nil)?.location ?? .zero; out(["x": Int(p.x), "y": Int(p.y)])
case "sleep":
    try need(1, "sleep 毫秒"); sleepMs(Int(try dbl(args[0]))); emit("ok")
case "wait":
    // wait 500 —— 纯等待；wait "App" --title X —— 等元素出现（或 --gone 消失）
    if args.count == 1, let ms = Double(args[0]) { sleepMs(Int(ms)); emit("ok"); break }
    let timeout = try option("--timeout").map(dbl) ?? 5
    let gone = flag("--gone")
    try need(1, "wait \"App\" --title X [--role R] [--timeout 5] [--gone]  或  wait 毫秒")
    let q = try parseQuery()
    let t0 = Date(); var interval = 0.02
    while true {
        if findApp(args[0]) != nil {
            let r = try axFind(args[0], q)
            if gone ? r.matches.isEmpty : !r.matches.isEmpty {
                if gone { out(["gone": true, "waitedMs": Int(Date().timeIntervalSince(t0) * 1000)]) }
                else { findOutput(r, all: q.all, t0: t0, extra: ["waitedMs": Int(Date().timeIntervalSince(t0) * 1000)]) }
                break
            }
        } else if gone { out(["gone": true, "waitedMs": Int(Date().timeIntervalSince(t0) * 1000)]); break }
        if Date().timeIntervalSince(t0) >= timeout { try fail("等待超时（\(timeout) 秒）", code: 4) }
        if daemonMode { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: interval)) } else { usleep(useconds_t(interval * 1_000_000)) }
        interval = min(interval * 1.5, 0.25)
    }
case "find":
    let t0 = Date()
    let q = try parseQuery()
    let r = try axFind(args.first, q)
    if r.matches.isEmpty { try fail("找不到元素（搜索了 \(r.visited) 个节点）", code: 4) }
    findOutput(r, all: q.all, t0: t0)
case "click-el":
    let t0 = Date()
    try guardUnlocked()
    let forceClick = flag("--click"), right = flag("--right"), double = flag("--double")
    var q = try parseQuery(); q.all = false
    let r = try axFind(args.first, q)
    guard let el = r.els.first else { try fail("找不到元素（搜索了 \(r.visited) 个节点）", code: 4) }
    var how = "AXPress"
    if forceClick || right || double || AXUIElementPerformAction(el, kAXPressAction as CFString) != .success {
        guard let c = r.matches[0]["center"] as? [String: Int] else { try fail("元素没有位置信息，无法点击") }
        click(CGPoint(x: c["x"]!, y: c["y"]!), right: right, double: double); how = "click"
    }
    findOutput(r, all: false, t0: t0, extra: ["action": how])
case "apps":
    drainRunLoop()
    out(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(appInfo))
case "open":
    try need(1, "open \"App\"")
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", args[0]]
    try? p.run(); p.waitUntilExit()
    if p.terminationStatus != 0 { try fail("打开失败: \(args[0])") }; emit("ok")
case "activate":
    try need(1, "activate \"App\"")
    guard let a = findApp(args[0]) else { try fail("没在运行: \(args[0])，可先 xyzlcu open") }
    a.unhide(); a.activate(options: [.activateAllWindows]); emit("ok")
case "hide":
    try need(1, "hide \"App\"")
    guard let a = findApp(args[0]) else { try fail("没在运行: \(args[0])") }
    a.hide(); emit("ok")
case "displays":
    out(activeDisplays().enumerated().map { (i, d) -> [String: Any] in
        let b = CGDisplayBounds(d)
        return ["index": i + 1, "id": Int(d), "main": d == CGMainDisplayID(), "x": Int(b.origin.x), "y": Int(b.origin.y),
                "w": Int(b.width), "h": Int(b.height), "pixelWidth": CGDisplayCopyDisplayMode(d)?.pixelWidth ?? 0, "pixelHeight": CGDisplayCopyDisplayMode(d)?.pixelHeight ?? 0]
    })
case "movewin":
    let wOpt = try option("--w").map(dbl), hOpt = try option("--h").map(dbl), titleOpt = option("--title")
    try need(3, "movewin \"App\" x y [--w W --h H] [--title 窗口标题]")
    let (root, app) = try axRoot(args[0])
    var win: AXUIElement? = nil
    if let t = titleOpt {
        win = ((attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first { (str($0, kAXTitleAttribute) ?? "").localizedCaseInsensitiveContains(t) }
    } else {
        win = (attr(root, kAXFocusedWindowAttribute) as! AXUIElement?) ?? (attr(root, kAXMainWindowAttribute) as! AXUIElement?)
            ?? ((attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []).first
    }
    guard let w = win else { try fail("找不到 \(app.localizedName ?? args[0]) 的窗口") }
    var pt = CGPoint(x: try dbl(args[1]), y: try dbl(args[2]))
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
    let (root, app) = try axRoot(args.first)
    emit("# \(app.localizedName ?? "?") pid=\(app.processIdentifier)")
    let win = (attr(root, kAXFocusedWindowAttribute) as! AXUIElement?) ?? (attr(root, kAXMainWindowAttribute) as! AXUIElement?)
    var n = 0
    if let w = win { dump(w, depth: 0, max: depth, count: &n) } else { dump(root, depth: 0, max: depth, count: &n) }
    if let mb = attr(root, kAXMenuBarAttribute), withMenu { dump(mb as! AXUIElement, depth: 0, max: 3, count: &n) }
case "press":
    try need(2, "press \"App\" \"按钮标题\"")
    try guardUnlocked()
    let (root, _) = try axRoot(args[0])
    guard let el = findElement(root, args[1]) else { try fail("找不到元素: \(args[1])") }
    let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
    if r != .success {
        if let f = frame(el) { click(CGPoint(x: f["x"]! + f["w"]! / 2, y: f["y"]! + f["h"]! / 2), right: false, double: false); emit("ok (AXPress 失败，已改为点击中心)") }
        else { try fail("AXPress 失败: \(r.rawValue)") }
    } else { emit("ok") }
case "taps":
    // 诊断：列出系统里的事件监听（event tap）。主动拦截型（listenOnly=false）且延迟很高的 tap 会让键盘/鼠标输入卡住或丢失
    var n: UInt32 = 0; CGGetEventTapList(0, nil, &n)
    var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(n)); CGGetEventTapList(n, &list, &n)
    out(list.prefix(Int(n)).map { t -> [String: Any] in
        var buf = [CChar](repeating: 0, count: 4096); proc_pidpath(t.tappingProcess, &buf, 4096)
        return ["process": String(cString: buf), "pid": Int(t.tappingProcess), "enabled": t.enabled,
                "listenOnly": t.options == .listenOnly, "eventsMask": String(t.eventsOfInterest, radix: 16),
                "avgLatencyMs": Double(t.avgUsecLatency) / 1000, "maxLatencyMs": Double(t.maxUsecLatency) / 1000,
                "blocking": t.enabled && t.options != .listenOnly && Double(t.avgUsecLatency) / 1000 > tapThresholdMs()]
    })
case "record":
    // 只监听地录制键鼠事件到 JSON Lines 文件。不拦截、不修改输入；锁屏或安全输入（密码框）时不记录按键
    if screenLocked() { try fail("屏幕已锁定，拒绝录制", code: 3) }
    let outPath = option("--out") ?? args.first ?? (NSHomeDirectory() + "/.xyzlcu/recordings/rec-\(Int(Date().timeIntervalSince1970)).jsonl")
    let dur = try option("--duration").map(dbl) ?? 60
    let moves = !flag("--no-moves")
    try recordSession(outPath: outPath, duration: max(0.5, dur), moves: moves)
case "replay":
    try guardUnlocked()
    let speed = try option("--speed").map(dbl) ?? 1
    let force = flag("--force"), noKeys = flag("--no-keys")
    try need(1, "replay 录制文件.jsonl [--speed 2] [--no-keys] [--force]")
    try replaySession(path: args[0], speed: speed, force: force, noKeys: noKeys)
case "__status":
    out(["running": daemonMode, "pid": Int(getpid()), "version": version, "uptimeSec": Int(Date().timeIntervalSince(startedAt)),
         "socket": socketPath(), "accessibility": axTrusted(), "screenRecording": CGPreflightScreenCaptureAccess(), "screenLocked": screenLocked(),
         "responsibleProcess": responsiblePid(getpid()).map { pathOf($0) } ?? "unknown",
         "liveStreams": liveStreams.keys.sorted(), "streamsEnabled": streamsEnabled, "prewarm": prewarmKeys.sorted(),
         "diffBaselines": prevFrames.keys.sorted(), "protocol": 2])
case "batch", "run":
    try fail("batch/run 不能嵌套")
case "serve":
    try fail("serve 只能作为单独的命令运行")
default:
    try fail("未知命令: \(cmd)（xyzlcu help 查看用法）")
}
if outBuf == nil { fflush(stdout) }
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

/// batch/run 的选项：--delay N、--continue-on-error，剩下的是脚本文件（batch）或脚本文本（run）
func batchOptions(_ rest: [String]) throws -> (rest: [String], delay: Int?, coe: Bool) {
    var r = rest, d: Int? = nil, coe = false
    if let i = r.firstIndex(of: "--continue-on-error") { coe = true; r.remove(at: i) }
    if let i = r.firstIndex(of: "--delay"), i + 1 < r.count { d = Int(try dbl(r[i + 1])); r.removeSubrange(i...i+1) }
    return (r, d, coe)
}

/// 执行一次完整的命令行（单条命令或 batch/run），返回退出码。CLI 和守护进程共用
/// 会改变界面的命令执行完记一下时间：之后的截图若取常驻流的帧，会等到这之后的新帧
let readOnlyCommands: Set<String> = ["help", "-h", "--help", "version", "--version", "-v", "check", "whoami", "screenshot", "value", "cursor",
                                     "sleep", "wait", "find", "apps", "displays", "windows", "ax", "taps", "__status", "serve"]
func markIfMutating(_ argv: [String]) { if let c = argv.first, !readOnlyCommands.contains(c) { lastInputAt = Date() } }
func runMain(_ top: [String], stdinText: () -> String, err: (String) -> Void) -> Int32 {
    if top.isEmpty { emit(usage); return 0 }
    do {
        if top[0] == "batch" || top[0] == "run" {
            inBatch = true; defer { inBatch = false }
            let (rest, d, coe) = try batchOptions(Array(top.dropFirst()))
            if let d = d { stepDelay = d }
            let text: String
            if top[0] == "run" { text = rest.joined(separator: " ") }
            else if let f = rest.first { guard let t = try? String(contentsOfFile: f, encoding: .utf8) else { try fail("读不到脚本: \(f)") }; text = t }
            else { text = stdinText() }
            var worst: Int32 = 0
            for (n, c) in parseScript(text).enumerated() {
                defer { markIfMutating(c) }
                do { try execute(c) } catch let e as XErr {
                    err("error: 第 \(n + 1) 步（\(c.joined(separator: " "))）: \(e.msg)")
                    if !coe { return e.code }
                    worst = e.code
                }
            }
            return worst
        }
        defer { markIfMutating(top) }
        try execute(top); return 0
    } catch let e as XErr { err("error: " + e.msg); return e.code }
    catch { err("error: \(error)"); return 1 }
}

// MARK: - 守护进程（Unix socket，只允许当前用户连接）
// 协议：客户端发一个 JSON 请求（v、proto、argv、cwd、env、delay、stdin），写完关闭写端。
// proto 2 的回复是二进制帧，图像字节不用 base64：
//   "XYZ2" | int32 退出码 | u32 长度 + 标准输出 | u32 长度 + 标准错误 | u32 长度 + 二进制（--stdout 的图像），整数都是大端。
// 版本不一致时总是回 JSON {"code":98}（旧客户端也看得懂），客户端改为自己执行。
// 启动锁：~/.xyzlcu/sock.lock 上的 fcntl 写锁，守护进程从启动到退出一直持有。客户端连不上时看一眼这把锁：
// 有人持有 = 守护进程正在启动，等它（最多 XYZLCU_CONNECT_WAIT_MS，默认 3000）；没人持有 = 没有守护进程，立刻自己执行。
func socketPath() -> String {
    ProcessInfo.processInfo.environment["XYZLCU_SOCKET"] ?? (NSHomeDirectory() + "/.xyzlcu/sock")
}
func makeAddr(_ path: String) -> sockaddr_un? {
    var a = sockaddr_un(); a.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: a.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &a.sun_path) { buf in for (i, b) in bytes.enumerated() { buf[i] = b }; buf[bytes.count] = 0 }
    return a
}
func connectDaemon(_ path: String) -> Int32? {
    guard var a = makeAddr(path) else { return nil }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0); if fd < 0 { return nil }
    let r = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    if r != 0 { close(fd); return nil }
    var one: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    return fd
}
/// 持有启动锁的进程 pid（没有就是 nil）
func lockHolder(_ path: String) -> pid_t? {
    let fd = open(path + ".lock", O_RDONLY); if fd < 0 { return nil }
    defer { close(fd) }
    var fl = flock(); fl.l_type = Int16(F_WRLCK); fl.l_whence = Int16(SEEK_SET)
    guard fcntl(fd, F_GETLK, &fl) == 0, fl.l_type != Int16(F_UNLCK) else { return nil }
    return fl.l_pid
}
/// 连守护进程；它正在启动时等它
func connectDaemonWaiting(_ path: String, waitMs: Int? = nil) -> Int32? {
    if let fd = connectDaemon(path) { return fd }
    guard lockHolder(path) != nil else { return nil }
    let ms = waitMs ?? Int(ProcessInfo.processInfo.environment["XYZLCU_CONNECT_WAIT_MS"] ?? "") ?? 3000
    let deadline = Date(timeIntervalSinceNow: Double(ms) / 1000)
    while Date() < deadline {
        usleep(5000)
        if let fd = connectDaemon(path) { return fd }
        if lockHolder(path) == nil { return nil }   // 启动失败退出了
    }
    return nil
}
func peerPid(_ fd: Int32) -> pid_t? {
    var pid: pid_t = 0; var len = socklen_t(MemoryLayout<pid_t>.size)
    return getsockopt(fd, 0 /* SOL_LOCAL */, 0x002 /* LOCAL_PEERPID */, &pid, &len) == 0 && pid > 0 ? pid : nil
}
func writeAll(_ fd: Int32, _ d: Data) -> Bool {
    d.withUnsafeBytes { p -> Bool in
        var off = 0
        while off < d.count { let n = write(fd, p.baseAddress! + off, d.count - off); if n <= 0 { return false }; off += n }
        return true
    }
}
func readAll(_ fd: Int32) -> Data {
    var d = Data(); var buf = [UInt8](repeating: 0, count: 1 << 18)
    while true { let n = read(fd, &buf, buf.count); if n <= 0 { break }; d.append(buf, count: n) }
    return d
}
struct RunResult { var code: Int32; var out: String; var err: String; var bin: Data? }
func encodeFrame(_ r: RunResult) -> Data {
    let o = Data(r.out.utf8), e = Data(r.err.utf8), b = r.bin ?? Data()
    var d = Data(capacity: 20 + o.count + e.count + b.count)
    d.append(contentsOf: Array("XYZ2".utf8))
    func u32(_ v: UInt32) { d.append(contentsOf: [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]) }
    u32(UInt32(bitPattern: r.code))
    u32(UInt32(o.count)); d.append(o); u32(UInt32(e.count)); d.append(e); u32(UInt32(b.count)); d.append(b)
    return d
}
func decodeFrame(_ d: Data) -> RunResult? {
    let a = [UInt8](d)
    guard a.count >= 20, a[0] == 0x58, a[1] == 0x59, a[2] == 0x5A, a[3] == 0x32 else { return nil }
    var i = 4
    func u32() -> Int? { guard i + 4 <= a.count else { return nil }; defer { i += 4 }; return Int(a[i]) << 24 | Int(a[i+1]) << 16 | Int(a[i+2]) << 8 | Int(a[i+3]) }
    func bytes() -> Data? { guard let n = u32(), i + n <= a.count else { return nil }; defer { i += n }; return Data(a[i..<(i+n)]) }
    guard let c = u32(), let o = bytes(), let e = bytes(), let b = bytes() else { return nil }
    return RunResult(code: Int32(bitPattern: UInt32(c)), out: String(decoding: o, as: UTF8.self), err: String(decoding: e, as: UTF8.self), bin: b.isEmpty ? nil : b)
}
/// 发一条请求给守护进程。nil = 守护进程不在或版本不一致（调用方改为自己执行）
func daemonRequest(_ argv: [String], stdin: String? = nil, wait: Bool = true) -> RunResult? {
    guard let fd = wait ? connectDaemonWaiting(socketPath()) : connectDaemon(socketPath()) else { return nil }
    defer { close(fd) }
    var req: [String: Any] = ["v": version, "proto": 2, "argv": argv, "cwd": FileManager.default.currentDirectoryPath]
    if let d = ProcessInfo.processInfo.environment["XYZLCU_DELAY"], let n = Int(d) { req["delay"] = n }
    var env: [String: String] = [:]
    for k in forwardedEnv { if let v = ProcessInfo.processInfo.environment[k] { env[k] = v } }
    req["env"] = env
    if let s = stdin { req["stdin"] = s }
    guard let body = try? JSONSerialization.data(withJSONObject: req), writeAll(fd, body) else { return nil }
    shutdown(fd, SHUT_WR)
    let resp = readAll(fd)
    if let r = decodeFrame(resp) { return r }
    // JSON 回复：版本不一致（98）或者旧版本守护进程
    if let j = try? JSONSerialization.jsonObject(with: resp) as? [String: Any], let code = j["code"] as? Int, code != 98 {
        return RunResult(code: Int32(code), out: j["out"] as? String ?? "", err: j["err"] as? String ?? "",
                         bin: (j["bin"] as? String).flatMap { Data(base64Encoded: $0) })
    }
    if resp.isEmpty { return RunResult(code: 1, out: "", err: "error: 守护进程没有回复（可能在执行中退出了）\n", bin: nil) }
    return nil
}
/// 客户端：把整条命令转发给守护进程。守护进程不在或版本不一致时返回 nil（改为进程内执行）
func forward(_ top: [String]) -> Int32? {
    var stdin: String? = nil
    if top.first == "batch", let bo = try? batchOptions(Array(top.dropFirst())), bo.rest.isEmpty {
        // 先确认守护进程在，再读标准输入（不在的话标准输入要留给进程内执行）
        guard let fd = connectDaemonWaiting(socketPath()) else { return nil }
        close(fd)
        stdin = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    guard let r = daemonRequest(top, stdin: stdin) else { return nil }
    if !r.out.isEmpty { FileHandle.standardOutput.write(Data(r.out.utf8)) }
    if let b = r.bin { FileHandle.standardOutput.write(b) }
    if !r.err.isEmpty { FileHandle.standardError.write(Data(r.err.utf8)) }
    return r.code
}
/// 在本进程里执行并收集输出（守护进程处理请求、MCP 自己执行时用）
func runCaptured(_ argv: [String], stdin: String = "") -> RunResult {
    let savedOut = outBuf
    outBuf = ""; var errText = ""; binOut = nil; binMeta = nil
    let code = runMain(argv, stdinText: { stdin }, err: { errText += $0 + "\n" })
    if let m = binMeta { errText = m + "\n" + errText }
    let r = RunResult(code: code, out: outBuf ?? "", err: errText, bin: binOut)
    outBuf = savedOut; binOut = nil; binMeta = nil
    return r
}
func handle(_ data: Data) -> (Data, Bool) {
    func json(_ o: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{\"code\":1}".utf8) }
    guard let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let argv = req["argv"] as? [String] else {
        return (json(["code": 1, "out": "", "err": "bad request"]), false)
    }
    let proto = req["proto"] as? Int ?? 1
    // __stop 不看版本：升级后用新版本也能停掉旧的守护进程
    if argv.first == "__stop" {
        let r = RunResult(code: 0, out: "ok\n", err: "", bin: nil)
        return (proto >= 2 ? encodeFrame(r) : json(["code": 0, "out": "ok\n", "err": ""]), true)
    }
    if req["v"] as? String != version { return (json(["code": 98, "err": "version mismatch", "version": version]), false) }
    if let cwd = req["cwd"] as? String { FileManager.default.changeCurrentDirectoryPath(cwd) }
    let saved = stepDelay
    if let d = req["delay"] as? Int { stepDelay = d }
    envOverlay = req["env"] as? [String: String] ?? [:]
    let r = runCaptured(argv, stdin: req["stdin"] as? String ?? "")
    stepDelay = saved
    if proto >= 2 { return (encodeFrame(r), false) }
    var resp: [String: Any] = ["code": Int(r.code), "out": r.out, "err": r.err]
    if let b = r.bin { resp["bin"] = b.base64EncodedString() }
    return (json(resp), false)
}
var lockFd: Int32 = -1
func serve() throws -> Never {
    let path = socketPath()
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    chmod(dir, 0o700)
    // 启动锁：同一时间只有一个守护进程；拿不到锁说明已经有一个在运行或正在启动，等它好了直接返回（幂等）
    lockFd = open(path + ".lock", O_CREAT | O_RDWR, 0o600)
    guard lockFd >= 0 else { try fail("打不开锁文件: \(path).lock") }
    var fl = flock(); fl.l_type = Int16(F_WRLCK); fl.l_whence = Int16(SEEK_SET)
    if fcntl(lockFd, F_SETLK, &fl) != 0 {
        let holder = lockHolder(path)
        let up = connectDaemonWaiting(path, waitMs: 5000).map { close($0); return true } ?? false
        FileHandle.standardError.write("守护进程已经在运行\(holder.map { "（pid \($0)）" } ?? "")\(up ? "" : "，但还没有开始接受连接")：\(path)\n".data(using: .utf8)!)
        exit(up ? 0 : 1)
    }
    // 拿到锁了。socket 还能连上，说明是不用锁文件的旧版本守护进程
    if let fd = connectDaemon(path) {
        close(fd); try fail("有一个旧版本的守护进程在运行（\(path)），先执行 xyzlcu serve --stop")
    }
    unlink(path)   // 没有活着的守护进程，留下的 socket 文件是旧的
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0, var a = makeAddr(path) else { try fail("无法创建 socket: \(path)") }
    let old = umask(0o077)
    let r = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    umask(old)
    guard r == 0 else { try fail("bind 失败: \(String(cString: strerror(errno)))") }
    chmod(path, 0o600)
    guard listen(fd, 64) == 0 else { try fail("listen 失败") }
    ftruncate(lockFd, 0); let pidLine = "\(getpid())\n"; _ = pidLine.withCString { write(lockFd, $0, strlen($0)) }
    daemonMode = true
    // 客户端提前断开（比如只是探测守护进程在不在）时，写回复会触发 SIGPIPE，不忽略的话守护进程会直接退出
    signal(SIGPIPE, SIG_IGN)
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler { unlink(path); exit(0) }
        src.resume(); signalSources.append(src)
    }
    let me = getuid()
    FileHandle.standardError.write("xyzlcu \(version) 守护进程已启动 pid=\(getpid()) socket=\(path) accessibility=\(axTrusted()) screenRecording=\(screenTrusted())\n".data(using: .utf8)!)
    Thread {
        while true {
            let c = accept(fd, nil, nil); if c < 0 { continue }
            var one: Int32 = 1; setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var uid: uid_t = 0, gid: gid_t = 0
            // 只接受同一用户的连接
            if getpeereid(c, &uid, &gid) != 0 || uid != me { close(c); continue }
            let body = readAll(c)
            if body.isEmpty { close(c); continue }   // 只是连上看看守护进程在不在
            var reply = Data(); var stop = false
            DispatchQueue.main.sync { (reply, stop) = handle(body) }
            _ = writeAll(c, reply); close(c)
            if stop { unlink(path); exit(0) }
        }
    }.start()
    // 预热（在主运行循环里做，不耽误接受连接）：权限检查、屏幕内容列表、主屏常驻流
    DispatchQueue.main.async {
        if #available(macOS 14.0, *), screenTrusted() { _ = shareableContent(maxAge: 0) }
        prewarmMainDisplay()
    }
    RunLoop.main.run()
    exit(0)
}
var signalSources: [DispatchSourceSignal] = []
/// serve --background：在新会话里启动守护进程（不随终端 / 工具调用结束而退出），等它能接受连接再返回
func serveBackground() -> Int32 {
    let path = socketPath()
    if let fd = connectDaemonWaiting(path) { close(fd); FileHandle.standardError.write("守护进程已经在运行：\(path)\n".data(using: .utf8)!); return 0 }
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let log = dir + "/serve.log"
    var attr: posix_spawnattr_t? = nil; posix_spawnattr_init(&attr); defer { posix_spawnattr_destroy(&attr) }
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var fa: posix_spawn_file_actions_t? = nil; posix_spawn_file_actions_init(&fa); defer { posix_spawn_file_actions_destroy(&fa) }
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&fa, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o600)
    posix_spawn_file_actions_adddup2(&fa, 1, 2)
    var env = ProcessInfo.processInfo.environment; env["XYZLCU_DAEMON"] = "0"
    let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
    let argv = [strdup(exe), strdup("serve"), nil]
    defer { for p in envp { free(p) }; for p in argv { free(p) } }
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, exe, &fa, &attr, argv, envp)
    guard rc == 0 else { FileHandle.standardError.write("启动失败: \(String(cString: strerror(rc)))\n".data(using: .utf8)!); return 1 }
    let deadline = Date(timeIntervalSinceNow: 8)
    while Date() < deadline {
        if let fd = connectDaemon(path) { close(fd); out(["running": true, "pid": Int(lockHolder(path) ?? pid), "socket": path, "log": log]); return 0 }
        var st: Int32 = 0
        if waitpid(pid, &st, WNOHANG) == pid { break }   // 退出了（比如已经有一个在运行）
        usleep(10000)
    }
    if let fd = connectDaemon(path) { close(fd); out(["running": true, "socket": path, "log": log]); return 0 }
    FileHandle.standardError.write("守护进程没有启动起来，见 \(log)\n".data(using: .utf8)!)
    return 1
}
/// serve --stop：新版本直接停；版本不一致的旧守护进程（不认 __stop）按 socket 对端 pid 发 SIGTERM
func stopDaemon() -> Int32 {
    let path = socketPath()
    guard let fd = connectDaemonWaiting(path) else { FileHandle.standardError.write("守护进程没有运行\n".data(using: .utf8)!); return 1 }
    let pid = peerPid(fd)
    let req: [String: Any] = ["v": version, "proto": 2, "argv": ["__stop"]]
    if let body = try? JSONSerialization.data(withJSONObject: req) { _ = writeAll(fd, body) }
    shutdown(fd, SHUT_WR)
    let resp = readAll(fd); close(fd)
    if let r = decodeFrame(resp), r.code == 0 { print("ok"); return 0 }
    if let p = pid, (pathOf(p) as NSString).lastPathComponent.hasPrefix("xyzlcu") {
        kill(p, SIGTERM)
        for _ in 0..<100 { if kill(p, 0) != 0 { break }; usleep(20000) }
        print("ok（停掉了旧版本的守护进程 pid \(p)）"); return 0
    }
    FileHandle.standardError.write("停不掉：守护进程没有正常回复\n".data(using: .utf8)!)
    return 1
}

// MARK: - MCP 服务器（stdio，给只支持 MCP 的客户端用；工具调用直接发给守护进程，没有守护进程就在本进程里执行，不起子进程）
/// 执行一条 xyzlcu 命令并拿回输出：守护进程在就直接发给它（不起新进程），不在就在本进程里执行
var mcpUseDaemon = true
func mcpRunSelf(_ argv: [String]) -> RunResult {
    if mcpUseDaemon, ProcessInfo.processInfo.environment["XYZLCU_DAEMON"] != "0", let r = daemonRequest(argv) { return r }
    return runCaptured(argv)
}

func mcpTools() -> [[String: Any]] {
    func t(_ name: String, _ desc: String, _ props: [String: Any] = [:], _ req: [String] = [], readOnly: Bool = false) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": props]
        if !req.isEmpty { schema["required"] = req }
        return ["name": name, "description": desc, "inputSchema": schema,
                "annotations": ["readOnlyHint": readOnly, "destructiveHint": false]]
    }
    let s: [String: Any] = ["type": "string"], n: [String: Any] = ["type": "number"], b: [String: Any] = ["type": "boolean"]
    return [
        t("check", "Permissions, screen lock and input-path health. Call first; stop if screenLocked is true or permissions are missing.", readOnly: true),
        t("screenshot", "Screenshot returned as a JPEG image (in memory, no file). Whole display (default scale 0.5), one app window (window, optional title), or a region \"x,y,w,h\" in global points. The text part has originX/originY/pixelsPerPoint: global point = origin + pixel / pixelsPerPoint. diff=true compares with the previous diff screenshot of the same target: returns no image if nothing changed, otherwise only the changed area (origin adjusted, diff.rects in global points).",
          ["window": s, "title": s, "region": s, "display": n, "scale": n, "quality": n, "diff": b], readOnly: true),
        t("apps", "Running GUI apps; the one with active=true is frontmost.", readOnly: true),
        t("windows", "On-screen windows with owner, title and bounds (global points).", readOnly: true),
        t("cursor", "Current pointer position.", readOnly: true),
        t("ax", "Dump an app's accessibility tree: role title value [x,y wxh] per line.", ["app": s, "depth": n], ["app"], readOnly: true),
        t("find", "Find a control by role/title; returns frame and center (global points).",
          ["app": s, "role": s, "title": s, "contains": b, "window": s], ["app"], readOnly: true),
        t("click_element", "Find a control and press it (AXPress, falling back to clicking its center).",
          ["app": s, "role": s, "title": s, "window": s], ["app"]),
        t("click", "Click at global point coordinates (moves the real pointer).", ["x": n, "y": n, "right": b, "double": b], ["x", "y"]),
        t("type_text", "Type Unicode text into the focused element. Pass app and window so it refuses to type anywhere else.",
          ["text": s, "app": s, "window": s], ["text"]),
        t("key", "Press keys or combos, e.g. [\"cmd+s\"] or [\"return\"].", ["keys": ["type": "array", "items": s], "app": s], ["keys"]),
        t("activate", "Bring an app to the front.", ["app": s], ["app"]),
        t("batch", "Run several xyzlcu commands in one call, e.g. [\"click 100 200\", \"wait-change --timeout 2\", \"screenshot --fast\"]. Each step is a command line (same syntax as `xyzlcu run`). Screenshot steps return images (JPEG, half scale for whole displays unless --scale is given). Stops at the first failing step unless continue_on_error.",
          ["steps": ["type": "array", "items": s], "continue_on_error": b], ["steps"]),
        t("xyzlcu", "Run any other xyzlcu command with raw arguments, e.g. [\"wait\",\"TextEdit\",\"--role\",\"AXSheet\",\"--timeout\",\"3\"] or [\"run\",\"click-el TextEdit --title Save; key return\"]. See `xyzlcu help`.",
          ["args": ["type": "array", "items": s]], ["args"]),
    ]
}

/// --stdout 截图的结果变成 MCP 内容：图像（只在这里 base64 一次）+ 元数据文本（标准错误第一行）
func mcpImageContent(_ r: RunResult) -> [[String: Any]] {
    var content: [[String: Any]] = []
    let lines = r.err.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    let meta = lines.first.map(String.init) ?? ""
    let mime = meta.contains("\"format\":\"png\"") ? "image/png" : meta.contains("\"format\":\"heic\"") ? "image/heic" : "image/jpeg"
    if let b = r.bin { content.append(["type": "image", "data": b.base64EncodedString(), "mimeType": mime]) }
    var t = meta
    if lines.count > 1, !lines[1].isEmpty { t += "\n" + lines[1] }
    if r.bin == nil, meta.contains("\"changed\":false") { t = "unchanged\n" + t }
    content.append(["type": "text", "text": t.isEmpty ? "ok" : t])
    return content
}
/// MCP batch：一次调用执行多条命令（比如 截图 + 点击 + 验证），省掉每一步一个来回
func mcpBatch(_ steps: [String], continueOnError: Bool) -> [String: Any] {
    let t0 = Date()
    var content: [[String: Any]] = []
    var failed = false, n = 0
    outer: for step in steps {
        for var argv in parseScript(step) {
            guard let f = argv.first else { continue }
            n += 1
            if ["mcp", "serve", "record", "replay", "batch", "run"].contains(f) {
                content.append(["type": "text", "text": "[\(n)] \(step)\n`\(f)` 不能放进 batch / not allowed in batch"]); failed = true
                if continueOnError { continue } else { break outer }
            }
            let isShot = f == "screenshot" && !argv.contains("--base64") && !argv.contains("--out")
                && !(argv.count > 1 && !argv[1].hasPrefix("--"))
            if isShot {
                argv.append("--stdout")
                if !argv.contains("--format") && !argv.contains("--fast") { argv += ["--format", "jpg"] }
                if !argv.contains("--scale") && !argv.contains("--window") && !argv.contains("--region") && !argv.contains("--fast") { argv += ["--scale", "0.5"] }
            }
            let ts = Date()
            let r = mcpRunSelf(argv)
            let ms = Int(Date().timeIntervalSince(ts) * 1000)
            if isShot && r.code == 0 {
                var c = mcpImageContent(r)
                if var last = c.popLast() { last["text"] = "[\(n)] \(step) (\(ms) ms)\n" + (last["text"] as? String ?? ""); c.append(last) }
                content += c
            } else {
                var s = r.out
                if !r.err.isEmpty { s += (s.isEmpty ? "" : "\n") + r.err }
                if r.code != 0 { s += "\nexit code \(r.code)" }
                content.append(["type": "text", "text": "[\(n)] \(argv.joined(separator: " ")) (\(ms) ms)\n" + (s.isEmpty ? "ok" : s)])
            }
            if r.code != 0 { failed = true; if !continueOnError { break outer } }
        }
    }
    content.append(["type": "text", "text": "batch: \(n) steps, \(failed ? "failed" : "ok"), \(Int(Date().timeIntervalSince(t0) * 1000)) ms"])
    return ["content": content, "isError": failed]
}
func mcpCall(_ name: String, _ a: [String: Any]) -> [String: Any] {
    func str(_ k: String) -> String? { if let v = a[k] as? String, !v.isEmpty { return v }; if let v = a[k] as? NSNumber { return v.stringValue }; return nil }
    func on(_ k: String) -> Bool { (a[k] as? Bool) ?? false }
    func text(_ s: String, _ isErr: Bool = false) -> [String: Any] { ["content": [["type": "text", "text": s]], "isError": isErr] }
    var argv: [String] = []
    switch name {
    case "check", "apps", "windows", "cursor": argv = [name]
    case "screenshot":
        argv = ["screenshot", "--stdout", "--format", "jpg", "--quality", str("quality") ?? "0.7"]
        if let w = str("window") { argv += ["--window", w]; if let t = str("title") { argv += ["--title", t] } }
        if let r = str("region") { argv += ["--region", r] }
        if let d = str("display") { argv += ["--display", d] }
        if on("diff") { argv.append("--diff") }
        argv += ["--scale", str("scale") ?? (str("window") != nil || str("region") != nil ? "1" : "0.5")]
        let r = mcpRunSelf(argv)
        guard r.code == 0 else { return text((r.err.isEmpty ? r.out : r.err) + "\nexit code \(r.code)", true) }
        return ["content": mcpImageContent(r), "isError": false]
    case "batch":
        return mcpBatch((a["steps"] as? [String]) ?? [], continueOnError: on("continue_on_error"))
    case "ax": argv = ["ax", str("app") ?? ""] + (str("depth").map { ["--depth", $0] } ?? [])
    case "find", "click_element":
        argv = [name == "find" ? "find" : "click-el", str("app") ?? ""]
        for k in ["role", "title", "window"] { if let v = str(k) { argv += ["--\(k)", v] } }
        if name == "find" && on("contains") { argv.append("--contains") }
    case "click":
        argv = ["click", str("x") ?? "", str("y") ?? ""]
        if on("right") { argv.append("--right") }; if on("double") { argv.append("--double") }
    case "type_text":
        argv = ["type"]
        if let v = str("app") { argv += ["--app", v] }; if let v = str("window") { argv += ["--window", v] }
        argv.append(str("text") ?? "")
    case "key":
        argv = ["key"] + ((a["keys"] as? [String]) ?? [])
        if let v = str("app") { argv += ["--app", v] }
    case "activate": argv = ["activate", str("app") ?? ""]
    case "xyzlcu":
        argv = (a["args"] as? [String]) ?? []
        if argv.contains("--stdout") { return text("--stdout 会破坏 MCP 输出，用 screenshot 工具 / use the screenshot tool", true) }
        if let f = argv.first, ["mcp", "serve", "record", "replay", "batch"].contains(f) {
            return text("`\(f)` 不能通过 MCP 运行 / not available over MCP", true)
        }
    default: return text("unknown tool: \(name)", true)
    }
    let r = mcpRunSelf(argv)
    var s = r.out
    if !r.err.isEmpty { s += (s.isEmpty ? "" : "\n") + r.err }
    if r.code != 0 { s += "\nexit code \(r.code)" }
    return text(s.isEmpty ? "ok" : s, r.code != 0)
}

func mcpServe() -> Never {
    func send(_ obj: [String: Any]) {
        guard var d = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        d.append(0x0A); FileHandle.standardOutput.write(d)
    }
    // MCP 服务器本身就是常驻进程：没有守护进程时它自己当守护进程用（缓存、常驻截图流都生效）
    if connectDaemon(socketPath()).map({ close($0); return true }) != true {
        daemonMode = true; envOverlay = ProcessInfo.processInfo.environment
    }
    func handleLine(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let msg = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]]); return
        }
        let method = msg["method"] as? String ?? ""
        guard let id = msg["id"] else { return }   // 通知（notifications/initialized 等）不回复
        let params = msg["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let want = params["protocolVersion"] as? String ?? ""
            let pv = ["2024-11-05", "2025-03-26", "2025-06-18"].contains(want) ? want : "2025-06-18"
            send(["jsonrpc": "2.0", "id": id, "result": [
                "protocolVersion": pv, "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "xyzlcu", "version": version],
                "instructions": "macOS GUI control. Call check first. Confirm the frontmost app (apps) before click/type/key. Prefer find/click_element over raw coordinates. Ask the user before irreversible actions; stop at captchas."]])
        case "ping": send(["jsonrpc": "2.0", "id": id, "result": [:]])
        case "tools/list": send(["jsonrpc": "2.0", "id": id, "result": ["tools": mcpTools()]])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            send(["jsonrpc": "2.0", "id": id, "result": mcpCall(name, params["arguments"] as? [String: Any] ?? [:])])
        default:
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found: \(method)"]])
        }
    }
    // 后台线程读标准输入，主线程执行（主 runloop 要转，ScreenCaptureKit 回调和定时器才会到）
    Thread {
        while let line = readLine(strippingNewline: true) { DispatchQueue.main.sync { handleLine(line) } }
        DispatchQueue.main.async { exit(0) }
    }.start()
    RunLoop.main.run()
    exit(0)
}

// MARK: - 入口
let top = Array(CommandLine.arguments.dropFirst())
let errOut: (String) -> Void = { FileHandle.standardError.write(($0 + "\n").data(using: .utf8)!) }
if top.first == "serve" {
    let rest = Array(top.dropFirst())
    if rest.contains("--stop") { exit(stopDaemon()) }
    if rest.contains("--status") {
        guard let r = daemonRequest(["__status"]) else { out(["running": false, "socket": socketPath()]); exit(0) }
        FileHandle.standardOutput.write(Data(r.out.utf8)); FileHandle.standardError.write(Data(r.err.utf8)); exit(r.code)
    }
    if rest.contains("--background") || rest.contains("-d") { exit(serveBackground()) }
    if let bad = rest.first { errOut("error: serve 不认识 \(bad)（可用 --background / --status / --stop）"); exit(1) }
    do { try serve() } catch let e as XErr { errOut("error: " + e.msg); exit(e.code) } catch { exit(1) }
}
if top.first == "mcp" { mcpServe() }
let daemonEnv = ProcessInfo.processInfo.environment["XYZLCU_DAEMON"]
// record / replay 运行时间长，总在当前进程里执行，不占用守护进程
if daemonEnv != "0", !top.isEmpty, !["help", "-h", "--help", "record", "replay"].contains(top[0]) {
    if let code = forward(top) { exit(code) }
    if daemonEnv == "1" { errOut("error: 守护进程没有运行（先执行 xyzlcu serve --background）"); exit(5) }
}
exit(runMain(top, stdinText: { String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? "" }, err: errOut))
