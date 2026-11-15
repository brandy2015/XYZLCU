import XCTest
@testable import IdentityProof

final class IdentityProofTests: XCTestCase {
    let digest = String(repeating:"a",count:64)
    let token = String(repeating:"a",count:32)
    let boot = "12345678-1234-1234-1234-123456789abc"
    func json(_ object: Any) throws -> JSONValue { try JSONValue(any:object) }
    func change(_ value: JSONValue, _ path: [String], _ replacement: JSONValue) -> JSONValue {
        guard let key = path.first else { return replacement }
        var obj = value.object!; obj[key] = change(obj[key]!,Array(path.dropFirst()),replacement); return .object(obj)
    }
    func binding(element: Bool = false) throws -> JSONValue {
        let frame: [String:Any] = ["x":0,"y":0,"width":500,"height":300]
        let requirement = "identifier fixture"
        let signing: [String:Any] = ["kind":"adhoc_fixture","valid":true,"team_id":NSNull(),"signing_identifier":"com.xyztech.fixture","cdhash":String(repeating:"b",count:40),"cdhash_algorithm":"sha256_truncated","architecture":"arm64","designated_requirement":requirement,"requirement_sha256":JSONValue.sha256(Data(requirement.utf8))]
        let app: [String:Any] = ["bundle_id":"com.xyztech.fixture","bundle_path":"/tmp/Fixture.app","executable_path":"/tmp/Fixture.app/Contents/MacOS/Fixture","executable_file":["device":"1","inode":"2","sha256":digest],"signing":signing]
        let process: [String:Any] = ["boot_id":boot,"pid":4242,"uid":501,"start_time":["seconds":"1700000000","microseconds":123456],"app":app]
        let window: [String:Any] = ["id":42,"owner_pid":4242,"layer":0,"frame":frame,"onscreen":true,"displays":[["id":1,"uuid":boot,"frame":frame,"scale":2,"rotation":0]],"coordinate_space":"desktop-top-left-points-v1","content_transform_sha256":digest,"instance_token":"fixture-generation-1","instance_provider":"fixture-v1"]
        let el: [String:Any] = ["token":token,"path":[["child_index":0,"role":"AXButton","subrole":NSNull(),"identifier":"ok"]],"role":"AXButton","subrole":NSNull(),"identifier":"ok","title_sha256":digest,"frame":frame,"actions":["AXPress"],"state_sha256":digest,"context_sha256":digest,"observation_id":token,"observation_revision":"1","instance_provider":"fixture-v1"]
        return try json(["binding_token":token,"process":process,"window":window,"element":element ? el as Any : NSNull() as Any,"context_sha256":digest])
    }
    func request(operation:String = "screenshot", expected:JSONValue? = nil) throws -> JSONValue {
        var r = try json(["schema_version":1,"profile":"owner_diagnostic","session_id":token,"controller_id":token,"lock_revision":"1","policy_sha256":digest,"nonce":String(repeating:"A",count:43),"sequence":"1","deadline":["boot_id":boot,"continuous_ns":"10000"],"operation":operation,"expected":NSNull(),"required_assurance":["process-instance","window-observed"],"frame_tolerance_pt":0.5,"catalog_context":NSNull(),"arguments":operation == "screenshot" ? ["format":"png","max_pixel_edge":1024] : operation == "ax" ? ["max_depth":8,"max_nodes":100] : ["action":"AXPress"],"mac":NSNull()])
        r = change(r,["expected"],try expected ?? binding(element:operation != "screenshot")); return r
    }
    func policy() throws -> JSONValue {
        try json(["sha256":digest,"catalog_revision":"test-v1","classification":"unknown","decision":"allow","matched_rule_ids":[],"surface_classification":"unknown","surface_evidence":NSNull()])
    }
    func environment(observations: [JSONValue]? = nil, operation:String = "screenshot", observeError:IdentityFailure? = nil, permits: (() throws -> Void)? = nil, performed: @escaping () -> Void = {}) throws -> CoordinatorEnvironment {
        let snapshots = try observations ?? [binding(element:operation != "screenshot")]
        var index = 0
        let p = try policy()
        let executor = try json(["pid":999,"start_time":"1700000000123456","boot_id":boot,"build_sha256":digest,"execution_mode":"direct","client_build_sha256":NSNull()])
        return CoordinatorEnvironment(executor:executor,policySHA256:digest,bootID:boot,observe:{
            if let error = observeError { throw error }
            let b = snapshots[min(index,snapshots.count-1)]; index += 1
            return IdentityObservation(binding:b,assurance:["process-instance","window-observed","window-instance","element-observed","element-instance"],policy:p)
        },perform:{
            performed()
            if operation == "screenshot" { return IdentityPayload(data:Data("fixture-image".utf8),kind:"image",mediaType:"image/png",route:"sck-window-screenshot",pixelSHA256:self.digest,pixelWidth:500,pixelHeight:300,sourceFrameContinuousNS:100) }
            return IdentityPayload(data:Data("{}".utf8),kind:operation == "ax" ? "ax_json" : "action_receipt",mediaType:"application/json",route:operation == "ax" ? "ax-read" : "ax-press",effectVerification:"unverified")
        },checkPermit: permits ?? {},clock:{100},wallClock:{"2026-11-15T00:00:00Z"})
    }
    func code(_ result:JSONValue) -> String? { result["code"]?.string }
    func testSuccessNonceSchemaDigests() throws {
        let r = try request(), result = ProofCoordinator().execute(request:r,environment:try environment())
        XCTAssertEqual(result["ok"]?.bool,true, result.canonicalString)
        try ProofSchema.validate(result,definition:"Success")
        XCTAssertEqual(result["proof"]?["nonce"],r["nonce"])
        XCTAssertEqual(result["proof"]?["request_sha256"]?.string,JSONValue.sha256(r.canonicalData(),domain:"XYZLCU/REQUEST/1\0"))
        XCTAssertEqual(result["proof"]?["payload"]?["sha256"]?.string,JSONValue.sha256(Data("fixture-image".utf8),domain:"XYZLCU/PAYLOAD/1\0"))
        XCTAssertEqual(result["proof"]?["effect_verification"]?.string,"not_applicable")
    }
    func testPIDReuseBeforeDispatch() throws {
        let changed = change(try binding(),["process","start_time","microseconds"],.number(123457)); var calls = 0
        let result = ProofCoordinator().execute(request:try request(),environment:try environment(observations:[changed],performed:{calls += 1}))
        XCTAssertEqual(code(result),"PID_REUSED"); XCTAssertEqual(calls,0); XCTAssertNil(result["result"]); XCTAssertEqual(result["dispatch_state"]?.string,"not_dispatched")
    }
    func testPIDReuseAfterDispatchDiscardsPayload() throws {
        let base = try binding(), changed = change(base,["process","start_time","seconds"],.string("1700000001"))
        let result = ProofCoordinator().execute(request:try request(),environment:try environment(observations:[base,base,changed]))
        XCTAssertEqual(code(result),"PID_REUSED"); XCTAssertEqual(result["phase"]?.string,"postcheck"); XCTAssertNil(result["proof"]); XCTAssertNil(result["result"])
    }
    func testWindowReuseDetectedByCooperativeGeneration() throws {
        let changed = change(try binding(),["window","instance_token"],.string("fixture-generation-2")); var calls = 0
        let result = ProofCoordinator().execute(request:try request(),environment:try environment(observations:[changed],performed:{calls += 1}))
        XCTAssertEqual(code(result),"WINDOW_ID_REUSED"); XCTAssertEqual(calls,0)
    }
    func testGenericABARefusesRequiredInstanceBeforeDispatch() throws {
        let b = try binding(), env = try environment(); var calls = 0
        let e = CoordinatorEnvironment(executor:env.executor,policySHA256:digest,bootID:boot,observe:{IdentityObservation(binding:b,assurance:["process-instance","window-observed"],policy:try self.policy())},perform:{calls += 1; return try env.perform()},clock:{100},wallClock:env.wallClock)
        let r = change(try request(),["required_assurance"],.array([.string("window-instance")]))
        XCTAssertEqual(code(ProofCoordinator().execute(request:r,environment:e)),"IDENTITY_UNPROVABLE"); XCTAssertEqual(calls,0)
    }
    func testAXElementReplacementRefuses() throws {
        let b = try binding(element:true), changed = change(b,["element","token"],.string(String(repeating:"b",count:32)))
        XCTAssertEqual(code(ProofCoordinator().execute(request:try request(operation:"press"),environment:try environment(observations:[changed],operation:"press"))),"AX_ELEMENT_REPLACED")
    }
    func testAXContextChangedRefuses() throws {
        let changed = change(try binding(element:true),["context_sha256"],.string(String(repeating:"c",count:64)))
        XCTAssertEqual(code(ProofCoordinator().execute(request:try request(operation:"ax"),environment:try environment(observations:[changed],operation:"ax"))),"AX_CONTEXT_MISMATCH")
    }
    func testAXMissingInstanceSupportRefuses() throws {
        let env = try environment(operation:"press"), b = try binding(element:true)
        let e = CoordinatorEnvironment(executor:env.executor,policySHA256:digest,bootID:boot,observe:{IdentityObservation(binding:b,assurance:["process-instance","window-observed","element-observed"],policy:try self.policy())},perform:env.perform,clock:env.clock,wallClock:env.wallClock)
        let r = change(try request(operation:"press"),["required_assurance"],.array([.string("element-instance")]))
        XCTAssertEqual(code(ProofCoordinator().execute(request:r,environment:e)),"AX_INSTANCE_UNPROVABLE")
    }
    func testProtectedRefusalBeforePrimitive() throws {
        var calls = 0
        let result = ProofCoordinator().execute(request:try request(),environment:try environment(observeError:IdentityFailure(code:"PROTECTED_APP_REFUSED"),performed:{calls += 1}))
        XCTAssertEqual(code(result),"PROTECTED_APP_REFUSED"); XCTAssertEqual(calls,0); XCTAssertNil(result["proof"])
    }
    func testWindowOwnerMismatch() throws {
        let changed = change(try binding(),["window","owner_pid"],.number(4243))
        XCTAssertEqual(code(ProofCoordinator().execute(request:try request(),environment:try environment(observations:[changed]))),"WINDOW_OWNER_MISMATCH")
    }
    func testSignatureChange() throws {
        let changed = change(try binding(),["process","app","signing","cdhash"],.string(String(repeating:"c",count:40)))
        XCTAssertEqual(code(ProofCoordinator().execute(request:try request(),environment:try environment(observations:[changed]))),"SIGNING_IDENTITY_MISMATCH")
    }
    func testExecutableChange() throws {
        let changed = change(try binding(),["process","app","executable_file","inode"],.string("3"))
        XCTAssertEqual(code(ProofCoordinator().execute(request:try request(),environment:try environment(observations:[changed]))),"EXECUTABLE_IDENTITY_MISMATCH")
    }
    func testFrameToleranceFrozen() throws {
        let b = try binding(), tolerated = change(b,["window","frame","x"],.number(0.5)), moved = change(b,["window","frame","x"],.number(0.51))
        XCTAssertEqual(ProofCoordinator().execute(request:try request(),environment:try environment(observations:[tolerated]))["ok"]?.bool,true)
        XCTAssertEqual(code(ProofCoordinator().execute(request:try request(),environment:try environment(observations:[moved]))),"WINDOW_FRAME_MISMATCH")
    }
    func testDisplayScaleHasZeroTolerance() throws {
        var b = try binding(); var displays = b["window"]!["displays"]!.array!
        displays[0] = change(displays[0],["scale"],.number(1)); b = change(b,["window","displays"],.array(displays))
        XCTAssertEqual(code(ProofCoordinator().execute(request:try request(),environment:try environment(observations:[b]))),"DISPLAY_BINDING_MISMATCH")
    }
    func testNonceReplayAndSequenceReplay() throws {
        let c = ProofCoordinator(), r = try request()
        XCTAssertEqual(c.execute(request:r,environment:try environment())["ok"]?.bool,true)
        XCTAssertEqual(code(c.execute(request:r,environment:try environment())),"REQUEST_REPLAYED")
        let nextNonce = Data(repeating:1,count:32).base64EncodedString().replacingOccurrences(of:"=",with:"")
        XCTAssertEqual(code(c.execute(request:change(r,["nonce"],.string(nextNonce)),environment:try environment())),"REQUEST_REPLAYED")
    }
    func testReplayCapacityNeverEvicts() throws {
        let c = ProofCoordinator(nonceCapacity:1), r = try request()
        _ = c.execute(request:r,environment:try environment())
        let next = change(change(r,["sequence"],.string("2")),["nonce"],.string(Data(repeating:1,count:32).base64EncodedString().replacingOccurrences(of:"=",with:"")))
        XCTAssertEqual(code(c.execute(request:next,environment:try environment())),"SESSION_INVALID")
    }
    func testExpiredDeadlineBeforePrimitive() throws {
        var calls = 0; let r = change(try request(),["deadline","continuous_ns"],.string("100"))
        XCTAssertEqual(code(ProofCoordinator().execute(request:r,environment:try environment(performed:{calls += 1}))),"REQUEST_EXPIRED"); XCTAssertEqual(calls,0)
    }
    func testCancellationAtBoundaryStopsPrimitive() throws {
        var checks = 0, calls = 0
        let env = try environment(permits:{ checks += 1; if checks == 3 { throw IdentityFailure(code:"CANCELLED") } },performed:{calls += 1})
        let r = ProofCoordinator().execute(request:try request(),environment:env)
        XCTAssertEqual(code(r),"CANCELLED"); XCTAssertEqual(calls,0)
    }
    func testCancellationAfterDispatchDiscardsPayload() throws {
        var checks = 0
        let env = try environment(permits:{ checks += 1; if checks == 4 { throw IdentityFailure(code:"CANCELLED") } })
        let r = ProofCoordinator().execute(request:try request(operation:"press"),environment:try actionEnvironment(cancels:env.checkPermit))
        XCTAssertEqual(code(r),"CANCELLED"); XCTAssertEqual(r["side_effects_possible"]?.bool,true); XCTAssertNil(r["result"])
    }
    func actionEnvironment(cancels:@escaping () throws -> Void) throws -> CoordinatorEnvironment { try environment(operation:"press",permits:cancels) }
    func testConsumerCannotSelfAdmit() throws {
        let r = change(try request(),["profile"],.string("xyzstudio"))
        XCTAssertEqual(code(ProofCoordinator().execute(request:r,environment:try environment())),"SESSION_INVALID")
    }
    func testUnknownFieldRejectedAndNonceEchoed() throws {
        var o = try request().object!; o["allow_global"] = .bool(true)
        let r = ProofCoordinator().execute(request:.object(o),environment:try environment())
        XCTAssertEqual(code(r),"INVALID_REQUEST"); XCTAssertEqual(r["nonce"]?.string,String(repeating:"A",count:43))
    }
    func testWrongOperationArgumentShapeRefused() throws {
        let r = change(try request(),["arguments"],try json(["action":"AXPress"]))
        XCTAssertEqual(code(ProofCoordinator().execute(request:r,environment:try environment())),"INVALID_REQUEST")
    }
    func testInvalidNonceNotEchoed() throws {
        let r = change(try request(),["nonce"],.string(String(repeating:"A",count:42)+"B"))
        let result = ProofCoordinator().execute(request:r,environment:try environment())
        XCTAssertEqual(code(result),"INVALID_REQUEST"); XCTAssertEqual(result["nonce"],.null)
    }
    func testCounterOverflowRejected() throws {
        let r = change(try request(),["sequence"],.string("18446744073709551616"))
        XCTAssertEqual(code(ProofCoordinator().execute(request:r,environment:try environment())),"INVALID_REQUEST")
    }
    func testDuplicateKeysEscapesAndInvalidJSON() throws {
        for raw in [#"{"a":1,"\u0061":2}"#, #"{"x":{"a":1,"a":2}}"#] {
            XCTAssertThrowsError(try JSONValue.parse(Data(raw.utf8))) { XCTAssertEqual(($0 as? IdentityFailure)?.code,"DUPLICATE_JSON_KEY") }
        }
        for raw in [#"{"x":NaN}"#, #"{"x":01}"#, #"{"x":true,}"#, #""\ud800""#, #"[1e999]"#, #"[9007199254740992]"#, #""\udc00""#] { XCTAssertThrowsError(try JSONValue.parse(Data(raw.utf8)),raw) }
    }
    func testParserBoundsAndCanonicalUnicode() throws {
        XCTAssertThrowsError(try JSONValue.parse(Data("[]".utf8),maximumBytes:1))
        XCTAssertThrowsError(try JSONValue.parse(Data("[[[]]]".utf8),maximumDepth:1))
        let v = try JSONValue.parse(Data(#"{"z":1e+15,"a":"x\/y","x":1e-6}"#.utf8))
        XCTAssertEqual(v.canonicalString,#"{"a":"x/y","x":0.000001,"z":1000000000000000}"#)
        XCTAssertEqual(try JSONValue.parse(Data(#""\ud83d\ude00""#.utf8)),.string("😀"))
    }
    func testCanonicalEquivalentUnicodeStringsRemainDistinctIdentity() throws {
        XCTAssertNotEqual(JSONValue.string("\u{e9}"), JSONValue.string("e\u{301}"))
        let a = try JSONValue.parse(Data(#"{"path":"/tmp/é.app"}"#.utf8))
        let b = try JSONValue.parse(Data(#"{"path":"/tmp/e\u0301.app"}"#.utf8))
        XCTAssertNotEqual(a,b)
        XCTAssertNotEqual(a.canonicalData(),b.canonicalData())
    }
    func testPostcheckCannotAccumulateFrameTolerance() throws {
        let b = try binding(), pre = change(b,["window","frame","x"],.number(0.5)), post = change(b,["window","frame","x"],.number(1))
        let result = ProofCoordinator().execute(request:try request(),environment:try environment(observations:[pre,pre,post]))
        XCTAssertEqual(code(result),"WINDOW_FRAME_MISMATCH"); XCTAssertEqual(result["phase"]?.string,"postcheck"); XCTAssertNil(result["result"])
    }
    func testPostActionMismatchReportsPossibleEffectsWithoutReceipt() throws {
        let b = try binding(element:true), post = change(b,["window","instance_token"],.string("replaced"))
        let result = ProofCoordinator().execute(request:try request(operation:"press"),environment:try environment(observations:[b,b,post],operation:"press"))
        XCTAssertEqual(code(result),"WINDOW_ID_REUSED"); XCTAssertEqual(result["side_effects_possible"]?.bool,true)
        XCTAssertEqual(result["retryable"]?.bool,false); XCTAssertNil(result["proof"]); XCTAssertNil(result["result"])
    }
    func testNestedUnknownFieldsRejected() throws {
        var expected = try binding(), signing = expected["process"]!["app"]!["signing"]!.object!
        signing["trust_me"] = .bool(true); expected = change(expected,["process","app","signing"],.object(signing))
        let result = ProofCoordinator().execute(request:try request(expected:expected),environment:try environment())
        XCTAssertEqual(code(result),"INVALID_REQUEST"); XCTAssertEqual(result["phase"]?.string,"parse")
    }
    func testMissingSourceTimestampExplicitlyLimited() throws {
        let env = try environment()
        let noSource = CoordinatorEnvironment(executor:env.executor,policySHA256:digest,bootID:boot,observe:env.observe,perform:{
            IdentityPayload(data:Data("image".utf8),kind:"image",mediaType:"image/png",route:"sck-window-screenshot",pixelSHA256:self.digest,pixelWidth:500,pixelHeight:300)
        },clock:env.clock,wallClock:env.wallClock)
        let result = ProofCoordinator().execute(request:try request(),environment:noSource)
        XCTAssertEqual(result["ok"]?.bool,true,result.canonicalString)
        XCTAssertEqual(result["proof"]?["timing"]?["source_frame_continuous_ns"],.null)
        XCTAssertTrue(result["proof"]?["limitations"]?.array?.contains(.string("source-frame-time-unavailable-no-freshness-guarantee")) ?? false)
    }
    func testStaleSourceTimestampDiscardsImage() throws {
        let env = try environment()
        let stale = CoordinatorEnvironment(executor:env.executor,policySHA256:digest,bootID:boot,observe:env.observe,perform:{
            IdentityPayload(data:Data("image".utf8),kind:"image",mediaType:"image/png",route:"sck-window-screenshot",pixelSHA256:self.digest,pixelWidth:500,pixelHeight:300,sourceFrameContinuousNS:99)
        },clock:env.clock,wallClock:env.wallClock)
        let result = ProofCoordinator().execute(request:try request(),environment:stale)
        XCTAssertEqual(code(result),"CAPTURE_FRAME_STALE"); XCTAssertNil(result["result"])
    }
    func testMacCannotEnableUnauthenticatedIntegrity() throws {
        let r = change(try request(),["mac"],try json(["algorithm":"hmac-sha256","key_id":token,"tag":digest]))
        XCTAssertEqual(code(ProofCoordinator().execute(request:r,environment:try environment())),"PROOF_CAPABILITY_UNSUPPORTED")
    }
    func testSetTextRequiresFrozenPreconditionBeforeDispatch() throws {
        var r = try request(operation:"press")
        r = change(r,["operation"],.string("set-text"))
        r = change(r,["arguments"],try json(["text":"fixture","precondition_sha256":String(repeating:"c",count:64),"postcondition_sha256":digest]))
        var calls = 0
        XCTAssertEqual(code(ProofCoordinator().execute(request:r,environment:try environment(operation:"press",performed:{calls += 1}))),"AX_CONTEXT_MISMATCH")
        XCTAssertEqual(calls,0)
    }

}
