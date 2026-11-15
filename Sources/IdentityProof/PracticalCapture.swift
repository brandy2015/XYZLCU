import Foundation

/// Explicit owner-selected observation assurance, separate from strict proof v1.
/// This does not authenticate a consumer, identify embedded sensitive surfaces,
/// or prove that a window incarnation persisted between the observations.
public struct PracticalCaptureEnvironment {
    public let observe: () throws -> JSONValue
    public let checkPolicy: (JSONValue) throws -> Void
    public let perform: () throws -> IdentityPayload
    public let clock: () -> UInt64
    public let wallClock: () -> String
    public init(observe: @escaping () throws -> JSONValue, checkPolicy: @escaping (JSONValue) throws -> Void,
                perform: @escaping () throws -> IdentityPayload, clock: @escaping () -> UInt64, wallClock: @escaping () -> String) {
        self.observe = observe; self.checkPolicy = checkPolicy; self.perform = perform
        self.clock = clock; self.wallClock = wallClock
    }
}

public enum PracticalCaptureCoordinator {
    public static func isAbsoluteLexicalPath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    public static func validateBinding(_ b: JSONValue) throws {
        guard let object = b.object, Set(object.keys) == ["process", "window"], let process = b["process"], let window = b["window"],
              let w = window.object, Set(w.keys) == ["window_id", "owner_pid", "layer", "frame", "on_screen"] else { throw IdentityFailure(code: "INVALID_REQUEST") }
        // The diagnostic observer names ad-hoc code adhoc_diagnostic. Reuse
        // strict field validation without widening strict's fixture-only enum;
        // keep the original value in comparisons and emitted observations.
        var schemaProcess = process
        if process["app"]?["signing"]?["kind"] == .string("adhoc_diagnostic"),
           var p = process.object, var app = p["app"]?.object, var signing = app["signing"]?.object {
            signing["kind"] = .string("adhoc_fixture"); app["signing"] = .object(signing)
            p["app"] = .object(app); schemaProcess = .object(p)
        }
        try ProofSchema.validate(schemaProcess, definition: "Process")
        try ProofSchema.validate(window["frame"] ?? .null, definition: "Frame")
        func integer(_ v: JSONValue?, max: Double) -> Bool {
            guard let n = v?.number else { return false }
            return n.isFinite && n >= 1 && n <= max && n.rounded() == n
        }
        guard integer(window["window_id"], max: Double(UInt32.max)), integer(window["owner_pid"], max: Double(Int32.max)),
              let layer = window["layer"]?.number, layer.isFinite, layer.rounded() == layer,
              window["on_screen"]?.bool != nil else { throw IdentityFailure(code: "INVALID_REQUEST") }
        guard window["owner_pid"] == process["pid"] else { throw IdentityFailure(code: "WINDOW_OWNER_MISMATCH", fields: ["window.owner_pid"]) }
        guard layer == 0 else { throw IdentityFailure(code: "WINDOW_LAYER_MISMATCH", fields: ["window.layer"]) }
        guard window["on_screen"] == .bool(true) else { throw IdentityFailure(code: "WINDOW_NOT_FOUND", fields: ["window.on_screen"]) }
        let app = process["app"]!, signing = app["signing"]!
        guard let seconds = process["start_time"]?["seconds"]?.string, let start = UInt64(seconds), start > 0 else { throw IdentityFailure(code: "INVALID_REQUEST") }
        guard let bundle = app["bundle_id"]?.string, bundle.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#, options: .regularExpression) != nil else { throw IdentityFailure(code: "BUNDLE_ID_MISMATCH") }
        for field in ["bundle_path", "executable_path"] {
            guard let p = app[field]?.string, isAbsoluteLexicalPath(p) else { throw IdentityFailure(code: "EXECUTABLE_IDENTITY_MISMATCH") }
        }
        guard app["executable_path"]!.string!.hasPrefix(app["bundle_path"]!.string! + "/") else { throw IdentityFailure(code: "EXECUTABLE_IDENTITY_MISMATCH") }
        guard signing["requirement_sha256"]?.string == JSONValue.sha256(Data(signing["designated_requirement"]!.string!.utf8)),
              !["developer_id", "app_store"].contains(signing["kind"]!.string!) || signing["team_id"] != .null else { throw IdentityFailure(code: "SIGNATURE_INVALID") }
    }

    public static func validateRequest(_ r: JSONValue) throws {
        guard let o = r.object, Set(o.keys) == ["schema_version", "nonce", "expected", "format", "max_pixel_edge"],
              r["schema_version"] == .number(1), ProofCoordinator.canonicalNonce(r["nonce"]?.string),
              ["png", "jpeg"].contains(r["format"]?.string ?? ""), let edge = r["max_pixel_edge"]?.number,
              edge.isFinite, edge.rounded() == edge, edge >= 1, edge <= 4096, let expected = r["expected"] else { throw IdentityFailure(code: "INVALID_REQUEST") }
        try validateBinding(expected)
    }

