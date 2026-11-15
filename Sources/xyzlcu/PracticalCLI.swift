import Foundation
import AppKit
import ScreenCaptureKit
import CryptoKit
import Darwin
#if SWIFT_PACKAGE
import IdentityProof
#endif

func practicalCaptureSupported() -> Bool {
    if #available(macOS 14.2, *) { return true }
    return false
}

/// No discovery, title search, AX, cache, display crop, or legacy lock fallback.
private func practicalWindow(_ expected: JSONValue) throws -> JSONValue {
    let id = CGWindowID(expected["window_id"]!.number!)
    let rows = ((CGWindowListCopyWindowInfo([.optionIncludingWindow, .excludeDesktopElements], id) as? [[String: Any]]) ?? [])
        .filter { ($0[kCGWindowNumber as String] as? UInt32) == id }
    guard rows.count == 1, let r = rows.first,
          let owner = r[kCGWindowOwnerPID as String] as? Int32,
          let layer = r[kCGWindowLayer as String] as? Int,
          let onscreen = r[kCGWindowIsOnscreen as String] as? Bool,
          let dict = r[kCGWindowBounds as String] as? [String: Any], let f = CGRect(dictionaryRepresentation: dict as CFDictionary) else { throw IdentityFailure(code: "WINDOW_NOT_FOUND") }
    return try JSONValue(any: ["window_id": id, "owner_pid": owner, "layer": layer, "on_screen": onscreen,
                              "frame": ["x": f.minX, "y": f.minY, "width": f.width, "height": f.height]])
}

/// Opens every path component relative to a retained directory descriptor. Never
/// creates directories, follows symlinks, overwrites files, or uses a temp path.
private final class PracticalImageDirectory {
    let path: String
    private var fd: Int32 = -1
    init(_ path: String) throws {
        guard PracticalCaptureCoordinator.isAbsoluteLexicalPath(path), path != "/" else { throw IdentityFailure(code: "INVALID_REQUEST") }
        self.path = path
        fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID") }
        do {
            for part in path.split(separator: "/") {
                let next = openat(fd, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Output directory must be private and contain no symlinks.") }
                close(fd); fd = next
            }
            try verify()
        } catch { close(fd); fd = -1; throw error }
    }
    deinit { if fd >= 0 { close(fd) } }
    private func requireNoACL(_ descriptor: Int32) throws {
        errno = 0
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            guard errno == ENOENT else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Cannot establish private output ACL.") }
            return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        guard acl_valid(acl) == 0, acl_get_entry(acl, ACL_FIRST_ENTRY.rawValue, &entry) == -1, errno == EINVAL else {
            throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Extended output ACLs are refused.")
        }
    }
    func verify() throws {
        try requireNoACL(fd)
        var s = stat(), linked = stat()
        guard fstat(fd, &s) == 0, lstat(path, &linked) == 0, s.st_mode & S_IFMT == S_IFDIR,
              s.st_uid == geteuid(), s.st_mode & 0o777 == 0o700, s.st_nlink > 0,
              s.st_dev == linked.st_dev, s.st_ino == linked.st_ino, linked.st_mode & S_IFMT == S_IFDIR else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID") }
    }
    func write(_ data: Data, format: String) throws -> String {
        try verify()
        let name = UUID().uuidString.lowercased() + (format == "png" ? ".png" : ".jpg")
        let out = openat(fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard out >= 0 else { throw IdentityFailure(code: "CAPTURE_UNAVAILABLE", message: "Cannot create private output file.") }
        var committed = false
        defer { close(out); if !committed { unlinkat(fd, name, 0) } }
        guard fchmod(out, 0o600) == 0 else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID") }
        try requireNoACL(out)
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(out, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw IdentityFailure(code: "CAPTURE_UNAVAILABLE") }
                offset += n
            }
        }
        var file = stat(), linked = stat()
        guard fsync(out) == 0, fstat(out, &file) == 0, fstatat(fd, name, &linked, AT_SYMLINK_NOFOLLOW) == 0,
              file.st_dev == linked.st_dev, file.st_ino == linked.st_ino, file.st_mode & S_IFMT == S_IFREG,
              file.st_nlink == 1, file.st_uid == geteuid(), file.st_mode & 0o777 == 0o600, file.st_size == data.count else { throw IdentityFailure(code: "CAPTURE_UNAVAILABLE") }
        try requireNoACL(out)
        try verify()
        committed = true
        return path + "/" + name
    }
}

