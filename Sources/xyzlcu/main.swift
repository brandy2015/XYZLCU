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
func screenTrusted() -> Bool { CGPreflightScreenCaptureAccess() }
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
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
func postKey(_ e: CGEvent?) { if let p = keyTargetPid { e?.postToPid(p) } else { e?.post(tap: .cghidEventTap) } }
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
func pressCombo(_ combo: String) throws {
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    var flags: CGEventFlags = []
    var key: CGKeyCode? = nil
    for p in parts {
        if let m = modMap[p] { flags.insert(m) }
        else if let k = keyMap[p] { key = k }
        else { try fail("未知按键: \(p)") }
    }
    guard let k = key else { try fail("组合键里没有主键: \(combo)") }
    let src = eventSource
    let d = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: true); d?.flags = flags; postKey(d)
    let u = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: false); u?.flags = flags; postKey(u)
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
/// 被键盘事件卡住的监听：主动拦截、已启用、关心 keyDown、平均延迟超过 1 秒
func blockingKeyboardTaps() -> [[String: Any]] {
    var n: UInt32 = 0; CGGetEventTapList(0, nil, &n)
    guard n > 0 else { return [] }
    var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(n)); CGGetEventTapList(n, &list, &n)
    return list.prefix(Int(n)).filter { t in
        t.enabled && t.options != .listenOnly && (t.eventsOfInterest & (1 << CGEventType.keyDown.rawValue)) != 0 && t.avgUsecLatency > 1_000_000
    }.map { t in ["process": pathOf(t.tappingProcess), "pid": Int(t.tappingProcess), "avgLatencyMs": Double(t.avgUsecLatency) / 1000] }
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
    defer { restorePasteboard(snap) }
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
            sleepMs(30)
        }
    } else { sleepMs(300) }
    return ["method": "paste-menu", "verified": verified, "length": (el.flatMap(axStringValue) ?? "").count, "clipboardRestored": true]
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
    // 菜单「粘贴」要靠应用处理事件队列；键盘事件流卡住时按了也不会生效，还可能排队到以后才执行，所以自动模式下不走这条路
    if via == "auto", !blockingKeyboardTaps().isEmpty {
        try fail("辅助功能写入不可用，且检测到卡住的键盘监听（xyzlcu taps），剪贴板 + 菜单粘贴也不会生效。如确实要试，加 --via paste", code: 4)
    }
    return try pasteWrite(appName, el, text, replaceAll: replaceAll)
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
/// SCShareableContent 取一次要几十毫秒；守护进程里缓存起来复用
var cachedContent: AnyObject? = nil
var cachedAt = Date.distantPast
@available(macOS 14.0, *)
func shareableContent(maxAge: Double) -> SCShareableContent? {
    if maxAge > 0, daemonMode, let c = cachedContent as? SCShareableContent, Date().timeIntervalSince(cachedAt) < maxAge { return c }
    let sem = DispatchSemaphore(value: 0)
    var result: SCShareableContent?
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, _ in result = c; sem.signal() }
    if sem.wait(timeout: .now() + 5) == .timedOut { return nil }
    if let r = result { cachedContent = r; cachedAt = Date() }
    return result
}
@available(macOS 14.0, *)
func grab(_ filter: SCContentFilter, _ cfg: SCStreamConfiguration) -> CGImage? {
    let sem = DispatchSemaphore(value: 0)
    var result: CGImage?
    SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { img, _ in result = img; sem.signal() }
    return sem.wait(timeout: .now() + 5) == .timedOut ? nil : result
}
enum Target { case display(CGDirectDisplayID), region(CGDirectDisplayID, CGRect), window(CGWindowID) }
/// 快路径：ScreenCaptureKit（macOS 14+），在进程内截图，直接按目标尺寸输出
func captureSCK(_ target: Target, scale: Double) -> (CGImage, CGRect)? {
    guard #available(macOS 14.0, *) else { return nil }
    for attempt in 0..<2 {
        var maxAge = 30.0
        if case .window = target { maxAge = 2 }  // 窗口大小/位置变化快，缓存时间短一些
        guard let content = shareableContent(maxAge: attempt == 1 ? 0 : maxAge) else { return nil }
        let cfg = SCStreamConfiguration()
        cfg.showsCursor = false
        cfg.captureResolution = .best
        switch target {
        case .display(let did), .region(let did, _):
            guard let d = content.displays.first(where: { $0.displayID == did }) else { continue }
            let b = CGDisplayBounds(did), pps = pixelsPerPoint(did)
            var rect = b
            if case .region(_, let r) = target {
                rect = r
                cfg.sourceRect = CGRect(x: r.minX - b.minX, y: r.minY - b.minY, width: r.width, height: r.height)
            }
            cfg.width = max(1, Int(rect.width * pps * scale)); cfg.height = max(1, Int(rect.height * pps * scale))
            if let img = grab(SCContentFilter(display: d, excludingWindows: []), cfg) { return (img, rect) }
            if attempt == 0 { continue }; return nil
        case .window(let wid):
            guard let w = content.windows.first(where: { $0.windowID == wid }) else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let r = filter.contentRect, pps = Double(filter.pointPixelScale)
            cfg.width = max(1, Int(r.width * pps * scale)); cfg.height = max(1, Int(r.height * pps * scale))
            if let img = grab(filter, cfg) { return (img, w.frame) }
            if attempt == 0 { continue }; return nil
        }
    }
    return nil
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
func screenshot(path: String, scale: Double?, display: Int, region: CGRect?, window: (String, String?)?, jpeg: Bool, quality: Double, forceCLI: Bool) throws {
    let displays = activeDisplays()
    let s = (scale ?? 1) > 0 ? (scale ?? 1) : 1
    var target: Target
    var cliArgs: [String]
    var rect: CGRect
    var extra: [String: Any] = [:]
    if let (app, title) = window {
        let (wid, r, t) = try appWindow(app, title: title)
        target = .window(wid); cliArgs = ["-o", "-l", String(wid)]; rect = r
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
    if !forceCLI && screenTrusted(), let (i, _) = captureSCK(target, scale: s) { img = i }
    if img == nil {
        method = "screencapture"
        img = captureCLI(cliArgs, tmp: NSTemporaryDirectory() + "xyzlcu-raw-\(getpid()).png")
        if let i = img, s != 1 { img = scaled(i, s); method += "+scaled" }
    }
    guard let cg = img, writeImage(cg, to: URL(fileURLWithPath: path), jpeg: jpeg, quality: quality) else {
        try fail("截图失败（多半是没有屏幕录制权限）", code: 2)
    }
    // 锁屏时截图全黑；没有屏幕录制权限时只能拍到桌面和菜单栏
    var o: [String: Any] = ["path": path, "pixelWidth": cg.width, "pixelHeight": cg.height,
         "originX": Int(rect.minX), "originY": Int(rect.minY), "pointWidth": Int(rect.width), "pointHeight": Int(rect.height),
         "pixelsPerPoint": rect.width > 0 ? Double(cg.width) / Double(rect.width) : 1, "method": method, "screenLocked": screenLocked(),
         "note": "全局点坐标 x = originX + x_pixel / pixelsPerPoint，y = originY + y_pixel / pixelsPerPoint"]
    o.merge(extra) { a, _ in a }
    out(o)
}

// MARK: - 主命令
let usage = """
xyzlcu — XYZ Local Computer Use：macOS 图形界面控制
  check | request | whoami
  screenshot [path] [--scale 0.5] [--display N] [--format png|jpg] [--quality 0.7] [--fast] [--cli]
             [--window "App" [--title 标题]] [--region x,y,w,h]      （--fast = jpg、质量 0.6、缩放 0.5）
  click x y [--right] [--double] | move x y | drag x1 y1 x2 y2 | scroll dx dy
  type "文字" [--via auto|events|ax|paste] | key cmd+shift+4   （都可加 --app "App"：直接投递给该应用）
  insert "App" "文字" | settext "App" [--role R] [--title T|--id I] [--window 窗口] "文字" | value "App" [...]
                        （辅助功能直接写值，不经过键盘事件；--via paste = 剪贴板 + 菜单「粘贴」，会恢复剪贴板）
  menu "App" "文件>存储"   按菜单路径按下菜单项（每级可写 文件|File），键盘被卡住时代替快捷键
  apps | open "App" | activate "App" | hide "App" | windows [--all]
  displays | movewin "App" x y [--w W --h H] [--title 标题]
  ax ["App"] [--depth N] [--menu] | press "App" "按钮标题"
  find "App" [--role AXButton] [--title 保存] [--contains] [--index N|--all] [--window 标题] [--menu]
  click-el "App" --role AXButton --title 保存 [--click] [--right] [--double]
  wait "App" --title X [--role R] [--timeout 5] [--gone]   |   wait 毫秒 | sleep 毫秒
  cursor | version | taps（诊断输入卡顿）
  batch [--continue-on-error] [脚本文件]  （从 stdin 或文件逐行读取命令，一次启动执行多步）
  run [--continue-on-error] 'click 10 20; type 你好; key return'
  serve [--status | --stop]  常驻守护进程（~/.xyzlcu/sock），之后的命令自动转发给它，更快
  通用选项: --delay N  事件间隔毫秒（默认 2，也可用环境变量 XYZLCU_DELAY）
  环境变量: XYZLCU_DAEMON=0 不用守护进程；=1 必须用守护进程
"""
let version = "0.3.1"
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
    out(["accessibility": axTrusted(), "screenRecording": screenTrusted(), "screenLocked": screenLocked(), "binary": pathOf(getpid()),
         "responsibleProcess": responsiblePid(getpid()).map { pathOf($0) } ?? "unknown", "daemon": daemonMode,
         "keyboardBlockedBy": blockingKeyboardTaps()])
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
    let fmtOpt = option("--format")?.lowercased()
    let quality = try option("--quality").map(dbl) ?? (fast ? 0.6 : 0.7)
    let forceCLI = flag("--cli")
    let winApp = option("--window"), winTitle = option("--title")
    var region: CGRect? = nil
    if let r = option("--region") {
        let v = try r.split(separator: ",").map { try dbl(String($0).trimmingCharacters(in: .whitespaces)) }
        guard v.count == 4, v[2] > 0, v[3] > 0 else { try fail("--region 格式: x,y,w,h（全局点坐标）") }
        region = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }
    let p0 = args.first?.lowercased() ?? ""
    let jpeg = fmtOpt.map { $0 == "jpg" || $0 == "jpeg" } ?? (p0.hasSuffix(".jpg") || p0.hasSuffix(".jpeg") || fast)
    let path = args.first ?? (NSTemporaryDirectory() + "xyzlcu-\(Int(Date().timeIntervalSince1970 * 1000)).\(jpeg ? "jpg" : "png")")
    try screenshot(path: path, scale: scale, display: display, region: region, window: winApp.map { ($0, winTitle) },
                   jpeg: jpeg, quality: quality, forceCLI: forceCLI)
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
    // --app "App"：直接投递给该应用进程，不经过系统 HID 事件流（应用必须已在前台，焦点在要输入的位置）
    let appOpt = option("--app")
    // --via events|ax|paste|auto：auto = 平时用键盘事件；检测到卡住的键盘监听时改用辅助功能写值（不行再剪贴板 + 菜单粘贴）
    let via = (option("--via") ?? ProcessInfo.processInfo.environment["XYZLCU_TYPE_VIA"] ?? "auto").lowercased()
    guard ["auto", "events", "ax", "paste"].contains(via) else { try fail("--via 只能是 auto、events、ax、paste") }
    if cmd == "type" {
        try need(1, "type \"文字\" [--app App] [--via auto|events|ax|paste]")
        let text = args.joined(separator: " ")
        var mode = via
        var blocked: [[String: Any]] = []
        if mode == "auto" { blocked = blockingKeyboardTaps(); mode = blocked.isEmpty ? "events" : "auto-ax" }
        if mode != "events" {
            let (root, app) = try axRoot(appOpt)
            let el = axElement(attr(root, kAXFocusedUIElementAttribute))
            if el == nil && mode != "paste" && mode != "auto-ax" { try fail("\(app.localizedName ?? "应用") 没有焦点元素，无法用辅助功能输入", code: 4) }
            var r = try writeText(appOpt ?? app.bundleIdentifier, el, text, replaceAll: false, via: mode == "auto-ax" ? "auto" : mode)
            if !blocked.isEmpty { r["reason"] = "检测到卡住的键盘监听: " + blocked.compactMap { ($0["process"] as? String)?.split(separator: "/").last.map(String.init) }.joined(separator: ", ") }
            emit("ok via=\(r["method"] ?? "?") verified=\(r["verified"] ?? false)\((r["reason"] as? String).map { "（\($0)）" } ?? "")")
            break
        }
    }
    if let a = appOpt {
        guard let app = findApp(a) else { try fail("找不到应用: \(a)") }
        keyTargetPid = app.processIdentifier
    }
    defer { keyTargetPid = nil }
    if cmd == "type" { typeText(args.joined(separator: " ")) }
    else { try need(1, "key cmd+shift+4 [--app App]（键盘被卡住时用 menu \"App\" \"文件>存储\" 代替快捷键）"); for (i, c) in args.enumerated() { if i > 0 { sleepMs(stepDelay) }; try pressCombo(c) } }
    emit("ok")
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
    try need(2, "menu \"App\" \"文件>存储\"   （每级可写 文件|File）")
    let t0 = Date()
    let path = parseMenuPath(args.dropFirst().joined(separator: " "))
    guard !path.isEmpty else { try fail("菜单路径为空，例如 \"文件>存储\" 或 \"File>Save\"") }
    let picked = try pressMenu(args[0], path)
    var o: [String: Any] = ["app": findApp(args[0])?.localizedName ?? args[0], "pressed": picked.joined(separator: ">"), "ms": Int(Date().timeIntervalSince(t0) * 1000)]
    if lastMenuWasDisabled { o["note"] = "按下前该菜单项显示为不可用（可能是旧状态），请确认效果" }
    let blocked = blockingKeyboardTaps()
    if !blocked.isEmpty { o["warning"] = "检测到卡住的键盘监听，应用可能处理不了菜单动作（会排队到事件流恢复后才执行）。请确认效果" }
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
    pumpRunLoop()
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
                "avgLatencyMs": Double(t.avgUsecLatency) / 1000, "maxLatencyMs": Double(t.maxUsecLatency) / 1000]
    })
