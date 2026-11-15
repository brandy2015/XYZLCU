import XCTest
@testable import IdentityProof

final class ProtectedPolicyTests: XCTestCase {
    func overlay(revision:String = "1", rules:[[String:Any]] = [], extra: [String:Any] = [:]) throws -> Data {
        var object: [String:Any] = ["schema_version":1,"revision":revision,"additions":rules,"allow_builtin_removals":false,"removed_builtin_rule_ids":[]]
        object.merge(extra) { _, rhs in rhs }
        return try JSONValue(any:object).canonicalData()
    }
    func state(_ overlay:Data, revision:String = "1") throws -> Data {
        try JSONValue(any:["schema_version":1,"revision":revision,"overlay_sha256":JSONValue.sha256(overlay)]).canonicalData()
    }
    func rule(pattern:String = "com.example.bank.*") -> [String:Any] {
        ["rule_id":"bank","category":"banking_payment","bundle_id_pattern":pattern,"team_id":"BANKTEAM","designated_requirement":"anchor apple generic and certificate leaf[subject.OU] = BANKTEAM","signing_identifiers":["com.example.bank.client"]]
    }
    func testBuiltinProtectedAndSuspicious() throws {
        let p = try ProtectedAppPolicy()
        for seed in ProtectedAppPolicy.builtins {
            XCTAssertEqual(p.evaluate(bundleID:seed,teamID:"UNREVIEWED",signingID:seed,validSignature:true).decision,"deny",seed)
            XCTAssertEqual(p.evaluate(bundleID:seed,teamID:nil,signingID:nil,validSignature:false).code,"PROTECTED_IDENTITY_SUSPICIOUS",seed)
        }
        XCTAssertEqual(p.evaluate(bundleID:"com.apple.Terminal",teamID:nil,signingID:"com.apple.Terminal",validSignature:true,appleAnchor:true).code,"PROTECTED_APP_REFUSED")
        XCTAssertEqual(p.evaluate(bundleID:"com.apple.Terminal",teamID:"SPOOF",signingID:"com.apple.Terminal",validSignature:true).code,"PROTECTED_IDENTITY_SUSPICIOUS")
        XCTAssertEqual(p.evaluate(bundleID:"com.1password.1password",teamID:"UNREVIEWED",signingID:"com.1password.1password",validSignature:true).decision,"deny")
    }
    func testUnknownValidAllowedAndInvalidRefused() throws {
        let p = try ProtectedAppPolicy()
        XCTAssertEqual(p.evaluate(bundleID:"com.xyztech.fixture",teamID:nil,signingID:"fixture",validSignature:true).decision,"allow")
        XCTAssertEqual(p.evaluate(bundleID:"com.xyztech.fixture",teamID:nil,signingID:"fixture",validSignature:false).code,"SIGNATURE_INVALID")
    }
    func testProtectedIdentityIndependentOfBundleDisplayName() throws {
        // Evaluator intentionally has no app-name/path/title argument: renaming
        // an installation cannot change the verified bundle identity verdict.
        let p = try ProtectedAppPolicy()
        for _ in ["Harmless Notes.app","Terminal.app"] {
            XCTAssertEqual(p.evaluate(bundleID:"com.apple.Terminal",teamID:nil,signingID:"com.apple.Terminal",validSignature:true,appleAnchor:true).decision,"deny")
        }
    }
    func testOverlayRequiresContinuityAndDetectsMissingOverlay() throws {
        let o = try overlay()
        XCTAssertThrowsError(try ProtectedAppPolicy(overlay:o))
        XCTAssertThrowsError(try ProtectedAppPolicy(continuity:state(o)))
        XCTAssertNoThrow(try ProtectedAppPolicy(overlay:o,continuity:state(o)))
    }
    func testRevisionRollbackAndAlteredContentRefused() throws {
        let first = try overlay(), second = try overlay(revision:"2")
        XCTAssertThrowsError(try ProtectedAppPolicy(overlay:first,continuity:state(second,revision:"2")))
        let altered = try overlay(rules:[rule()])
        XCTAssertThrowsError(try ProtectedAppPolicy(overlay:altered,continuity:state(first)))
    }
    func testStrictPolicySchemaAndPatterns() throws {
        for o in [try overlay(extra:["unsafe":true]),try overlay(revision:"01"),try overlay(rules:[rule(pattern:"com.*.bank")]),try overlay(rules:[rule(pattern:".*")]),try overlay(rules:[rule(),rule()])] {
            XCTAssertThrowsError(try ProtectedAppPolicy(overlay:o,continuity:state(o)))
        }
    }
    func testOwnerPatternAddsDenialOnlyWithinExactNamespace() throws {
        let o = try overlay(rules:[rule()]), p = try ProtectedAppPolicy(overlay:o,continuity:state(o))
        XCTAssertEqual(p.evaluate(bundleID:"com.example.bank.client",teamID:"BANKTEAM",signingID:"com.example.bank.client",validSignature:true).decision,"deny")
        XCTAssertEqual(p.evaluate(bundleID:"com.example.bank.client",teamID:"OTHER",signingID:"com.example.bank.client",validSignature:true).code,"PROTECTED_IDENTITY_SUSPICIOUS")
        XCTAssertEqual(p.evaluate(bundleID:"com.example.bankevil.client",teamID:"BANKTEAM",signingID:"com.example.bank.client",validSignature:true).decision,"allow")
    }
    func testBuiltinRemovalRequiresExplicitFlagAndExactRule() throws {
        let forbidden = try overlay(extra:["removed_builtin_rule_ids":["com.apple.Terminal"]])
        XCTAssertThrowsError(try ProtectedAppPolicy(overlay:forbidden,continuity:state(forbidden)))
        let explicit = try overlay(extra:["allow_builtin_removals":true,"removed_builtin_rule_ids":["com.apple.Terminal"]])
        let p = try ProtectedAppPolicy(overlay:explicit,continuity:state(explicit))
        XCTAssertEqual(p.removals,["com.apple.Terminal"])
    }
}

