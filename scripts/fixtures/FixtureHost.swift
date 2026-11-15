// Test harness: background AppKit launch and passive desktop/TCC snapshots only.
import AppKit
import ApplicationServices

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "snapshot" {
    let frontmost = NSWorkspace.shared.frontmostApplication
    let pointer = NSEvent.mouseLocation
    emit(["frontmostPID": frontmost.map { Int($0.processIdentifier) } ?? -1,
          "pointerX": pointer.x, "pointerY": pointer.y,
          "accessibility": AXIsProcessTrusted(), "screenRecording": CGPreflightScreenCaptureAccess()])
} else if arguments.first == "launch", arguments.count == 2 {
    let url = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    guard let bundle = Bundle(url: url), bundle.bundleIdentifier == "com.xyztech.xyzlcu.identity-fixture",
          bundle.object(forInfoDictionaryKey: "XYZLCUTestRunID") is String else {
        fputs("refused: not an owned fixture bundle\n", stderr); exit(1)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.hides = false
    configuration.addsToRecentItems = false
    configuration.promptsUserIfNeeded = false
    configuration.arguments = []
    configuration.environment = [:]
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
        if let error = error { fputs("background fixture launch failed: \(error)\n", stderr); exit(1) }
        guard let app = app else { exit(1) }
        emit(["pid": Int(app.processIdentifier), "bundlePath": app.bundleURL?.path ?? "", "activated": false])
        exit(0)
    }
    RunLoop.main.run()
} else {
    fputs("usage: fixture-host snapshot | launch OWNED_FIXTURE_PATH\n", stderr); exit(1)
}
