// v0.8 identity metadata and deliberately gated native dispatchers.
// Generic macOS APIs do not establish window/element/surface incarnation.
import Foundation
import AppKit
import ApplicationServices
import Security
import CryptoKit
import ScreenCaptureKit
import CoreMedia
import CoreImage
import Darwin
#if SWIFT_PACKAGE
import IdentityProof
#endif

private func identityHash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func identityJSON(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
private func identityToken() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw IdentityFailure(code: "PROCESS_IDENTITY_UNAVAILABLE") }
    return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
private func identityCanonicalNonce(_ value: String) -> Bool {
    guard value.utf8.count == 43, value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
          let bytes = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="), bytes.count == 32 else { return false }
    return bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value
}
private func identityBoot() throws -> String {
    var size = 0
    guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1, size <= 128 else { throw IdentityFailure(code: "PROCESS_IDENTITY_UNAVAILABLE") }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0,
          let uuid = UUID(uuidString: String(cString: bytes)) else { throw IdentityFailure(code: "PROCESS_IDENTITY_UNAVAILABLE") }
    return uuid.uuidString.lowercased()
}
private func identityNow() -> UInt64 {
    var timebase = mach_timebase_info_data_t()
    guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return 0 }
    let value = mach_continuous_time(), quotient = value / UInt64(timebase.denom), remainder = value % UInt64(timebase.denom)
    let (whole, overflow) = quotient.multipliedReportingOverflow(by: UInt64(timebase.numer))
    let (result, overflow2) = whole.addingReportingOverflow(remainder * UInt64(timebase.numer) / UInt64(timebase.denom))
    return overflow || overflow2 ? 0 : result
}
func identityInstant() -> [String: Any] { ["continuous_ns": String(identityNow()), "wall_utc": ISO8601DateFormatter().string(from: Date())] }

