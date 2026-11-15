import XCTest
@testable import IdentityProof

/// Deterministic fakes only: no applications, desktop APIs, TCC prompts or events.
final class PracticalCaptureTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private let otherDigest = String(repeating: "c", count: 64)
    private let boot = "12345678-1234-1234-1234-123456789abc"
    private let nonce = String(repeating: "A", count: 43)
    private let image = Data([0, 1, 2, 3, 0xff, 0x80, 10])

    private func json(_ value: Any) throws -> JSONValue { try JSONValue(any: value) }
    private func change(_ value: JSONValue, _ path: [String], _ replacement: JSONValue) -> JSONValue {
        guard let first = path.first else { return replacement }
        var object = value.object!
        object[first] = change(object[first]!, Array(path.dropFirst()), replacement)
        return .object(object)
    }
    private func binding() throws -> JSONValue {
        let requirement = "identifier com.xyztech.practical-fixture"
        return try json([
            "process": ["boot_id": boot, "pid": 4242, "uid": 501,
                "start_time": ["seconds": "1700000000", "microseconds": 123456],
                "app": ["bundle_id": "com.xyztech.practical-fixture", "bundle_path": "/tmp/PracticalFixture.app",
                    "executable_path": "/tmp/PracticalFixture.app/Contents/MacOS/Fixture",
                    "executable_file": ["device": "1", "inode": "2", "sha256": digest],
                    "signing": ["kind": "adhoc_fixture", "valid": true, "team_id": NSNull(),
                        "signing_identifier": "com.xyztech.practical-fixture", "cdhash": String(repeating: "b", count: 40),
                        "cdhash_algorithm": "sha256_truncated", "architecture": "arm64",
                        "designated_requirement": requirement, "requirement_sha256": JSONValue.sha256(Data(requirement.utf8))]]],
            "window": ["window_id": 42, "owner_pid": 4242, "layer": 0,
                "frame": ["x": 20, "y": 30, "width": 500, "height": 300], "on_screen": true]
        ])
    }
    private func request(expected: JSONValue? = nil) throws -> JSONValue {
        .object(["schema_version": .number(1), "nonce": .string(nonce), "expected": try expected ?? binding(),
                 "format": .string("png"), "max_pixel_edge": .number(1024)])
    }
    private func environment(observations: [JSONValue]? = nil,
                             policy: @escaping (JSONValue) throws -> Void = { _ in },
                             payload: IdentityPayload? = nil,
                             observed: @escaping () -> Void = {}, performed: @escaping () -> Void = {}) throws -> PracticalCaptureEnvironment {
        let snapshots = try observations ?? [binding()]
        var index = 0, time: UInt64 = 100
        let defaultPayload = IdentityPayload(data: image, kind: "image", mediaType: "image/png", route: "sck-window-screenshot",
            pixelSHA256: digest, pixelWidth: 500, pixelHeight: 300)
        return PracticalCaptureEnvironment(observe: {
            observed()
            let value = snapshots[min(index, snapshots.count - 1)]; index += 1
            return value
        }, checkPolicy: policy, perform: {
            performed(); return payload ?? defaultPayload
        }, clock: { time += 1; return time }, wallClock: { "2026-11-15T00:00:00Z" })
    }
    private func assertNoPayload(_ result: JSONValue, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result["ok"]?.bool, false, result.canonicalString, file: file, line: line)
        XCTAssertNil(result["result"], file: file, line: line)
        XCTAssertNil(result["proof"], file: file, line: line)
        XCTAssertEqual(result["side_effects_possible"]?.bool, false, file: file, line: line)
    }

    /// Both components of the start time, every executable identity field and
    /// every signer field are independent pins, not interchangeable descriptors.
    private func processMutations(_ base: JSONValue) -> [(String, JSONValue, String)] {
        var cases: [(String, JSONValue, String)] = []
        func add(_ path: [String], _ replacement: JSONValue, _ code: String) {
            cases.append((path.joined(separator: "."), change(base, path, replacement), code))
        }
        add(["process", "boot_id"], .string("22345678-1234-1234-1234-123456789abc"), "BOOT_MISMATCH")
        var pid = change(base, ["process", "pid"], .number(4243))
        pid = change(pid, ["window", "owner_pid"], .number(4243))
        cases.append(("process.pid", pid, "PROCESS_IDENTITY_MISMATCH"))
        add(["process", "uid"], .number(502), "PROCESS_UID_MISMATCH")
        add(["process", "start_time", "seconds"], .string("1700000001"), "PID_REUSED")
        add(["process", "start_time", "microseconds"], .number(123457), "PID_REUSED")
        add(["process", "app", "bundle_id"], .string("com.xyztech.changed"), "BUNDLE_ID_MISMATCH")
        add(["process", "app", "bundle_path"], .string("/tmp/Changed.app"), "EXECUTABLE_IDENTITY_MISMATCH")
        add(["process", "app", "executable_path"], .string("/tmp/PracticalFixture.app/Contents/MacOS/Other"), "EXECUTABLE_IDENTITY_MISMATCH")
        for (key, replacement) in [("device", JSONValue.string("3")), ("inode", .string("4")), ("sha256", .string(otherDigest))] {
            add(["process", "app", "executable_file", key], replacement, "EXECUTABLE_IDENTITY_MISMATCH")
        }
        for (key, replacement) in [("kind", JSONValue.string("apple_platform")), ("valid", .bool(false)), ("team_id", .string("OTHERTEAM")),
                ("signing_identifier", .string("com.xyztech.other")), ("cdhash", .string(String(repeating: "c", count: 40))),
                ("cdhash_algorithm", .string("sha1")), ("architecture", .string("x86_64"))] {
            add(["process", "app", "signing", key], replacement, "SIGNING_IDENTITY_MISMATCH")
        }
        let requirement = "identifier com.xyztech.changed"
        var signer = change(base, ["process", "app", "signing", "designated_requirement"], .string(requirement))
        signer = change(signer, ["process", "app", "signing", "requirement_sha256"], .string(JSONValue.sha256(Data(requirement.utf8))))
        cases.append(("process.app.signing.designated_requirement+requirement_sha256", signer, "SIGNING_IDENTITY_MISMATCH"))
        add(["process", "app", "signing", "requirement_sha256"], .string(otherDigest), "SIGNING_IDENTITY_MISMATCH")
        return cases
    }
    private func windowMutations(_ base: JSONValue) -> [(String, JSONValue, String)] {
        var cases: [(String, JSONValue, String)] = []
        func add(_ path: [String], _ replacement: JSONValue, _ code: String) {
            cases.append((path.joined(separator: "."), change(base, path, replacement), code))
        }
        add(["window", "window_id"], .number(43), "WINDOW_ID_REUSED")
        add(["window", "owner_pid"], .number(4243), "WINDOW_OWNER_MISMATCH")
        add(["window", "layer"], .number(1), "WINDOW_LAYER_MISMATCH")
        for (key, replacement) in [("x", 20.001), ("y", 30.001), ("width", 500.001), ("height", 300.001)] {
            add(["window", "frame", key], .number(replacement), "WINDOW_FRAME_MISMATCH")
        }
        add(["window", "on_screen"], .bool(false), "WINDOW_NOT_FOUND")
        return cases
    }
    private func assertMutations(_ cases: [(String, JSONValue, String)], stage: Int) throws {
        let base = try binding()
        for (field, mutation, code) in cases {
            var snapshots = [base, base, base]; snapshots[stage] = mutation
            var calls = 0
            let result = PracticalCaptureCoordinator.execute(request: try request(),
                environment: try environment(observations: snapshots, performed: { calls += 1 }))
            XCTAssertEqual(result["code"]?.string, code, "stage \(stage), \(field): \(result.canonicalString)")
            XCTAssertEqual(calls, stage == 2 ? 1 : 0, "stage \(stage), \(field)")
            XCTAssertEqual(result["dispatch_state"]?.string, stage == 2 ? "dispatched" : "not_dispatched")
            XCTAssertEqual(result["nonce"]?.string, nonce)
            assertNoPayload(result)
        }
    }
    func testEveryProcessFieldMismatchAtFirstPrecheck() throws { try assertMutations(processMutations(try binding()), stage: 0) }
    func testEveryProcessFieldMismatchAtDispatchPrecheck() throws { try assertMutations(processMutations(try binding()), stage: 1) }
    func testEveryProcessFieldMismatchAfterCaptureDiscardsPixels() throws { try assertMutations(processMutations(try binding()), stage: 2) }
    func testEveryWindowFieldMismatchAtFirstPrecheck() throws { try assertMutations(windowMutations(try binding()), stage: 0) }
    func testEveryWindowFieldMismatchAtDispatchPrecheck() throws { try assertMutations(windowMutations(try binding()), stage: 1) }
    func testEveryWindowFieldMismatchAfterCaptureDiscardsPixels() throws { try assertMutations(windowMutations(try binding()), stage: 2) }

    func testEncodedImageHashIsPlainSHA256OfReturnedBytes() throws {
        let expected = try binding()
        let result = PracticalCaptureCoordinator.execute(request: try request(), environment: try environment())
        XCTAssertEqual(result["ok"]?.bool, true, result.canonicalString)
        let proof = try XCTUnwrap(result["proof"])
        XCTAssertEqual(proof["schema_version"]?.number, 1)
        XCTAssertEqual(proof["assurance"]?.string, "practical")
        XCTAssertEqual(proof["nonce"]?.string, nonce)
        XCTAssertEqual(proof["observed_pre"], expected)
        XCTAssertEqual(proof["observed_post"], expected)
        XCTAssertEqual(result["result"]?["encoding"]?.string, "base64")
        let encoded = try XCTUnwrap(result["result"]?["data"]?.string)
        let returned = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertEqual(returned, image)
        XCTAssertEqual(proof["image"]?["sha256"]?.string, JSONValue.sha256(returned))
        // Independently computed known vector for the seven fixture bytes.
        XCTAssertEqual(proof["image"]?["sha256"]?.string, "75e2c6d85d1fe1f17c49145ad21711a240c52f52fd7bcd3c63f416e51dfc116e")
        XCTAssertNotEqual(proof["image"]?["sha256"]?.string, JSONValue.sha256(returned, domain: "XYZLCU/PAYLOAD/1\0"))
        XCTAssertEqual(proof["image"]?["raw_pixel_sha256"]?.string, digest)
        XCTAssertEqual(proof["image"]?["pixel_width"]?.number, 500)
        XCTAssertEqual(proof["image"]?["pixel_height"]?.number, 300)
        XCTAssertFalse(proof["limitations"]?.array?.isEmpty ?? true)
        XCTAssertNotNil(proof["timing"])
    }
    func testProtectedExpectedRefusalDoesNotObserveOrCapture() throws {
        var observations = 0, captures = 0
        let result = PracticalCaptureCoordinator.execute(request: try request(), environment: try environment(
            policy: { _ in throw IdentityFailure(code: "PROTECTED_APP_REFUSED") },
            observed: { observations += 1 }, performed: { captures += 1 }))
        XCTAssertEqual(result["code"]?.string, "PROTECTED_APP_REFUSED")
        XCTAssertEqual(observations, 0); XCTAssertEqual(captures, 0); assertNoPayload(result)
    }
    func testProtectedObservedRefusalAtEachBoundary() throws {
        for denyCheck in 2...4 {
            var checks = 0, captures = 0
            let result = PracticalCaptureCoordinator.execute(request: try request(), environment: try environment(
                policy: { _ in checks += 1; if checks == denyCheck { throw IdentityFailure(code: "PROTECTED_IDENTITY_SUSPICIOUS") } },
                performed: { captures += 1 }))
            XCTAssertEqual(result["code"]?.string, "PROTECTED_IDENTITY_SUSPICIOUS", result.canonicalString)
            XCTAssertEqual(captures, denyCheck == 4 ? 1 : 0)
            assertNoPayload(result)
        }
    }
    func testProtectedBuiltinPolicyStillDenies() throws {
        let policy = try ProtectedAppPolicy()
        var b = try binding()
        b = change(b, ["process", "app", "bundle_id"], .string("com.1password.1password"))
        var calls = 0
        let result = PracticalCaptureCoordinator.execute(request: try request(expected: b), environment: try environment(
            observations: [b], policy: { binding in
                let app = binding["process"]!["app"]!
                let verdict = policy.evaluate(bundleID: app["bundle_id"]!.string!, teamID: nil,
                    signingID: app["signing"]?["signing_identifier"]?.string, validSignature: true)
                if let code = verdict.code { throw IdentityFailure(code: code) }
            }, performed: { calls += 1 }))
        XCTAssertEqual(result["code"]?.string, "PROTECTED_IDENTITY_SUSPICIOUS")
        XCTAssertEqual(calls, 0); assertNoPayload(result)
    }
    func testInvalidSignerNeverReachesCapture() throws {
        let invalid = change(try binding(), ["process", "app", "signing", "valid"], .bool(false))
        var calls = 0
        let result = PracticalCaptureCoordinator.execute(request: try request(), environment: try environment(observations: [invalid], performed: { calls += 1 }))
        XCTAssertEqual(result["ok"]?.bool, false); XCTAssertEqual(calls, 0); assertNoPayload(result)
    }
    func testClosedRequestRejectsOperationAndAssuranceDowngradeFields() throws {
        for (key, value) in [("operation", JSONValue.string("ax")), ("assurance", .string("practical")),
                ("allow_global", .bool(true)), ("frame_tolerance_pt", .number(1))] {
            var object = try request().object!; object[key] = value
            var calls = 0
            let result = PracticalCaptureCoordinator.execute(request: .object(object), environment: try environment(performed: { calls += 1 }))
            XCTAssertEqual(result["code"]?.string, "INVALID_REQUEST", key)
            XCTAssertEqual(calls, 0); assertNoPayload(result)
        }
    }
    func testPracticalRequestDoesNotAdmitStrictCoordinator() throws {
        let strict = IdentityProofTests()
        var calls = 0
        let result = ProofCoordinator().execute(request: try request(), environment: try strict.environment(performed: { calls += 1 }))
        XCTAssertEqual(result["code"]?.string, "INVALID_REQUEST"); XCTAssertEqual(calls, 0); assertNoPayload(result)
    }
    func testStrictRequestAndProofContractRemainUnchanged() throws {
        let strict = IdentityProofTests()
        let result = ProofCoordinator().execute(request: try strict.request(), environment: try strict.environment())
        XCTAssertEqual(result["ok"]?.bool, true, result.canonicalString)
        XCTAssertNotNil(result["proof"]?["assurance"]?.array)
        XCTAssertNil(result["proof"]?["assurance"]?.string)
        try ProofSchema.validate(result, definition: "Success")
    }
    func testPracticalCannotAcceptStrictAXOrActionRequests() throws {
        let strict = IdentityProofTests()
        for operation in ["ax", "press", "set-text", "click", "open-app"] {
            var object = try request().object!; object["operation"] = .string(operation)
            var calls = 0
            let result = PracticalCaptureCoordinator.execute(request: .object(object), environment: try environment(performed: { calls += 1 }))
            XCTAssertEqual(result["code"]?.string, "INVALID_REQUEST", operation)
            XCTAssertEqual(calls, 0); assertNoPayload(result)
        }
        var calls = 0
        let result = PracticalCaptureCoordinator.execute(request: try strict.request(operation: "ax"), environment: try environment(performed: { calls += 1 }))
        XCTAssertEqual(result["code"]?.string, "INVALID_REQUEST"); XCTAssertEqual(calls, 0)
    }
    func testMalformedExpectedBindingRefusesBeforeAnyObservation() throws {
        let base = try binding()
        var cases = [
            change(base, ["window", "owner_pid"], .number(99)),
            change(base, ["window", "layer"], .number(1)),
            change(base, ["window", "on_screen"], .bool(false)),
            change(base, ["process", "start_time", "seconds"], .string("0")),
            change(base, ["process", "start_time", "seconds"], .string("18446744073709551616")),
            change(base, ["process", "app", "executable_path"], .string("/tmp/Other.app/Contents/MacOS/Fixture")),
            change(base, ["process", "app", "signing", "valid"], .bool(false))
        ]
        var unknown = base.object!; unknown["trust_me"] = .bool(true); cases.append(.object(unknown))
        for expected in cases {
            var observations = 0, captures = 0
            let result = PracticalCaptureCoordinator.execute(request: try request(expected: expected), environment: try environment(
                observed: { observations += 1 }, performed: { captures += 1 }))
            XCTAssertEqual(observations, 0); XCTAssertEqual(captures, 0); assertNoPayload(result)
        }
    }
    func testRequestBoundsAndNonCanonicalNonceRefuseBeforeCapture() throws {
        let base = try request()
        let cases = [
            change(base, ["schema_version"], .number(2)),
            change(base, ["nonce"], .string(String(repeating: "A", count: 42) + "B")),
            change(base, ["format"], .string("tiff")),
            change(base, ["max_pixel_edge"], .number(0)),
            change(base, ["max_pixel_edge"], .number(4097)),
            change(base, ["max_pixel_edge"], .number(200.5))
        ]
        for request in cases {
            var calls = 0
            let result = PracticalCaptureCoordinator.execute(request: request, environment: try environment(performed: { calls += 1 }))
            XCTAssertEqual(result["code"]?.string, "INVALID_REQUEST"); XCTAssertEqual(calls, 0); assertNoPayload(result)
        }
    }
    func testInvalidPayloadNeverPublishesBytes() throws {
        let cases = [
            IdentityPayload(data: Data(), kind: "image", mediaType: "image/png", route: "sck-window-screenshot", pixelWidth: 500, pixelHeight: 300),
            IdentityPayload(data: image, kind: "image", mediaType: "image/jpeg", route: "sck-window-screenshot", pixelWidth: 500, pixelHeight: 300),
            IdentityPayload(data: image, kind: "image", mediaType: "image/png", route: "sck-window-stream-once", pixelWidth: 500, pixelHeight: 300),
            IdentityPayload(data: image, kind: "image", mediaType: "image/png", route: "sck-window-screenshot", pixelWidth: 1025, pixelHeight: 300),
            IdentityPayload(data: image, kind: "image", mediaType: "image/png", route: "sck-window-screenshot", pixelWidth: 0, pixelHeight: 300),
            IdentityPayload(data: image, kind: "image", mediaType: "image/png", route: "sck-window-screenshot", pixelWidth: 500)
        ]
        for payload in cases {
            let result = PracticalCaptureCoordinator.execute(request: try request(), environment: try environment(payload: payload))
            XCTAssertEqual(result["code"]?.string, "CAPTURE_SOURCE_UNPROVABLE"); assertNoPayload(result)
        }
    }
    func testMalformedObservedBindingAtEveryBoundaryDiscardsPixels() throws {
        let base = try binding()
        var malformed = base.object!; malformed["surprise"] = .string("unknown")
        for stage in 0...2 {
            var observations = [base, base, base]; observations[stage] = .object(malformed)
            var calls = 0
            let result = PracticalCaptureCoordinator.execute(request: try request(), environment: try environment(
                observations: observations, performed: { calls += 1 }))
            XCTAssertEqual(calls, stage == 2 ? 1 : 0); assertNoPayload(result)
        }
    }

    func testNativeAdhocDiagnosticBindingIsAcceptedAndPreservedInProof() throws {
        let native = change(try binding(), ["process", "app", "signing", "kind"], .string("adhoc_diagnostic"))
        try PracticalCaptureCoordinator.validateBinding(native)
        var captures = 0
        let result = PracticalCaptureCoordinator.execute(request: try request(expected: native), environment: try environment(
            observations: [native], performed: { captures += 1 }))
        XCTAssertEqual(result["ok"]?.bool, true, result.canonicalString)
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(result["proof"]?["observed_pre"], native)
        XCTAssertEqual(result["proof"]?["observed_post"], native)
        for key in ["observed_pre", "observed_post"] {
            XCTAssertEqual(result["proof"]?[key]?["process"]?["app"]?["signing"]?["kind"]?.string, "adhoc_diagnostic")
        }
        XCTAssertEqual(native["process"]?["app"]?["signing"]?["kind"]?.string, "adhoc_diagnostic")
    }
    func testNativeAdhocDiagnosticKindDoesNotWidenStrictProcessSchema() throws {
        let fixtureProcess = try binding()["process"]!
        try ProofSchema.validate(fixtureProcess, definition: "Process")
        let nativeProcess = change(fixtureProcess, ["app", "signing", "kind"], .string("adhoc_diagnostic"))
        XCTAssertThrowsError(try ProofSchema.validate(nativeProcess, definition: "Process")) { error in
            XCTAssertEqual((error as? IdentityFailure)?.code, "INVALID_REQUEST")
        }
        let unknown = change(try binding(), ["process", "app", "signing", "kind"], .string("adhoc_unknown"))
        XCTAssertThrowsError(try PracticalCaptureCoordinator.validateBinding(unknown))
    }
    func testNativeAdhocAdapterCannotHideSigningKindChangeAtAnyBoundary() throws {
        let fixture = try binding()
        let native = change(fixture, ["process", "app", "signing", "kind"], .string("adhoc_diagnostic"))
        for (expected, changed) in [(native, fixture), (fixture, native)] {
            for stage in 0...2 {
                var observations = [expected, expected, expected]; observations[stage] = changed
                var captures = 0
                let result = PracticalCaptureCoordinator.execute(request: try request(expected: expected), environment: try environment(
                    observations: observations, performed: { captures += 1 }))
                XCTAssertEqual(result["code"]?.string, "SIGNING_IDENTITY_MISMATCH", result.canonicalString)
                XCTAssertEqual(captures, stage == 2 ? 1 : 0)
                assertNoPayload(result)
            }
        }
    }

    func testPrivateVarRealPathsRemainValidWithoutFoundationAliasRewrite() throws {
        let native = try binding()
        var expected = change(native, ["process", "app", "bundle_path"], .string("/private/var/folders/owned/Fixture.app"))
        expected = change(expected, ["process", "app", "executable_path"], .string("/private/var/folders/owned/Fixture.app/Contents/MacOS/Fixture"))
        try PracticalCaptureCoordinator.validateBinding(expected)
        let result = PracticalCaptureCoordinator.execute(request: try request(expected: expected), environment: try environment(observations: [expected]))
        XCTAssertEqual(result["ok"]?.bool, true, result.canonicalString)
        XCTAssertEqual(result["proof"]?["observed_pre"], expected)
    }
    func testAbsoluteLexicalPathRejectsEmptyOrDotComponents() throws {
        XCTAssertTrue(PracticalCaptureCoordinator.isAbsoluteLexicalPath("/private/var/folders/owned"))
        XCTAssertTrue(PracticalCaptureCoordinator.isAbsoluteLexicalPath("/Users/owner/Private Capture"))
        for path in ["/a//b", "/a/../b", "/a/./b", "/a/", "relative", "/", "", "/a\0b"] {
            XCTAssertFalse(PracticalCaptureCoordinator.isAbsoluteLexicalPath(path), path)
        }
    }

}
