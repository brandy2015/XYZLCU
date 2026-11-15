import Foundation

public struct IdentityObservation {
    public let binding: JSONValue
    public let assurance: [String]
    public let policy: JSONValue
    public init(binding: JSONValue, assurance: [String], policy: JSONValue) {
        self.binding = binding; self.assurance = assurance; self.policy = policy
    }
}
public struct IdentityPayload {
    public let data: Data
    public let kind: String, mediaType: String, route: String, effectVerification: String
    public let pixelSHA256: String?
    public let pixelWidth: Int?, pixelHeight: Int?
    public let sourceFrameContinuousNS: UInt64?
    public init(data: Data, kind: String, mediaType: String, route: String, effectVerification: String = "not_applicable", pixelSHA256: String? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil, sourceFrameContinuousNS: UInt64? = nil) {
        self.data = data; self.kind = kind; self.mediaType = mediaType; self.route = route; self.effectVerification = effectVerification
        self.pixelSHA256 = pixelSHA256; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.sourceFrameContinuousNS = sourceFrameContinuousNS
    }
}
public struct CoordinatorEnvironment {
    public let executor: JSONValue
    public let policySHA256: String, bootID: String
    public let observe: () throws -> IdentityObservation
    public let perform: () throws -> IdentityPayload
    public let checkPermit: () throws -> Void
    public let authority: DispatchAuthority
    public let clock: () -> UInt64
    public let wallClock: () -> String
    public init(executor: JSONValue, policySHA256: String, bootID: String, observe: @escaping () throws -> IdentityObservation, perform: @escaping () throws -> IdentityPayload, checkPermit: @escaping () throws -> Void = {}, authority: DispatchAuthority = DispatchAuthority(), clock: @escaping () -> UInt64, wallClock: @escaping () -> String) {
        self.executor = executor; self.policySHA256 = policySHA256; self.bootID = bootID; self.observe = observe; self.perform = perform; self.checkPermit = checkPermit; self.authority = authority; self.clock = clock; self.wallClock = wallClock
    }
}

/// One primitive per call. Providers retain the exact validated API objects and
/// must never resolve a selector again in perform(). This coordinator is evidence
/// plumbing for owner diagnostics; it cannot admit a consumer session.
public final class ProofCoordinator {
    private let lock = NSLock()
    private let capacity: Int
    private var consumed = Set<String>()
    private var sequences: [String: UInt64] = [:]
    public init(nonceCapacity: Int = 4096) { capacity = nonceCapacity }