struct NativeProcessIdentity {
    static func start(_ pid: pid_t) throws -> (UInt64, UInt64, UInt32) {
        guard pid > 0 else { throw IdentityFailure(code: "PROCESS_NOT_FOUND") }
        var info = proc_bsdinfo()
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard count == Int32(MemoryLayout<proc_bsdinfo>.size), info.pbi_pid == UInt32(pid), info.pbi_start_tvsec > 0, info.pbi_start_tvusec < 1_000_000 else {
            throw IdentityFailure(code: kill(pid, 0) != 0 ? "PROCESS_NOT_FOUND" : "PROCESS_IDENTITY_UNAVAILABLE")
        }
        return (info.pbi_start_tvsec, info.pbi_start_tvusec, info.pbi_uid)
    }
    static func executable(_ pid: pid_t) throws -> URL {
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { throw IdentityFailure(code: "PROCESS_IDENTITY_UNAVAILABLE") }
        return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL
    }
    static func file(_ url: URL) throws -> [String: Any] {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw IdentityFailure(code: "APP_IDENTITY_CHANGED") }
        defer { Darwin.close(fd) }
        var before = stat(), after = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size >= 0, before.st_size <= 512 * 1024 * 1024 else { throw IdentityFailure(code: "APP_IDENTITY_CHANGED") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var digest = SHA256(), length: Int64 = 0
        while true {
            let bytes = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if bytes.isEmpty { break }
            length += Int64(bytes.count)
            guard length <= before.st_size else { throw IdentityFailure(code: "APP_IDENTITY_CHANGED") }
            digest.update(data: bytes)
        }
        guard fstat(fd, &after) == 0, length == before.st_size, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec, before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw IdentityFailure(code: "APP_IDENTITY_CHANGED") }
        var pathname = stat()
        guard lstat(url.path, &pathname) == 0, pathname.st_dev == after.st_dev, pathname.st_ino == after.st_ino else { throw IdentityFailure(code: "APP_IDENTITY_CHANGED") }
        return ["device": String(UInt64(bitPattern: Int64(before.st_dev))), "inode": String(before.st_ino), "sha256": digest.finalize().map { String(format: "%02x", $0) }.joined()]
    }
    private static func matches(_ code: SecCode, _ requirement: String) -> Bool {
        var requirementRef: SecRequirement?
        return SecRequirementCreateWithString(requirement as CFString, [], &requirementRef) == errSecSuccess && requirementRef != nil && SecCodeCheckValidity(code, [], requirementRef) == errSecSuccess
    }
    static func signing(_ pid: pid_t, executable: URL) throws -> [String: Any] {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, [], &code) == errSecSuccess, let code = code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { throw IdentityFailure(code: "SIGNATURE_INVALID") }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode = staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { throw IdentityFailure(code: "SIGNATURE_INVALID") }
        var raw: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any], let identifier = info[kSecCodeInfoIdentifier as String] as? String, !identifier.isEmpty,
              let cdhash = info[kSecCodeInfoUnique as String] as? Data, !cdhash.isEmpty,
              let flags = info[kSecCodeInfoFlags as String] as? NSNumber,
              let main = info[kSecCodeInfoMainExecutable as String] as? URL,
              main.resolvingSymlinksInPath().standardizedFileURL == executable else { throw IdentityFailure(code: "SIGNATURE_UNPROVABLE") }
        var requirement: SecRequirement?, text: CFString?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement = requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text = text else { throw IdentityFailure(code: "SIGNATURE_UNPROVABLE") }
        let kind: String
        if flags.uint32Value & SecCodeSignatureFlags.adhoc.rawValue != 0 { kind = "adhoc_diagnostic" }
        else if matches(code, "anchor apple") { kind = "apple_platform" }
        else if matches(code, "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists") { kind = "developer_id" }
        else if matches(code, "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists") { kind = "app_store" }
        else { throw IdentityFailure(code: "SIGNATURE_UNPROVABLE") }
        var architectureInfo = proc_archinfo()
        guard proc_pidinfo(pid, PROC_PIDARCHINFO, 0, &architectureInfo, Int32(MemoryLayout<proc_archinfo>.size)) == Int32(MemoryLayout<proc_archinfo>.size) else { throw IdentityFailure(code: "SIGNATURE_UNPROVABLE") }
        let arch = architectureInfo.p_cputype
        let architecture: String
        if arch == CPU_TYPE_ARM64 { architecture = UInt32(bitPattern: architectureInfo.p_cpusubtype) & ~CPU_SUBTYPE_MASK == UInt32(CPU_SUBTYPE_ARM64E) ? "arm64e" : "arm64" } else if arch == CPU_TYPE_X86_64 { architecture = "x86_64" } else { throw IdentityFailure(code: "SIGNATURE_UNPROVABLE") }
        let algorithm = (info[kSecCodeInfoDigestAlgorithm as String] as? NSNumber)?.intValue
        let hashAlgorithm: String
        if algorithm == 1 { hashAlgorithm = "sha1" } else if algorithm == 2 { hashAlgorithm = cdhash.count == 20 ? "sha256_truncated" : "sha256" } else if algorithm == 3 { hashAlgorithm = "sha256_truncated" } else { throw IdentityFailure(code: "SIGNATURE_UNPROVABLE") }
        if ["developer_id", "app_store"].contains(kind), (info[kSecCodeInfoTeamIdentifier as String] as? String)?.isEmpty != false { throw IdentityFailure(code: "SIGNATURE_UNPROVABLE") }
        return ["kind": kind, "valid": true, "team_id": info[kSecCodeInfoTeamIdentifier as String] as? String as Any? ?? NSNull(),
                "signing_identifier": identifier, "cdhash": cdhash.map { String(format: "%02x", $0) }.joined(), "cdhash_algorithm": hashAlgorithm,
                "architecture": architecture, "designated_requirement": text as String, "requirement_sha256": identityHash(Data((text as String).utf8))]
    }
    static func observe(_ pid: pid_t) throws -> [String: Any] {
        let first = try start(pid), boot = try identityBoot()
        guard first.2 == geteuid() else { throw IdentityFailure(code: "PROCESS_UID_MISMATCH") }
        let executable = try executable(pid), executableFile = try file(executable), signature = try signing(pid, executable: executable)
        let running = NSRunningApplication(processIdentifier: pid)
        let bundleURL = running?.bundleURL?.resolvingSymlinksInPath().standardizedFileURL
        var bundleID: Any = NSNull(), bundlePath: Any = NSNull()
        if let url = bundleURL, let bundle = Bundle(url: url), let signedBundleID = bundle.bundleIdentifier {
            guard let osBundleID = running?.bundleIdentifier, osBundleID == signedBundleID,
                  let bundleExecutable = bundle.executableURL?.resolvingSymlinksInPath().standardizedFileURL, bundleExecutable == executable,
                  executable.path.hasPrefix(url.path + "/") else { throw IdentityFailure(code: "APP_IDENTITY_CHANGED") }
            var bundleStatic: SecStaticCode?
            guard SecStaticCodeCreateWithPath(url as CFURL, [], &bundleStatic) == errSecSuccess, let bundleStatic = bundleStatic,
                  SecStaticCodeCheckValidity(bundleStatic, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { throw IdentityFailure(code: "SIGNATURE_INVALID") }
            bundleID = osBundleID; bundlePath = url.path
        }
        let last = try start(pid)
        guard first.0 == last.0, first.1 == last.1, first.2 == last.2 else { throw IdentityFailure(code: "PID_REUSED", fields: ["process.start_time"]) }
        guard try self.executable(pid) == executable, try identityBoot() == boot else { throw IdentityFailure(code: "APP_IDENTITY_CHANGED") }
        return ["boot_id": boot, "pid": Int(pid), "uid": Int(first.2), "start_time": ["seconds": String(first.0), "microseconds": Int(first.1)],
                "app": ["bundle_id": bundleID, "bundle_path": bundlePath, "executable_path": executable.path, "executable_file": executableFile, "signing": signature]]
    }
}