private func practicalPixels(_ image: CGImage) throws -> Data {
    let width = image.width, height = image.height
    guard width > 0, height > 0, width <= 4096, height <= 4096 else { throw IdentityFailure(code: "CAPTURE_SOURCE_UNPROVABLE") }
    var bytes = Data(count: width * height * 4)
    let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard success else { throw IdentityFailure(code: "CAPTURE_UNAVAILABLE") }
    return bytes
}

func handlePracticalCLI(_ argv: [String]) throws -> Bool {
    var nonce: JSONValue = .null, phase = "parse", dispatched = false
    do {
        // All routes remain refused under consumer admission. No sensitive FD read.
        guard !argv.contains("--consumer") else { throw IdentityFailure(code: "SESSION_INVALID") }
        guard argv.first == "screenshot", Array(CommandLine.arguments.dropFirst()) == argv, !daemonMode, !inBatch else { throw IdentityFailure(code: "IDENTITY_UNPROVABLE") }
        let options = try identityArgumentOptions(argv, values: ["--assurance", "--request-fd", "--output-dir"], flags: ["--json"])
        guard ["practical", "strict"].contains(options["--assurance"] ?? "") else { throw IdentityFailure(code: "INVALID_REQUEST") }
        guard options["--assurance"] == "practical" else { throw IdentityFailure(code: "IDENTITY_UNPROVABLE") }
        guard let requestFD = options["--request-fd"], let outputPath = options["--output-dir"], options["--json"] != nil else { throw IdentityFailure(code: "INVALID_REQUEST") }
        let request = try identityReadRequest(requestFD)
        if ProofCoordinator.canonicalNonce(request["nonce"]?.string) { nonce = request["nonce"]! }
        try PracticalCaptureCoordinator.validateRequest(request)
        phase = "precheck"
        let expected = request["expected"]!, expectedProcess = expected["process"]!, expectedWindow = expected["window"]!
        let pid = pid_t(expectedProcess["pid"]!.number!), id = CGWindowID(expectedWindow["window_id"]!.number!)
        let policy = try ProtectedAppPolicy.loadUserPolicy(requireInitialized: false)
        func checkPolicy(_ binding: JSONValue) throws {
            // Reload continuity state at every boundary; policy changes invalidate.
            let current = try ProtectedAppPolicy.loadUserPolicy(requireInitialized: false)
            guard current.digest == policy.digest else { throw IdentityFailure(code: "POLICY_CHANGED") }
            let process = binding["process"]!, app = process["app"]!, signing = app["signing"]!
            let verdict = current.evaluate(bundleID: app["bundle_id"]!.string!, teamID: signing["team_id"]?.string,
                                           signingID: signing["signing_identifier"]?.string, validSignature: signing["valid"] == .bool(true))
            guard verdict.decision != "deny" else { throw IdentityFailure(code: verdict.code ?? "PROTECTED_APP_REFUSED") }
        }
        try checkPolicy(expected)
        // Deny the currently observed owner too before any content acquisition,
        // even if a stale caller claims that a protected PID was unprotected.
        if let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            let verdict = policy.evaluate(bundleID: bundle, teamID: nil, signingID: nil, validSignature: false)
            if ["protected", "suspicious_identity"].contains(verdict.classification) { throw IdentityFailure(code: verdict.code ?? "PROTECTED_APP_REFUSED") }
        }
        let directory = try PracticalImageDirectory(outputPath)
        guard practicalCaptureSupported() else { throw IdentityFailure(code: "SURFACE_CLASSIFICATION_UNPROVABLE") }
        func observe() throws -> JSONValue {
            let pre = try JSONValue(any: NativeProcessIdentity.observe(pid))
            let w = try practicalWindow(expectedWindow)
            let post = try JSONValue(any: NativeProcessIdentity.observe(pid))
            try PracticalCaptureCoordinator.compare(expected, .object(["process": pre, "window": w]))
            try PracticalCaptureCoordinator.compare(expected, .object(["process": post, "window": w]))
            return .object(["process": post, "window": w])
        }
        func guardNow() throws {
            try directory.verify()
            let binding = try observe(); try checkPolicy(binding)
            guard CGPreflightScreenCaptureAccess() else { throw IdentityFailure(code: "TCC_SCREEN_RECORDING_REQUIRED") }
        }
        let env = PracticalCaptureEnvironment(observe: observe, checkPolicy: checkPolicy, perform: {
            let f = expectedWindow["frame"]!
            let frame = CGRect(x: f["x"]!.number!, y: f["y"]!.number!, width: f["width"]!.number!, height: f["height"]!.number!)
            let source = try GuardedSCKWindowCapture.freshWindow(id: id, owner: pid, frame: frame, tolerance: 0)
            guard source.windowLayer == 0, source.isOnScreen, source.owningApplication?.bundleIdentifier == expectedProcess["app"]?["bundle_id"]?.string else { throw IdentityFailure(code: "WINDOW_OWNER_MISMATCH") }
            let service = GuardedSCKWindowCapture(window: source, checkIdentityAndPermit: guardNow, reviewedContinuity: false)
            dispatched = true
            let image = try service.capturePractical(maximumPixelEdge: Int(request["max_pixel_edge"]!.number!))
            let pixels = try practicalPixels(image)
            let rep = NSBitmapImageRep(cgImage: image), png = request["format"] == .string("png")
            guard let encoded = rep.representation(using: png ? .png : .jpeg, properties: png ? [:] : [.compressionFactor: 0.9]) else { throw IdentityFailure(code: "CAPTURE_UNAVAILABLE") }
            return IdentityPayload(data: encoded, kind: "image", mediaType: png ? "image/png" : "image/jpeg", route: "sck-window-screenshot",
                                   pixelSHA256: JSONValue.sha256(pixels), pixelWidth: image.width, pixelHeight: image.height)
        }, clock: { UInt64(identityInstant()["continuous_ns"] as! String)! }, wallClock: { ISO8601DateFormatter().string(from: Date()) })
        let response = PracticalCaptureCoordinator.execute(request: request, environment: env)
        if response["ok"] != .bool(true) {
            try identityEmit(try JSONSerialization.jsonObject(with: response.canonicalData()))
            throw XErr(msg: response["code"]!.string!, code: Int32(response["exit_code"]!.number!), policyCode: response["code"]!.string!)
        }
        phase = "release"
        try guardNow()
        guard let bytes = Data(base64Encoded: response["result"]!["data"]!.string!) else { throw IdentityFailure(code: "INTERNAL_ERROR") }
        // Complete all fallible proof preparation before publishing a file.
        var json = try JSONSerialization.jsonObject(with: response.canonicalData()) as! [String: Any]
        var proof = json["proof"] as! [String: Any]
        proof["executor"] = try identityExecutor(); proof["policy_sha256"] = policy.digest
        let path = try directory.write(bytes, format: request["format"]!.string!)
        var image = proof["image"] as! [String: Any]; image["path"] = path; proof["image"] = image
        json["proof"] = proof; json["result"] = ["path": path]
        try identityEmit(json)
        return true
    } catch let refusal as XErr { throw refusal }
    catch {
        let response = ProofCoordinator.failure(error as? IdentityFailure ?? IdentityFailure(code: "INTERNAL_ERROR"), nonce: nonce, phase: phase, dispatched: dispatched)
        try identityEmit(try JSONSerialization.jsonObject(with: response.canonicalData()))
        throw XErr(msg: response["code"]!.string!, code: Int32(response["exit_code"]!.number!), policyCode: response["code"]!.string!)
    }
}