    public func execute(request: JSONValue, environment e: CoordinatorEnvironment) -> JSONValue {
        lock.lock(); defer { lock.unlock() }
        var phase = "parse", dispatched = false
        let nonce = Self.canonicalNonce(request["nonce"]?.string) ? request["nonce"]! : .null
        let operation = request["operation"]?.string ?? ""
        do {
            try ProofSchema.validate(request, definition: "Request")
            try semanticValidation(request)
            // A profile string is not admission. No authenticated bootstrap or
            // reviewed continuity/surface provider ships in this version.
            if request["profile"]?.string == "xyzstudio" { throw IdentityFailure(code:"SESSION_INVALID", message:"Authenticated consumer admission is unavailable.") }
            if request["mac"] != .null { throw IdentityFailure(code:"PROOF_CAPABILITY_UNSUPPORTED", message:"Diagnostic integrity negotiation is unavailable.") }
            phase = "precheck"
            func permit() throws {
                try e.checkPermit()
                try e.authority.check()
                guard request["deadline"]?["boot_id"]?.string == e.bootID else { throw IdentityFailure(code:"BOOT_MISMATCH",fields:["deadline.boot_id"]) }
                guard let deadline = UInt64(request["deadline"]?["continuous_ns"]?.string ?? ""), e.clock() < deadline else { throw IdentityFailure(code:"REQUEST_EXPIRED",fields:["deadline.continuous_ns"]) }
                guard request["policy_sha256"]?.string == e.policySHA256 else { throw IdentityFailure(code:"POLICY_CHANGED",fields:["policy_sha256"]) }
            }
            try permit()
            let session = request["session_id"]!.string! + ":" + request["controller_id"]!.string!
            let sequence = UInt64(request["sequence"]!.string!)!
            let replayKey = session + ":" + nonce.string!
            guard !consumed.contains(replayKey), sequences[session].map({ sequence > $0 }) ?? true else { throw IdentityFailure(code:"REQUEST_REPLAYED") }
            guard consumed.count < capacity else { throw IdentityFailure(code:"SESSION_INVALID",message:"Replay ledger capacity exhausted.") }
            consumed.insert(replayKey); sequences[session] = sequence
            let preStart = instant(e)
            var pre = try e.observe()
            try validateObservation(pre, request:request, expected:request["expected"]!, post:false)
            try permit()
            // Repeat after slow lookup and use this exact observation at dispatch.
            pre = try e.observe()
            try validateObservation(pre, request:request, expected:request["expected"]!, post:false)
            try permit()
            let preEnd = instant(e)
            let operationStart = instant(e)
            try e.authority.beginDispatch {
                guard let deadline = UInt64(request["deadline"]?["continuous_ns"]?.string ?? ""), e.clock() < deadline else { throw IdentityFailure(code:"REQUEST_EXPIRED") }
            }
            phase = "operation"; dispatched = true
            let payload = try e.perform()
            let operationEnd = instant(e)
            phase = "postcheck"
            let postStart = instant(e)
            try permit()
            let post = try e.observe()
            try validateObservation(post, request:request, expected:pre.binding, post:true)
            try validateObservation(post, request:request, expected:request["expected"]!, post:true)
            try permit()
            if pre.assurance.contains("surface-continuity"), pre.policy["surface_evidence"] != post.policy["surface_evidence"] { throw IdentityFailure(code:"SURFACE_CLASSIFICATION_UNPROVABLE") }
            let postEnd = instant(e)
            phase = "release"
            try validatePayload(payload, operation:operation)
            if operation == "screenshot", payload.mediaType != (request["arguments"]?["format"]?.string == "png" ? "image/png" : "image/jpeg") { throw IdentityFailure(code:"CAPTURE_SOURCE_UNPROVABLE") }
            try permit()
            let release = instant(e)
            guard let preN = preEnd["continuous_ns"]?.string.flatMap(UInt64.init), let endN = operationEnd["continuous_ns"]?.string.flatMap(UInt64.init),
                  let pstart = postStart["continuous_ns"]?.string.flatMap(UInt64.init), preN <= endN, endN <= pstart else { throw IdentityFailure(code:"INTERNAL_ERROR") }
            if let frame = payload.sourceFrameContinuousNS, !(preN...endN).contains(frame) { throw IdentityFailure(code:"CAPTURE_FRAME_STALE") }
            let bindingDigest = JSONValue.sha256(request["expected"]!.canonicalData(), domain:"XYZLCU/BINDING/1\0")
            let requestDigest = JSONValue.sha256(request.canonicalData(), domain:"XYZLCU/REQUEST/1\0")
            let assurance = Set(pre.assurance).intersection(post.assurance).sorted()
            let metadata: JSONValue = .object([
                "kind":.string(payload.kind), "sha256":.string(JSONValue.sha256(payload.data,domain:"XYZLCU/PAYLOAD/1\0")),
                "byte_length":.number(Double(payload.data.count)), "media_type":.string(payload.mediaType),
                "pixel_sha256":payload.pixelSHA256.map(JSONValue.string) ?? .null,
                "pixel_width":payload.pixelWidth.map { .number(Double($0)) } ?? .null,
                "pixel_height":payload.pixelHeight.map { .number(Double($0)) } ?? .null])
            let proof: JSONValue = .object([
                "schema_version":.number(1), "session_id":request["session_id"]!, "controller_id":request["controller_id"]!,
                "lock_revision":request["lock_revision"]!, "nonce":nonce, "sequence":request["sequence"]!, "operation":.string(operation),
                "request_sha256":.string(requestDigest), "expected_binding_sha256":.string(bindingDigest), "executor":e.executor,
                "observed_pre":pre.binding, "observed_post":post.binding,
                "timing":.object(["precheck":interval(preStart,preEnd),"operation":interval(operationStart,operationEnd),"postcheck":interval(postStart,postEnd),"release":release,"source_frame_continuous_ns":payload.sourceFrameContinuousNS.map { .string(String($0)) } ?? .null]),
                "assurance":.array(assurance.map(JSONValue.string)), "identity_check":.string("matched"), "effect_verification":.string(payload.effectVerification),
                "policy":post.policy, "payload":metadata, "route":.string(payload.route),
                "limitations":.array((["diagnostic-only-no-authenticated-consumer-session", "observations-are-not-atomic-os-target-guarantees"] + (payload.kind == "image" && payload.sourceFrameContinuousNS == nil ? ["source-frame-time-unavailable-no-freshness-guarantee"] : [])).map(JSONValue.string)), "mac":.null])
            let result: JSONValue = .object(["encoding":.string(payload.kind == "image" ? "base64" : "jcs-json"),"data":.string(payload.kind == "image" ? payload.data.base64EncodedString() : String(data:payload.data,encoding:.utf8)!)])
            let success: JSONValue = .object(["ok":.bool(true), "proof":proof, "result":result])
            try ProofSchema.validate(success, definition:"Success")
            guard success.canonicalData().count <= 64 * 1024 * 1024 else { throw IdentityFailure(code:"REQUEST_TOO_LARGE") }
            // The final provider gate precedes publication; data has remained local.
            try permit()
            return success
        } catch {
            let failure = error as? IdentityFailure ?? IdentityFailure(code:"INTERNAL_ERROR")
            return Self.failure(failure, nonce:nonce, phase:phase, dispatched:dispatched, sideEffects:["press","set-text","click","open-app"].contains(operation))
        }
    }