func identityExecutor() throws -> [String: Any] {
    let pid = getpid(), start = try NativeProcessIdentity.start(pid), path = try NativeProcessIdentity.executable(pid)
    let (seconds, overflow) = start.0.multipliedReportingOverflow(by: 1_000_000)
    let (combined, overflow2) = seconds.addingReportingOverflow(start.1)
    guard !overflow && !overflow2 else { throw IdentityFailure(code: "PROCESS_IDENTITY_UNAVAILABLE") }
    return ["pid": Int(pid), "start_time": String(combined), "boot_id": try identityBoot(),
            "build_sha256": try NativeProcessIdentity.file(path)["sha256"]!, "execution_mode": daemonMode ? "daemon" : "direct", "client_build_sha256": NSNull()]
}
func identityEmit(_ object: Any) throws {
    let data = try identityJSON(object)
    guard data.count <= 8 * 1024 * 1024, let string = String(data: data, encoding: .utf8) else { throw IdentityFailure(code: "RESPONSE_TOO_LARGE") }
    inputResultEmitted = true
    emit(string)
}
private func identityFail(_ code: String, nonce: String? = nil, phase: String = "precheck", fields: [String] = []) throws -> Never {
    let failure = IdentityFailure(code: code, fields: fields, message: "Operation unavailable; required identity or authority cannot be established.")
    let response = ProofCoordinator.failure(failure, nonce: nonce.map(JSONValue.string) ?? .null, phase: phase)
    try identityEmit(try JSONSerialization.jsonObject(with: response.canonicalData()))
    throw XErr(msg: code, code: Int32(response["exit_code"]!.number!), policyCode: code)
}

