// Owned integration fixture. Never activates itself and never posts input events.
import AppKit

final class Fixture: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var fields: [NSTextField] = []
    var timer: Timer?
    var windowGeneration = 1
    var controlGeneration = 1
    var counter = 0
    var everFrontmost = false
    let runID = Bundle.main.object(forInfoDictionaryKey: "XYZLCUTestRunID") as! String
    let directory = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "XYZLCUTestDirectory") as! String)
    var lastCommand = ""

    func makeWindow(_ index: Int) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 120 + index * 60, y: 140 + index * 50, width: 420, height: 220),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "XYZLCU Identity Fixture \(index + 1) \(runID)"
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
        content.wantsLayer = true
        content.layer?.backgroundColor = (index == 0 ? NSColor.systemBlue : NSColor.systemOrange).cgColor
        let label = NSTextField(labelWithString: "Fixture nonce: \(runID)")
        label.frame = NSRect(x: 18, y: 155, width: 385, height: 36)
        content.addSubview(label)
        let field = NSTextField(string: "Owned fixture text")
        field.frame = NSRect(x: 18, y: 95, width: 385, height: 30)
        field.setAccessibilityIdentifier("xyzlcu-fixture-text-\(index)")
        content.addSubview(field)
        if fields.count > index { fields[index] = field } else { fields.append(field) }
        let button = NSButton(title: "Fixture counter", target: self, action: #selector(increment))
        button.frame = NSRect(x: 18, y: 28, width: 180, height: 36)
        button.setAccessibilityIdentifier("xyzlcu-fixture-counter-\(index)")
        content.addSubview(button)
        window.contentView = content
        window.orderFront(nil) // Does not activate or make the application frontmost.
        return window
    }
    @objc func increment() { counter += 1; publish() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        windows = [makeWindow(0), makeWindow(1)]
        publish()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.poll() }
    }
    func publish() {
        let state: [String: Any] = ["fixtureSchemaVersion": 1, "runID": runID, "pid": Int(getpid()),
            "bundleID": Bundle.main.bundleIdentifier!, "bundlePath": Bundle.main.bundleURL.path,
            "windowGeneration": windowGeneration, "controlGeneration": controlGeneration, "counter": counter,
            "windowIDs": windows.map { $0.windowNumber }, "titles": windows.map { $0.title },
            "text": fields.map { $0.stringValue }, "lastCommand": lastCommand,
            "everFrontmost": everFrontmost, "frontmostPID": NSWorkspace.shared.frontmostApplication.map { Int($0.processIdentifier) } ?? -1]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        }
    }
    func poll() {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid(), !everFrontmost {
            everFrontmost = true; publish()
        }
        let path = directory.appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf: path),
              let command = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              command["runID"] == runID, let id = command["id"], id != lastCommand else { return }
        lastCommand = id
        switch command["operation"] {
        case "replace-window":
            windows[0].close(); windows[0] = makeWindow(0); windowGeneration += 1; controlGeneration += 1
        case "replace-control":
            let previous = fields[0], replacement = NSTextField(string: previous.stringValue)
            replacement.frame = previous.frame
            replacement.setAccessibilityIdentifier("xyzlcu-fixture-text-0")
            previous.removeFromSuperview(); windows[0].contentView?.addSubview(replacement)
            fields[0] = replacement; controlGeneration += 1
        case "quit": publish(); NSApp.terminate(nil); return
        default: break
        }
        publish()
    }
}
let app = NSApplication.shared
let delegate = Fixture()
app.delegate = delegate
app.run()