    public static func compare(_ expected: JSONValue, _ observed: JSONValue) throws {
        // Compare specific differences before semantic validation, for stable
        // mismatch codes even when the observed owner/layer becomes ineligible.
        guard let p = observed["process"], let w = observed["window"] else { throw IdentityFailure(code: "INVALID_REQUEST") }
        let ep = expected["process"]!, ew = expected["window"]!
        let processFields: [(String, String)] = [("pid", "PROCESS_IDENTITY_MISMATCH"), ("start_time", "PID_REUSED"), ("boot_id", "BOOT_MISMATCH"), ("uid", "PROCESS_UID_MISMATCH")]
        for (field, code) in processFields where ep[field] != p[field] { throw IdentityFailure(code: code, fields: ["process." + field]) }
        let appFields: [(String, String)] = [("bundle_id", "BUNDLE_ID_MISMATCH"), ("bundle_path", "EXECUTABLE_IDENTITY_MISMATCH"), ("executable_path", "EXECUTABLE_IDENTITY_MISMATCH"), ("executable_file", "EXECUTABLE_IDENTITY_MISMATCH"), ("signing", "SIGNING_IDENTITY_MISMATCH")]
        for (field, code) in appFields where ep["app"]?[field] != p["app"]?[field] { throw IdentityFailure(code: code, fields: ["process.app." + field]) }
        let windowFields: [(String, String)] = [("window_id", "WINDOW_ID_REUSED"), ("owner_pid", "WINDOW_OWNER_MISMATCH"), ("layer", "WINDOW_LAYER_MISMATCH"), ("frame", "WINDOW_FRAME_MISMATCH"), ("on_screen", "WINDOW_NOT_FOUND")]
        for (field, code) in windowFields where ew[field] != w[field] { throw IdentityFailure(code: code, fields: ["window." + field]) }
        try validateBinding(observed)
        guard expected == observed else { throw IdentityFailure(code: "IDENTITY_UNPROVABLE") }
    }

    /// Success holds private encoded bytes in memory. The CLI removes base64 and
    /// publishes a private file only after these checks; errors never carry data.
    public static func execute(request r: JSONValue, environment e: PracticalCaptureEnvironment) -> JSONValue {
        var phase = "parse", dispatched = false
        let nonce: JSONValue = ProofCoordinator.canonicalNonce(r["nonce"]?.string) ? r["nonce"]! : .null
        func instant() -> JSONValue { .object(["continuous_ns": .string(String(e.clock())), "wall_utc": .string(e.wallClock())]) }
        do {
            try validateRequest(r)
            phase = "precheck"
            let expected = r["expected"]!, begin = instant()
            try e.checkPolicy(expected)
            let first = try e.observe()
            try e.checkPolicy(first); try compare(expected, first)
            let pre = try e.observe()
            try e.checkPolicy(pre); try compare(expected, pre)
            let captureStart = instant()
            phase = "operation"; dispatched = true
            let payload = try e.perform()
            let captureEnd = instant()
            phase = "postcheck"
            let post = try e.observe()
            try e.checkPolicy(post); try compare(expected, post); try compare(pre, post)
            let end = instant()
            guard payload.kind == "image", payload.route == "sck-window-screenshot",
                  payload.mediaType == (r["format"] == .string("png") ? "image/png" : "image/jpeg"),
                  !payload.data.isEmpty, payload.data.count <= 64 * 1024 * 1024,
                  let width = payload.pixelWidth, let height = payload.pixelHeight,
                  width > 0, height > 0, max(width, height) <= Int(r["max_pixel_edge"]!.number!) else { throw IdentityFailure(code: "CAPTURE_SOURCE_UNPROVABLE") }
            let image: JSONValue = .object(["format": r["format"]!, "media_type": .string(payload.mediaType),
                "sha256": .string(JSONValue.sha256(payload.data)), "raw_pixel_sha256": payload.pixelSHA256.map(JSONValue.string) ?? .null,
                "raw_pixel_format": payload.pixelSHA256 == nil ? .null : .string("rgba8-srgb-top-left-tight-v1"),
                "pixel_width": .number(Double(width)), "pixel_height": .number(Double(height)), "byte_length": .number(Double(payload.data.count))])
            let proof: JSONValue = .object(["schema_version": .number(1), "kind": .string("window-capture"), "operation": .string("screenshot"),
                "assurance": .string("practical"), "nonce": nonce, "observed_pre": pre, "observed_post": post,
                "timing": .object(["precheck_start": begin, "capture_start": captureStart, "capture_end": captureEnd, "postcheck_end": end]),
                "image": image, "limitations": .array([
                    "Millisecond-scale same-process CGWindowID reuse with identical pre/post descriptors may escape detection; no atomic window-incarnation guarantee.",
                    "Embedded or composited sensitive content is not classified; an unprotected app may display secrets.",
                    "No authenticated consumer session, permission grant, replay protection or atomic OS snapshot; the trusted caller owns its lock and nonce lifecycle.",
                    "Ad-hoc code is content-pinned observation, not publisher trust; raw pixel digest covers a normalized RGBA8 sRGB raster."
                ].map(JSONValue.string))])
            return .object(["ok": .bool(true), "proof": proof, "result": .object(["encoding": .string("base64"), "data": .string(payload.data.base64EncodedString())])])
        } catch {
            return ProofCoordinator.failure(error as? IdentityFailure ?? IdentityFailure(code: "INTERNAL_ERROR"), nonce: nonce, phase: phase, dispatched: dispatched)
        }
    }
}