func identityReadRequest(_ raw: String) throws -> JSONValue {
    guard let fd = Int32(raw), fd >= 3 else { throw IdentityFailure(code: "INVALID_REQUEST") }
    guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw IdentityFailure(code: "INVALID_REQUEST") }
    defer { Darwin.close(fd) }
    var output = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    let expires = Date().addingTimeInterval(2)
    while true {
        guard Date() < expires else { throw IdentityFailure(code: "INVALID_REQUEST") }
        var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&item, 1, 2000) > 0 else { throw IdentityFailure(code: "INVALID_REQUEST") }
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count == 0 { break }
        if count < 0 { if errno == EINTR { continue }; throw IdentityFailure(code: "INVALID_REQUEST") }
        output.append(contentsOf: buffer.prefix(count))
        guard output.count <= 256 * 1024 else { throw IdentityFailure(code: "REQUEST_TOO_LARGE") }
    }
    return try JSONValue.parse(output)
}
func identityArgumentOptions(_ argv: [String], values: Set<String>, flags: Set<String>) throws -> [String: String] {
    var result: [String: String] = [:], index = 1
    while index < argv.count {
        let arg = argv[index]
        guard result[arg] == nil else { throw IdentityFailure(code: "INVALID_REQUEST") }
        if flags.contains(arg) { result[arg] = "true"; index += 1 }
        else if values.contains(arg), index + 1 < argv.count, !argv[index + 1].hasPrefix("--") {
            result[arg] = argv[index + 1]; index += 2
        } else { throw IdentityFailure(code: "INVALID_REQUEST") }
    }
    return result
}
private func identitySameProcess(_ expected: JSONValue, _ observed: JSONValue) throws {
    guard let expectedObject = expected.object, let observedObject = observed.object,
          Set(expectedObject.keys) == Set(observedObject.keys) else { throw IdentityFailure(code: "INVALID_REQUEST") }
    if expected["pid"] != observed["pid"] { throw IdentityFailure(code: "PROCESS_IDENTITY_MISMATCH", fields: ["process.pid"]) }
    if expected["start_time"] != observed["start_time"] { throw IdentityFailure(code: "PID_REUSED", fields: ["process.start_time"]) }
    if expected["boot_id"] != observed["boot_id"] { throw IdentityFailure(code: "BOOT_MISMATCH", fields: ["process.boot_id"]) }
    guard expected == observed else { throw IdentityFailure(code: "APP_IDENTITY_CHANGED", fields: ["process.app"]) }
}

