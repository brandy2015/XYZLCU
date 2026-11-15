import XCTest
@testable import IdentityProof

final class AuthorityTests: XCTestCase {
    func identity(nonce:String = "nonce") -> PendingResponseIdentity {
        PendingResponseIdentity(bootID:"boot",sessionID:"session",controllerID:"controller",executorID:"boot-pid-start-build",nonce:nonce,sequence:"1",requestSHA256:"digest")
    }
    func testRevocationOrderedBeforeDispatchPreventsPrimitive() throws {
        let a = DispatchAuthority(); a.revoke()
        XCTAssertThrowsError(try a.beginDispatch()); XCTAssertEqual(a.dispatchCount,0)
    }
    func testDispatchOrderedBeforeRevocationRecordsPossibleEffectAndBlocksNext() throws {
        let a = DispatchAuthority(); XCTAssertEqual(try a.beginDispatch(),1); a.revoke()
        XCTAssertThrowsError(try a.check()); XCTAssertThrowsError(try a.beginDispatch()); XCTAssertEqual(a.dispatchCount,1)
    }
    func testDeadlineRecheckedInsideDispatchTransition() throws {
        let a = DispatchAuthority()
        XCTAssertThrowsError(try a.beginDispatch { throw IdentityFailure(code:"REQUEST_EXPIRED") })
        XCTAssertEqual(a.dispatchCount,0)
    }
    func testHostValidResponsePublishesOnlyOnce() throws {
        let l = PendingResponseLedger(), id = identity(); try l.register(id)
        try l.consume(id) { true }
        XCTAssertEqual(l.state(id),.published)
        XCTAssertThrowsError(try l.consume(id) { true })
    }
    func testHostRevocationDuringSlowVerificationWins() throws {
        let l = PendingResponseLedger(), id = identity(); try l.register(id)
        XCTAssertThrowsError(try l.consume(id) { l.revoke(); return true }) { XCTAssertEqual(($0 as? IdentityFailure)?.code,"CANCELLED") }
        XCTAssertEqual(l.state(id),.discarded)
    }
    func testUnknownOrDifferentSessionCannotPublish() throws {
        let l = PendingResponseLedger(), id = identity(); try l.register(id)
        XCTAssertThrowsError(try l.consume(identity(nonce:"other")) { true })
        let old = PendingResponseIdentity(bootID:"oldboot",sessionID:"session",controllerID:"controller",executorID:"boot-pid-start-build",nonce:"nonce",sequence:"1",requestSHA256:"digest")
        XCTAssertThrowsError(try l.consume(old) { true })
        XCTAssertEqual(l.state(id),.pending)
    }
    func testTerminalRecordsRemainAndCapacityRefusesNewAuthority() throws {
        let l = PendingResponseLedger(capacity:1), id = identity(); try l.register(id); try l.consume(id) { true }
        XCTAssertThrowsError(try l.register(identity(nonce:"next")))
        XCTAssertThrowsError(try l.register(id))
    }
    func testInvalidProofIsTerminalAndCannotBeRetriedAsValid() throws {
        let l = PendingResponseLedger(), id = identity(); try l.register(id)
        XCTAssertThrowsError(try l.consume(id) { false }); XCTAssertEqual(l.state(id),.discarded)
        XCTAssertThrowsError(try l.consume(id) { true })
    }
    func testThrownVerificationFailureAlsoDiscards() throws {
        let l = PendingResponseLedger(), id = identity(); try l.register(id)
        XCTAssertThrowsError(try l.consume(id) { throw IdentityFailure(code:"PAYLOAD_DIGEST_MISMATCH") })
        XCTAssertEqual(l.state(id),.discarded)
    }
}