import Darwin

extension ProtectedPolicyTests {
    func withPolicyDirectory(_ body: (URL, Int32) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xyzlcu-policy-test-" + UUID().uuidString, isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:directory) }
        XCTAssertEqual(chmod(directory.path,0o700),0)
        let fd = open(directory.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(fd,0); guard fd >= 0 else { return }
        defer { close(fd) }
        try body(directory,fd)
    }
    func writePolicyFiles(_ directory:URL) throws {
        let data = try overlay()
        let files = [("protected-apps.v1.json",data),("protected-apps.state.v1.json",try state(data))]
        for (name,contents) in files {
            let file = directory.appendingPathComponent(name)
            try contents.write(to:file)
            XCTAssertEqual(chmod(file.path,0o600),0)
        }
    }
    func assertPolicyFailure(_ expected:String, _ action:() throws -> Void, file:StaticString = #filePath, line:UInt = #line) {
        XCTAssertThrowsError(try action(),file:file,line:line) { error in
            XCTAssertEqual((error as? IdentityFailure)?.code,expected,file:file,line:line)
        }
    }
    func testFilesystemPrivateDirectoryAnd0600FilesAccepted() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory)
            XCTAssertEqual(try ProtectedAppPolicy.loadDirectory(fd).revision,"1")
        }
    }
    func testFilesystemWorldReadablePolicyRefused() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory)
            XCTAssertEqual(chmod(directory.appendingPathComponent("protected-apps.v1.json").path,0o644),0)
            assertPolicyFailure("POLICY_PERMISSION_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd) }
        }
    }
    func testFilesystemWorldReadableContinuityRefused() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory)
            XCTAssertEqual(chmod(directory.appendingPathComponent("protected-apps.state.v1.json").path,0o644),0)
            assertPolicyFailure("POLICY_PERMISSION_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd) }
        }
    }
    func testFilesystemNonPrivateDirectoryRefused() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory); XCTAssertEqual(chmod(directory.path,0o755),0)
            assertPolicyFailure("POLICY_PERMISSION_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd) }
        }
    }
    func testFilesystemSymlinkPolicyRefusedWithoutFollowing() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory)
            let original = directory.appendingPathComponent("protected-apps.v1.json"), target = directory.appendingPathComponent("actual.json")
            try FileManager.default.moveItem(at:original,to:target)
            XCTAssertEqual(symlink("actual.json",original.path),0)
            assertPolicyFailure("POLICY_PERMISSION_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd) }
        }
    }
    func testFilesystemHardlinkedPolicyRefused() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory)
            XCTAssertEqual(link(directory.appendingPathComponent("protected-apps.v1.json").path,directory.appendingPathComponent("extra-link.json").path),0)
            assertPolicyFailure("POLICY_PERMISSION_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd) }
        }
    }
    func testFilesystemOversizePolicyRefusedBeforeParsing() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory)
            let file = directory.appendingPathComponent("protected-apps.v1.json")
            try Data(repeating:32,count:262145).write(to:file); XCTAssertEqual(chmod(file.path,0o600),0)
            assertPolicyFailure("POLICY_PERMISSION_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd) }
        }
    }
    func testFilesystemMissingAcceptedOverlayRefused() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory)
            try FileManager.default.removeItem(at:directory.appendingPathComponent("protected-apps.v1.json"))
            assertPolicyFailure("POLICY_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd) }
            // Metadata-only discovery may omit initialization, but never forgets
            // a continuity file proving an owner overlay previously existed.
            assertPolicyFailure("POLICY_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd,requireInitialized:false) }
        }
    }
    func testFilesystemDirectoryDescriptorCannotBeRegularFile() throws {
        try withPolicyDirectory { directory,_ in
            try writePolicyFiles(directory)
            let file = open(directory.appendingPathComponent("protected-apps.v1.json").path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            XCTAssertGreaterThanOrEqual(file,0); defer { if file >= 0 { close(file) } }
            assertPolicyFailure("POLICY_PERMISSION_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(file) }
        }
    }
    func testFilesystemNonRegularPolicyRefused() throws {
        try withPolicyDirectory { directory,fd in
            try writePolicyFiles(directory)
            let file = directory.appendingPathComponent("protected-apps.v1.json")
            try FileManager.default.removeItem(at:file)
            XCTAssertEqual(mkfifo(file.path,0o600),0)
            assertPolicyFailure("POLICY_PERMISSION_INVALID") { _ = try ProtectedAppPolicy.loadDirectory(fd) }
        }
    }
    func testCanonicalRevisionRejectsLeadingPlus() throws {
        let bytes = try overlay(revision:"+1")
        assertPolicyFailure("POLICY_INVALID") { _ = try ProtectedAppPolicy(overlay:bytes,continuity:try state(bytes,revision:"+1")) }
    }
}