/// Hook before legacy command parsing; handles all structured/identity paths.
func handleIdentityCLI(_ argv: [String]) throws -> Bool {
    guard let command = argv.first else { return false }
    if argv.contains("--assurance") { return try handlePracticalCLI(argv) }
    let structured = argv.contains("--consumer") || argv.contains("--proof-protocol") || argv.contains("--request-fd") || argv.contains("--hmac-key-fd")
    let handles = ["capabilities", "identity-observe", "identity-check", "open-app", "bind-window"].contains(command)
        || (command == "windows" && (argv.contains("--thumbnails") || argv.contains("--show-all"))) || structured
    guard handles else { return false }
    var nonce: String?
    var failurePhase = "parse"
    do {
        if command == "capabilities" {
            _ = try identityArgumentOptions(argv, values: [], flags: ["--json"])
            try identityEmit(["schema_version": 1, "version": version, "executor": try identityExecutor(),
                              "proof_protocols": [1], "consumer_transports": [String](), "consumer_available": false,
                              "diagnostic_operations": ["identity-observe", "identity-check"],
                              "default_assurance": "strict",
                              "practical_window_capture": ["explicit_only": true, "available": practicalCaptureSupported() && CGPreflightScreenCaptureAccess(), "minimum_macos": "14.2", "command": "screenshot --assurance practical --request-fd N --output-dir DIR --json", "consumer_admission": false],
                              "tcc": ["accessibility": AXIsProcessTrusted(), "screen_recording": CGPreflightScreenCaptureAccess()],
                              "routes": ["sck-window-screenshot": ["available": false, "reason": "SURFACE_CLASSIFICATION_UNPROVABLE"],
                                         "ax-read": ["available": false, "reason": "AX_INSTANCE_UNPROVABLE"],
                                         "appkit-background-launch": ["available": false, "reason": "APP_TRUST_UNPROVABLE"]],
                              "assurance": ["process-instance"],
                              "limitations": ["No authenticated consumer admission/transport.", "No generic window, element, surface continuity or exact launch provider.", "Ad-hoc release is content-pinned diagnostic code, not publisher distribution trust."]])
            return true
        }
        if command == "identity-observe" || command == "identity-check" {
            let values: Set<String> = command == "identity-observe" ? ["--pid", "--nonce"] : ["--request-fd"]
            let options = try identityArgumentOptions(argv, values: values, flags: ["--json"])
            var expected: JSONValue?, pid: pid_t
            if command == "identity-check" {
                guard let raw = options["--request-fd"] else { throw IdentityFailure(code: "INVALID_REQUEST") }
                let request = try identityReadRequest(raw)
                guard let object = request.object, Set(object.keys) == ["schema_version", "nonce", "expected"], request["schema_version"] == (try JSONValue(any: 1)),
                      let suppliedNonce = request["nonce"]?.string, identityCanonicalNonce(suppliedNonce),
                      let suppliedExpected = request["expected"], let pidNumber = suppliedExpected["pid"]?.number,
                      pidNumber.isFinite, pidNumber.rounded(.towardZero) == pidNumber, pidNumber > 0, pidNumber <= Double(Int32.max) else { throw IdentityFailure(code: "INVALID_REQUEST") }
                nonce = suppliedNonce; expected = suppliedExpected; pid = Int32(pidNumber)
            } else {
                guard let raw = options["--pid"], let parsed = Int32(raw), parsed > 0 else { throw IdentityFailure(code: "INVALID_REQUEST") }
                pid = parsed
                if let supplied = options["--nonce"] { guard identityCanonicalNonce(supplied) else { throw IdentityFailure(code: "INVALID_REQUEST") }; nonce = supplied }
            }
            failurePhase = "precheck"
            let began = identityInstant(), pre = try NativeProcessIdentity.observe(pid), preJSON = try JSONValue(any: pre)
            if let expected = expected { try identitySameProcess(expected, preJSON) }
            failurePhase = "postcheck"
            let post = try NativeProcessIdentity.observe(pid), postJSON = try JSONValue(any: post)
            try identitySameProcess(preJSON, postJSON)
            if let expected = expected { try identitySameProcess(expected, postJSON) }
            try identityEmit(["schema_version": 1, "kind": "process-observation", "ok": true, "nonce": nonce as Any? ?? NSNull(),
                              "executor": try identityExecutor(), "observed_pre": pre, "observed_post": post, "identity_check": "matched", "assurance": ["process-instance"],
                              "timing": ["start": began, "end": identityInstant()],
                              "limitations": ["Diagnostic metadata only; not an identity-proof:1 content Success or consumer admission.", "PID-based Security lookup is bracketed, not atomic audit-token attestation.", "Ad-hoc identity is an executable content observation, not publisher trust."]])
            return true
        }
        if command == "windows" {
            let options = try identityArgumentOptions(argv, values: [], flags: ["--thumbnails", "--show-all", "--json"])
            try identityEmit(try identityCatalog(showAll: options["--show-all"] != nil))
            return true
        }
        // Every consumer path refuses before reading a sensitive envelope/key:
        // the legacy transport cannot authenticate either endpoint or owner role.
        if argv.contains("--consumer") { try identityFail("SESSION_INVALID", phase: "negotiate") }
        if command == "open-app" {
            let options = try identityArgumentOptions(argv, values: ["--bundle-id"], flags: ["--json"])
            guard let bundle = options["--bundle-id"], bundle.utf8.count <= 255,
                  bundle.range(of: "^[A-Za-z0-9][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*)+$", options: .regularExpression) != nil else { throw IdentityFailure(code: "INVALID_REQUEST") }
            try identityFail("APP_TRUST_UNPROVABLE")
        }
        if command == "bind-window" { try identityFail("IDENTITY_UNPROVABLE") }
        let options = try identityArgumentOptions(argv, values: ["--proof-protocol", "--request-fd"], flags: ["--json"])
        guard options["--proof-protocol"] == "1", let raw = options["--request-fd"] else { throw IdentityFailure(code: "INVALID_REQUEST") }
        let request = try identityReadRequest(raw)
        if let value = request["nonce"]?.string, identityCanonicalNonce(value) { nonce = value }
        try ProofSchema.validate(request, definition: "Request")
        guard request["operation"]?.string == command else { throw IdentityFailure(code: "INVALID_REQUEST") }
        try identityFail("IDENTITY_UNPROVABLE", nonce: nonce)
    } catch let failure as IdentityFailure {
        try identityFail(failure.code, nonce: nonce, phase: failurePhase, fields: failure.fields)
    } catch let refusal as XErr {
        throw refusal
    } catch {
        try identityFail("INTERNAL_ERROR", nonce: nonce, phase: failurePhase)
    }
}