case "__status":
    out(["running": daemonMode, "pid": Int(getpid()), "version": version, "uptimeSec": Int(Date().timeIntervalSince(startedAt)),
         "socket": socketPath(), "accessibility": axTrusted(), "screenRecording": screenTrusted(), "screenLocked": screenLocked(),
         "responsibleProcess": responsiblePid(getpid()).map { pathOf($0) } ?? "unknown"])
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
                do { try execute(c) } catch let e as XErr {
                    err("error: 第 \(n + 1) 步（\(c.joined(separator: " "))）: \(e.msg)")
                    if !coe { return e.code }
                    worst = e.code
                }
            }
            return worst
        }
        try execute(top); return 0
    } catch let e as XErr { err("error: " + e.msg); return e.code }
    catch { err("error: \(error)"); return 1 }
}

// MARK: - 守护进程（Unix socket，只允许当前用户连接）
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
func writeAll(_ fd: Int32, _ d: Data) -> Bool {
    d.withUnsafeBytes { p -> Bool in
        var off = 0
        while off < d.count { let n = write(fd, p.baseAddress! + off, d.count - off); if n <= 0 { return false }; off += n }
        return true
    }
}
func readAll(_ fd: Int32) -> Data {
    var d = Data(); var buf = [UInt8](repeating: 0, count: 65536)
    while true { let n = read(fd, &buf, buf.count); if n <= 0 { break }; d.append(buf, count: n) }
    return d
}
/// 客户端：把整条命令转发给守护进程。守护进程不在或版本不一致时返回 nil（改为进程内执行）
func forward(_ top: [String]) -> Int32? {
    guard let fd = connectDaemon(socketPath()) else { return nil }
    defer { close(fd) }
    var req: [String: Any] = ["v": version, "argv": top, "cwd": FileManager.default.currentDirectoryPath]
    if let d = ProcessInfo.processInfo.environment["XYZLCU_DELAY"], let n = Int(d) { req["delay"] = n }
    if top.first == "batch", let bo = try? batchOptions(Array(top.dropFirst())), bo.rest.isEmpty {
        req["stdin"] = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    guard let body = try? JSONSerialization.data(withJSONObject: req), writeAll(fd, body) else { return nil }
    shutdown(fd, SHUT_WR)
    guard let resp = try? JSONSerialization.jsonObject(with: readAll(fd)) as? [String: Any], let code = resp["code"] as? Int else { return nil }
    if code == 98 { return nil }  // 版本不一致
    if let o = resp["out"] as? String, !o.isEmpty { FileHandle.standardOutput.write(o.data(using: .utf8)!) }
    if let e = resp["err"] as? String, !e.isEmpty { FileHandle.standardError.write(e.data(using: .utf8)!) }
    return Int32(code)
}
func handle(_ data: Data) -> (Data, Bool) {
    var resp: [String: Any] = ["code": 1, "out": "", "err": ""]
    var stop = false
    if let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let argv = req["argv"] as? [String] {
        if req["v"] as? String != version { resp = ["code": 98, "err": "version mismatch"] }
        else if argv.first == "__stop" { resp = ["code": 0, "out": "ok\n", "err": ""]; stop = true }
        else {
            if let cwd = req["cwd"] as? String { FileManager.default.changeCurrentDirectoryPath(cwd) }
            let saved = stepDelay
            if let d = req["delay"] as? Int { stepDelay = d }
            outBuf = ""; var errText = ""
            let code = runMain(argv, stdinText: { req["stdin"] as? String ?? "" }, err: { errText += $0 + "\n" })
            resp = ["code": Int(code), "out": outBuf ?? "", "err": errText]
            outBuf = nil; stepDelay = saved
        }
    }
    return ((try? JSONSerialization.data(withJSONObject: resp)) ?? Data("{\"code\":1}".utf8), stop)
}
func serve() throws -> Never {
    let path = socketPath()
    if let fd = connectDaemon(path) { close(fd); try fail("守护进程已经在运行（\(path)），用 xyzlcu serve --stop 停止") }
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    chmod(dir, 0o700)
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0, var a = makeAddr(path) else { try fail("无法创建 socket: \(path)") }
    let old = umask(0o077)
    let r = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    umask(old)
    guard r == 0 else { try fail("bind 失败: \(String(cString: strerror(errno)))") }
    chmod(path, 0o600)
    guard listen(fd, 16) == 0 else { try fail("listen 失败") }
    daemonMode = true
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler { unlink(path); exit(0) }
        src.resume(); signalSources.append(src)
    }
    // 预热：权限检查、屏幕内容列表
    if #available(macOS 14.0, *), screenTrusted() { _ = shareableContent(maxAge: 0) }
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
            var reply = Data(); var stop = false
            DispatchQueue.main.sync { (reply, stop) = handle(body) }
            _ = writeAll(c, reply); close(c)
            if stop { unlink(path); exit(0) }
        }
    }.start()
    RunLoop.main.run()
    exit(0)
}
var signalSources: [DispatchSourceSignal] = []

// MARK: - 入口
let top = Array(CommandLine.arguments.dropFirst())
let errOut: (String) -> Void = { FileHandle.standardError.write(($0 + "\n").data(using: .utf8)!) }
if top.first == "serve" {
    let rest = Array(top.dropFirst())
    if rest.contains("--stop") || rest.contains("--status") {
        let isStop = rest.contains("--stop")
        guard let code = forward([isStop ? "__stop" : "__status"]) else {
            if isStop { errOut("守护进程没有运行"); exit(1) }
            out(["running": false, "socket": socketPath()]); exit(0)
        }
        exit(code)
    }
    do { try serve() } catch let e as XErr { errOut("error: " + e.msg); exit(e.code) } catch { exit(1) }
}
let daemonEnv = ProcessInfo.processInfo.environment["XYZLCU_DAEMON"]
if daemonEnv != "0", !top.isEmpty, !["help", "-h", "--help"].contains(top[0]) {
    if let code = forward(top) { exit(code) }
    if daemonEnv == "1" { errOut("error: 守护进程没有运行（先在智能体的终端里执行 xyzlcu serve &）"); exit(5) }
}
exit(runMain(top, stdinText: { String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? "" }, err: errOut))