    public static func failure(_ error: IdentityFailure, nonce: JSONValue = .null, phase: String = "parse", dispatched: Bool = false, sideEffects: Bool = false) -> JSONValue {
        let parse = ["INVALID_REQUEST","DUPLICATE_JSON_KEY","REQUEST_TOO_LARGE"]
        let capability = ["PROOF_PROTOCOL_UNSUPPORTED","PROOF_CAPABILITY_UNSUPPORTED"]
        let runtime = ["TCC_SCREEN_RECORDING_REQUIRED","TCC_ACCESSIBILITY_REQUIRED","CAPTURE_UNAVAILABLE","CAPTURE_TIMEOUT","CAPTURE_FRAME_STALE","CAPTURE_SOURCE_UNPROVABLE","CAPTURE_CLEANUP_FAILED","AX_READ_FAILED","AX_ACTION_FAILED","EFFECT_UNVERIFIED","APP_NOT_FOUND","APP_PATH_REFUSED","APP_RESOLUTION_AMBIGUOUS","APP_IDENTITY_CHANGED","LAUNCH_BINDING_UNPROVABLE","LAUNCH_FAILED","LAUNCH_OUTCOME_UNKNOWN","APP_TRUST_UNPROVABLE","APP_TRUST_REFUSED"]
        let code = error.code
        let exit = parse.contains(code) ? 2 : capability.contains(code) ? 3 : runtime.contains(code) ? 5 : ["CANCELLED","PARENT_CHANNEL_LOST","DEADLINE_EXCEEDED","OUTCOME_UNKNOWN"].contains(code) ? 6 : code == "INTERNAL_ERROR" ? 1 : 4
        return .object(["schema_version":.number(1),"ok":.bool(false),"code":.string(code),"exit_code":.number(Double(exit)),"nonce":canonicalNonce(nonce.string) ? nonce : .null,"phase":.string(phase),"dispatch_state":.string(dispatched ? "dispatched" : "not_dispatched"),"side_effects_possible":.bool(dispatched && sideEffects),"retryable":.bool(false),"mismatch_fields":.array(error.fields.prefix(32).map { .string(String($0.prefix(128))) }),"message":.string(String(error.message.prefix(256))),"mac":.null])
    }
    public static func canonicalNonce(_ nonce: String?) -> Bool {
        guard let nonce = nonce, nonce.count == 43, nonce.range(of:#"^[A-Za-z0-9_-]{43}$"#,options:.regularExpression) != nil,
              let bytes = Data(base64Encoded:nonce.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/") + "="), bytes.count == 32 else { return false }
        return bytes.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"") == nonce
    }
    private func semanticValidation(_ r: JSONValue) throws {
        guard Self.canonicalNonce(r["nonce"]?.string) else { throw IdentityFailure(code:"INVALID_REQUEST",fields:["nonce"]) }
        for key in ["sequence","lock_revision"] { guard UInt64(r[key]?.string ?? "") != nil else { throw IdentityFailure(code:"INVALID_REQUEST",fields:[key]) } }
        guard UInt64(r["deadline"]?["continuous_ns"]?.string ?? "") != nil else { throw IdentityFailure(code:"INVALID_REQUEST",fields:["deadline.continuous_ns"]) }
        let op = r["operation"]!.string!, args = r["arguments"]!.object!, expected = r["expected"]!
        let keys: Set<String>
        switch op {
        case "screenshot": keys = ["format","max_pixel_edge"]
        case "ax": keys = ["max_depth","max_nodes"]
        case "press": keys = ["action"]
        case "set-text": keys = ["text","precondition_sha256","postcondition_sha256"]
        case "click": keys = ["x","y","action"]
        case "open-app": keys = ["bundle_id","activates"]
        default: throw IdentityFailure(code:"INVALID_REQUEST")
        }
        guard Set(args.keys) == keys else { throw IdentityFailure(code:"INVALID_REQUEST",fields:["arguments"]) }
        if op == "open-app" {
            guard expected["app"] != nil, args["bundle_id"] == expected["app"]?["bundle_id"] else { throw IdentityFailure(code:"INVALID_REQUEST",fields:["expected.app.bundle_id"]) }
            throw IdentityFailure(code:"LAUNCH_BINDING_UNPROVABLE",message:"Atomic exact-code launch is unavailable in the proof coordinator.")
        }
        guard expected["process"] != nil else { throw IdentityFailure(code:"INVALID_REQUEST",fields:["expected"]) }
        if op == "screenshot", expected["element"] != .null { throw IdentityFailure(code:"INVALID_REQUEST",fields:["expected.element"]) }
        if ["press","set-text","click"].contains(op), expected["element"] == .null { throw IdentityFailure(code:"BINDING_REQUIRED",fields:["expected.element"]) }
        if r["catalog_context"] != .null && op != "screenshot" { throw IdentityFailure(code:"INVALID_REQUEST",fields:["catalog_context"]) }
        if op == "set-text", expected["element"]?["state_sha256"] != args["precondition_sha256"] { throw IdentityFailure(code:"AX_CONTEXT_MISMATCH",fields:["element.state_sha256"]) }
        try validateBinding(expected)
    }
    private func validateBinding(_ b: JSONValue) throws {
        let p = b["process"]!, a = p["app"]!, signing = a["signing"]!
        guard UInt64(p["start_time"]?["seconds"]?.string ?? "") != nil else { throw IdentityFailure(code:"PROCESS_IDENTITY_UNAVAILABLE") }
        guard b["window"]?["owner_pid"] == p["pid"] else { throw IdentityFailure(code:"WINDOW_OWNER_MISMATCH",fields:["window.owner_pid"]) }
        guard let bundle = a["bundle_id"]?.string, bundle.range(of:#"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#,options:.regularExpression) != nil else { throw IdentityFailure(code:"BUNDLE_ID_MISMATCH") }
        for key in ["bundle_path","executable_path"] {
            guard let path = a[key]?.string, path.hasPrefix("/"), !path.contains("\0"), (path as NSString).standardizingPath == path else { throw IdentityFailure(code:"EXECUTABLE_IDENTITY_MISMATCH",fields:["process.app." + key]) }
        }
        let bp = a["bundle_path"]!.string!, ep = a["executable_path"]!.string!
        guard ep.hasPrefix(bp + "/") else { throw IdentityFailure(code:"EXECUTABLE_IDENTITY_MISMATCH",fields:["process.app.executable_path"]) }
        if ["developer_id","app_store"].contains(signing["kind"]!.string!), signing["team_id"] == .null { throw IdentityFailure(code:"SIGNATURE_INVALID") }
        guard signing["requirement_sha256"]?.string == JSONValue.sha256(Data(signing["designated_requirement"]!.string!.utf8)) else { throw IdentityFailure(code:"SIGNATURE_INVALID",fields:["process.app.signing.requirement_sha256"]) }
        let displays = b["window"]?["displays"]?.array ?? []
        let displayIDs = displays.compactMap { $0["id"]?.number }
        guard displayIDs == displayIDs.sorted(), Set(displayIDs).count == displayIDs.count else { throw IdentityFailure(code:"DISPLAY_BINDING_MISMATCH") }
        if let actions = b["element"]?["actions"]?.array?.compactMap(\.string), actions != actions.sorted() { throw IdentityFailure(code:"AX_TARGET_MISMATCH",fields:["element.actions"]) }
    }
    private func validateObservation(_ observation: IdentityObservation, request r: JSONValue, expected: JSONValue, post: Bool) throws {
        // Policy must already be checked by the observer before any content API.
        if observation.policy["decision"]?.string == "deny" {
            let suspicious = observation.policy["classification"]?.string == "suspicious_identity"
            throw IdentityFailure(code:suspicious ? "PROTECTED_IDENTITY_SUSPICIOUS" : "PROTECTED_APP_REFUSED")
        }
        try ProofSchema.validate(observation.policy,definition:"Policy")
        guard observation.policy["sha256"]?.string == r["policy_sha256"]?.string else { throw IdentityFailure(code:"POLICY_CHANGED") }
        try ProofSchema.validate(observation.binding,definition:"Binding")
        try validateBinding(observation.binding)
        let wanted = Set(r["required_assurance"]!.array!.compactMap(\.string))
        let offered = Set(observation.assurance)
        if offered.contains("window-instance"), observation.binding["window"]?["instance_token"] == .null || observation.binding["window"]?["instance_provider"] == .null { throw IdentityFailure(code:"IDENTITY_UNPROVABLE") }
        if offered.contains("element-instance"), observation.binding["element"] != .null, observation.binding["element"]?["instance_provider"] == .null { throw IdentityFailure(code:"AX_INSTANCE_UNPROVABLE") }
        if offered.contains("surface-continuity"), observation.policy["surface_classification"]?.string != "allowed" || observation.policy["surface_evidence"] == .null { throw IdentityFailure(code:"SURFACE_CLASSIFICATION_UNPROVABLE") }
        guard wanted.isSubset(of:offered) else {
            if wanted.contains("element-instance"), !offered.contains("element-instance") { throw IdentityFailure(code:"AX_INSTANCE_UNPROVABLE") }
            throw IdentityFailure(code:"IDENTITY_UNPROVABLE")
        }
        guard offered.contains("process-instance"), offered.contains("window-observed") else { throw IdentityFailure(code:"IDENTITY_UNPROVABLE") }
        try compare(expected, observation.binding, tolerance:r["frame_tolerance_pt"]!.number!, post:post, operation:r["operation"]!.string!, arguments:r["arguments"]!)
    }
    private func compare(_ expected: JSONValue, _ actual: JSONValue, tolerance: Double, post: Bool, operation: String, arguments: JSONValue) throws {
        func same(_ lhs: JSONValue?, _ rhs: JSONValue?, _ code: String, _ field: String) throws { if lhs != rhs { throw IdentityFailure(code:code,fields:[field]) } }
        let ep = expected["process"]!, ap = actual["process"]!
        try same(ep["boot_id"],ap["boot_id"],"BOOT_MISMATCH","process.boot_id")
        try same(ep["pid"],ap["pid"],"PID_REUSED","process.pid")
        try same(ep["start_time"],ap["start_time"],"PID_REUSED","process.start_time")
        try same(ep["uid"],ap["uid"],"PROCESS_UID_MISMATCH","process.uid")
        let ea = ep["app"]!, aa = ap["app"]!
        try same(ea["bundle_id"],aa["bundle_id"],"BUNDLE_ID_MISMATCH","process.app.bundle_id")
        try same(ea["signing"],aa["signing"],"SIGNING_IDENTITY_MISMATCH","process.app.signing")
        for k in ["bundle_path","executable_path","executable_file"] { try same(ea[k],aa[k],"EXECUTABLE_IDENTITY_MISMATCH","process.app." + k) }
        let ew = expected["window"]!, aw = actual["window"]!
        try same(ew["id"],aw["id"],"WINDOW_ID_REUSED","window.id")
        try same(ew["instance_token"],aw["instance_token"],"WINDOW_ID_REUSED","window.instance_token")
        try same(ew["instance_provider"],aw["instance_provider"],"IDENTITY_UNPROVABLE","window.instance_provider")
        try same(ew["owner_pid"],aw["owner_pid"],"WINDOW_OWNER_MISMATCH","window.owner_pid")
        try same(ew["layer"],aw["layer"],"WINDOW_LAYER_MISMATCH","window.layer")
        for k in ["x","y","width","height"] {
            guard let lhs = ew["frame"]?[k]?.number, let rhs = aw["frame"]?[k]?.number, abs(lhs-rhs) <= tolerance else { throw IdentityFailure(code:"WINDOW_FRAME_MISMATCH",fields:["window.frame." + k]) }
        }
        try same(ew["displays"],aw["displays"],"DISPLAY_BINDING_MISMATCH","window.displays")
        for k in ["coordinate_space","content_transform_sha256","onscreen"] { try same(ew[k],aw[k],"COORDINATE_MAPPING_UNPROVABLE","window." + k) }
        try same(expected["binding_token"],actual["binding_token"],"BINDING_STALE","binding_token")
        try same(expected["context_sha256"],actual["context_sha256"],"AX_CONTEXT_MISMATCH","context_sha256")
        let ee = expected["element"], ae = actual["element"]
        if ee != .null || ae != .null {
            guard let eo = ee?.object, var ao = ae?.object else { throw IdentityFailure(code:"AX_ELEMENT_REPLACED",fields:["element"]) }
            try same(eo["token"],ao["token"],"AX_ELEMENT_REPLACED","element.token")
            if post && operation == "set-text" {
                guard ao["state_sha256"] == arguments["postcondition_sha256"], eo["state_sha256"] == arguments["precondition_sha256"] else { throw IdentityFailure(code:"AX_CONTEXT_MISMATCH",fields:["element.state_sha256"]) }
                ao["state_sha256"] = eo["state_sha256"]
            }
            try same(.object(eo),.object(ao),"AX_TARGET_MISMATCH","element")
        }
    }
    private func validatePayload(_ p: IdentityPayload, operation: String) throws {
        if operation == "screenshot" {
            guard p.kind == "image", ["image/png","image/jpeg"].contains(p.mediaType), ["sck-window-screenshot","sck-window-stream-once"].contains(p.route), p.pixelSHA256 != nil, p.pixelWidth != nil, p.pixelHeight != nil, p.data.count <= 24 * 1024 * 1024 else { throw IdentityFailure(code:"CAPTURE_SOURCE_UNPROVABLE") }
        } else {
            let kind = operation == "ax" ? "ax_json" : "action_receipt"
            let route = operation == "ax" ? "ax-read" : operation == "set-text" ? "ax-set-value" : "ax-press"
            guard p.kind == kind, p.route == route, p.mediaType == "application/json", p.pixelSHA256 == nil, p.pixelWidth == nil, p.pixelHeight == nil else { throw IdentityFailure(code:"INVALID_REQUEST") }
            let value = try JSONValue.parse(p.data,maximumBytes:4*1024*1024,maximumDepth:64)
            guard value.canonicalData() == p.data else { throw IdentityFailure(code:"PAYLOAD_DIGEST_MISMATCH") }
        }
    }
    private func instant(_ e: CoordinatorEnvironment) -> JSONValue { .object(["continuous_ns":.string(String(e.clock())),"wall_utc":.string(e.wallClock())]) }
    private func interval(_ start: JSONValue, _ end: JSONValue) -> JSONValue { .object(["start":start,"end":end]) }
}