private func identityCatalog(showAll: Bool) throws -> [String: Any] {
    // Discovery metadata cannot authorize content. Explicitly allow a builtin-only
    // diagnostic view before owner initialization; executable policy stays strict.
    let policy = try ProtectedAppPolicy.loadUserPolicy(requireInitialized: false)
    let rows = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    var candidates: [(Double, Int, UInt32, [String: Any])] = [], protectedCount = 0, filteredCount = 0, unavailableCount = 0
    for row in rows {
        guard let pid = row[kCGWindowOwnerPID as String] as? Int32, pid > 0,
              let number = row[kCGWindowNumber as String] as? UInt32, number > 0 else { unavailableCount += 1; continue }
        let app = NSRunningApplication(processIdentifier: pid), bundle = app?.bundleIdentifier ?? ""
        // No content/signature acquisition is necessary to conservatively redact
        // protected seeds; a missing signer never turns a seed into an allowance.
        let verdict = policy.evaluate(bundleID: bundle, teamID: nil, signingID: "", validSignature: false)
        let protected = ["protected", "suspicious_identity"].contains(verdict.classification)
        if protected && !showAll { protectedCount += 1; continue }
        let bounds = row[kCGWindowBounds as String] as? [String: Any]
        let rectangle = bounds.flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        let validFrame = rectangle.flatMap { frame -> CGRect? in
            guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return nil }
            return frame
        }
        let title = protected ? nil : row[kCGWindowName as String] as? String
        let layer = row[kCGWindowLayer as String] as? Int ?? 0
        let onscreen = row[kCGWindowIsOnscreen as String] as? Bool ?? false
        var reasons: [String] = []
        if layer != 0 { reasons.append("nonzero_layer") }
        if !onscreen { reasons.append("offscreen") }
        if let frame = validFrame { if frame.width < 120 || frame.height < 80 { reasons.append("too_small") } } else { reasons.append("unknown_geometry") }
        if title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { reasons.append("untitled") }
        if let opacity = row[kCGWindowAlpha as String] as? Double, opacity <= 0 { reasons.append("transparent") }
        if !showAll && !reasons.isEmpty { filteredCount += 1; continue }
        let frame: Any = protected ? NSNull() : validFrame.map { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height] as Any } ?? NSNull()
        let code = protected ? "PROTECTED_APP_REFUSED" : (CGPreflightScreenCaptureAccess() ? "SURFACE_CLASSIFICATION_UNPROVABLE" : "TCC_SCREEN_RECORDING_REQUIRED")
        let entry: [String: Any] = ["target_id": try identityToken(), "display_label": protected ? "Protected application" : String((app?.localizedName ?? "Application").prefix(512)),
                                    "title": title.map { String($0.prefix(4096)) } as Any? ?? NSNull(), "frame": frame, "filter_reasons": reasons,
                                    "identity": NSNull(), "selectable": false, "unavailable_code": code,
                                    "thumbnail_status": protected ? "refused" : "unavailable", "thumbnail": NSNull()]
        candidates.append((validFrame.map { $0.width * $0.height } ?? 0, Int(pid), number, entry))
    }
    candidates.sort { if $0.0 != $1.0 { return $0.0 > $1.0 }; if $0.1 != $1.1 { return $0.1 < $1.1 }; return $0.2 < $1.2 }
    unavailableCount += max(0, candidates.count - 20)
    return ["schema_version": 1, "catalog_revision": try identityToken(), "executor": try identityExecutor(), "generated_at": identityInstant(),
            "policy_sha256": policy.digest, "entries": candidates.prefix(20).map { $0.3 }, "next_cursor": NSNull(),
            "omitted_counts": ["protected": protectedCount, "filtered": filteredCount, "unavailable": unavailableCount]]
}

// Native dispatch service deliberately has no generic CLI admission. A reviewed
// adapter must supply exact retained SCWindow plus independently established
// window/surface continuity and run guards at both primitive boundaries.
// This service never falls back to display capture, old frames or screencapture.
struct GuardedSCKWindowCapture {
    let window: SCWindow
    let checkIdentityAndPermit: () throws -> Void
    let reviewedContinuity: Bool

    static func freshWindow(id: CGWindowID, owner: pid_t, frame: CGRect, tolerance: CGFloat = 0.5) throws -> SCWindow {
        guard CGPreflightScreenCaptureAccess() else { throw IdentityFailure(code: "TCC_SCREEN_RECORDING_REQUIRED") }
        guard tolerance.isFinite, tolerance >= 0, tolerance <= 1 else { throw IdentityFailure(code: "INVALID_REQUEST") }
        let semaphore = DispatchSemaphore(value: 0)
        let result = IdentityCaptureBox<SCShareableContent>()
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, error in result.value = content; result.error = error; semaphore.signal() }
        guard identityAwait(semaphore, seconds: 5), let content = result.value, result.error == nil else { throw IdentityFailure(code: "CAPTURE_UNAVAILABLE") }
        let matches = content.windows.filter { $0.windowID == id }
        let cg = ((CGWindowListCopyWindowInfo([.optionIncludingWindow, .excludeDesktopElements], id) as? [[String: Any]]) ?? []).filter { ($0[kCGWindowNumber as String] as? UInt32) == id }
        guard matches.count == 1, cg.count == 1, let source = matches.first,
              source.owningApplication?.processID == owner, (cg[0][kCGWindowOwnerPID as String] as? Int32) == owner,
              source.windowLayer == (cg[0][kCGWindowLayer as String] as? Int),
              source.owningApplication?.bundleIdentifier == NSRunningApplication(processIdentifier: owner)?.bundleIdentifier,
              let dictionary = cg[0][kCGWindowBounds as String] as? [String: Any], let cgFrame = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { throw IdentityFailure(code: "WINDOW_OWNER_MISMATCH") }
        for observed in [source.frame, cgFrame] {
            guard abs(observed.minX - frame.minX) <= tolerance, abs(observed.minY - frame.minY) <= tolerance,
                  abs(observed.width - frame.width) <= tolerance, abs(observed.height - frame.height) <= tolerance else { throw IdentityFailure(code: "WINDOW_FRAME_MISMATCH") }
        }
        return source
    }
    func capture(maximumPixelEdge: Int) throws -> CGImage {
        guard reviewedContinuity else { throw IdentityFailure(code: "IDENTITY_UNPROVABLE") }
        return try captureImage(maximumPixelEdge: maximumPixelEdge)
    }
    // Explicit practical adapter only: this does not establish reviewed continuity.
    func capturePractical(maximumPixelEdge: Int) throws -> CGImage {
        return try captureImage(maximumPixelEdge: maximumPixelEdge)
    }
    private func captureImage(maximumPixelEdge: Int) throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw IdentityFailure(code: "TCC_SCREEN_RECORDING_REQUIRED") }
        guard maximumPixelEdge > 0, maximumPixelEdge <= 8192, window.frame.width > 0, window.frame.height > 0 else { throw IdentityFailure(code: "INVALID_REQUEST") }
        // macOS 13/14.0 cannot explicitly exclude composed child windows. No
        // reviewed old-OS composition provider ships, so refuse before acquisition.
        guard #available(macOS 14.2, *) else { throw IdentityFailure(code: "SURFACE_CLASSIFICATION_UNPROVABLE") }
        let configuration = SCStreamConfiguration()
        let ratio = min(1, CGFloat(maximumPixelEdge) / max(window.frame.width, window.frame.height))
        configuration.width = max(1, Int((window.frame.width * ratio).rounded(.down)))
        configuration.height = max(1, Int((window.frame.height * ratio).rounded(.down)))
        configuration.includeChildWindows = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let semaphore = DispatchSemaphore(value: 0), result = IdentityCaptureBox<CGImage>()
        try checkIdentityAndPermit()
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in result.value = image; result.error = error; semaphore.signal() }
        guard identityAwait(semaphore, seconds: 5), result.error == nil, let image = result.value else { throw IdentityFailure(code: "CAPTURE_UNAVAILABLE") }
        try checkIdentityAndPermit()
        guard CGPreflightScreenCaptureAccess() else { throw IdentityFailure(code: "TCC_SCREEN_RECORDING_REQUIRED") }
        return image
    }
}
private final class IdentityCaptureBox<T>: @unchecked Sendable {
    private let mutex = NSLock()
    private var storedValue: T?, storedError: Error?
    var value: T? { get { mutex.lock(); defer { mutex.unlock() }; return storedValue } set { mutex.lock(); storedValue = newValue; mutex.unlock() } }
    var error: Error? { get { mutex.lock(); defer { mutex.unlock() }; return storedError } set { mutex.lock(); storedError = newValue; mutex.unlock() } }
}
private func identityAwait(_ semaphore: DispatchSemaphore, seconds: Double) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if semaphore.wait(timeout: .now()) == .success { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    }
    return false
}

/// A private adapter can use this dispatcher only after independently proving
/// current no-prompt OS eligibility and exact approved launch/surface scope.
/// Stock AppKit alone cannot establish either proof, so no CLI calls it today.
struct GuardedBackgroundApplicationLaunch {
    let validatedApplication: URL
    let reviewedTrustAndExactBinding: Bool
    let checkIdentityAndPermit: () throws -> Void
    func submit() throws -> NSRunningApplication {
        guard reviewedTrustAndExactBinding else { throw IdentityFailure(code: "APP_TRUST_UNPROVABLE") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = []; configuration.environment = [:]; configuration.appleEvent = nil
        configuration.activates = false; configuration.allowsRunningApplicationSubstitution = false
        configuration.createsNewApplicationInstance = false; configuration.promptsUserIfNeeded = false; configuration.addsToRecentItems = false
        let semaphore = DispatchSemaphore(value: 0), result = IdentityCaptureBox<NSRunningApplication>()
        try checkIdentityAndPermit()
        NSWorkspace.shared.openApplication(at: validatedApplication, configuration: configuration) { application, error in result.value = application; result.error = error; semaphore.signal() }
        guard identityAwait(semaphore, seconds: 10), result.error == nil, let application = result.value else { throw IdentityFailure(code: "LAUNCH_OUTCOME_UNKNOWN") }
        try checkIdentityAndPermit()
        return application
    }
}
