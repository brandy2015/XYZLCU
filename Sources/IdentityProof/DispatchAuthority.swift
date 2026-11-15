import Foundation

/// In-memory authority owned by the trusted controller, independently of the
/// coordinator operation queue. Revocation never waits for Security/AX/SCK calls.
/// A successful beginDispatch orders a single primitive before later revocation;
/// it cannot recall a primitive already admitted to the OS.
public final class DispatchAuthority {
    private let mutex = NSLock()
    private var refusal: IdentityFailure?
    private var dispatched: UInt64 = 0
    public init() {}
    public func revoke(code: String = "CANCELLED") {
        mutex.lock(); defer { mutex.unlock() }
        if refusal == nil { refusal = IdentityFailure(code:code) }
    }
    public func check() throws {
        mutex.lock(); defer { mutex.unlock() }
        if let refusal = refusal { throw refusal }
    }
    @discardableResult public func beginDispatch(validateLocalState: () throws -> Void = {}) throws -> UInt64 {
        mutex.lock(); defer { mutex.unlock() }
        if let refusal = refusal { throw refusal }
        // Only fast local facts (for example the continuous deadline) belong
        // in this closure. Never call an OS primitive or revoke recursively.
        try validateLocalState()
        guard dispatched < UInt64.max else { throw IdentityFailure(code:"SESSION_INVALID") }
        dispatched += 1
        return dispatched
    }
    public var dispatchCount: UInt64 { mutex.lock(); defer { mutex.unlock() }; return dispatched }
}

/// Full host-side pending identity. Executor identity includes its boot/start and
/// build pin encoded by the independently authenticated host, not self-reported
/// proof fields. Never reconstruct these records from historical chat/proof logs.
public struct PendingResponseIdentity: Hashable {
    public let bootID: String, sessionID: String, controllerID: String, executorID: String
    public let nonce: String, sequence: String, requestSHA256: String
    public init(bootID: String, sessionID: String, controllerID: String, executorID: String, nonce: String, sequence: String, requestSHA256: String) {
        self.bootID = bootID; self.sessionID = sessionID; self.controllerID = controllerID; self.executorID = executorID
        self.nonce = nonce; self.sequence = sequence; self.requestSHA256 = requestSHA256
    }
}

/// Host publication bookkeeping, distinct from the executor's dispatch ledger.
/// Actual host sinks must use the resulting once-only publication transaction;
/// a proof's nonce echo is never itself permission to publish or dispatch.
public final class PendingResponseLedger {
    public enum State { case pending, published, discarded }
    private let mutex = NSLock()
    private let capacity: Int
    private var records: [PendingResponseIdentity: State] = [:]
    private var revoked = false
    public init(capacity: Int = 4096) { self.capacity = capacity }
    public func register(_ identity: PendingResponseIdentity) throws {
        mutex.lock(); defer { mutex.unlock() }
        guard !revoked else { throw IdentityFailure(code:"CANCELLED") }
        guard records[identity] == nil else { throw IdentityFailure(code:"REQUEST_REPLAYED") }
        guard records.count < capacity else { throw IdentityFailure(code:"SESSION_INVALID",message:"Publication ledger capacity exhausted.") }
        records[identity] = .pending
    }
    public func revoke() {
        mutex.lock(); defer { mutex.unlock() }
        revoked = true
        for (identity,state) in records where state == .pending { records[identity] = .discarded }
    }
    /// Validate the response first using independently pinned schema/MAC/digest
    /// and live origin/session facts. Verification may be slow and runs outside
    /// the publication mutex; revocation wins before the final consume transition.
    public func consume(_ identity: PendingResponseIdentity, verify: () throws -> Bool) throws {
        let verified: Bool
        do { verified = try verify() } catch {
            mutex.lock(); if records[identity] == .pending { records[identity] = .discarded }; mutex.unlock()
            throw error
        }
        mutex.lock(); defer { mutex.unlock() }
        guard !revoked else { throw IdentityFailure(code:"CANCELLED") }
        guard records[identity] == .pending else { throw IdentityFailure(code:"REQUEST_REPLAYED") }
        guard verified else { records[identity] = .discarded; throw IdentityFailure(code:"PROOF_MAC_INVALID") }
        records[identity] = .published
    }
    public func state(_ identity: PendingResponseIdentity) -> State? { mutex.lock(); defer { mutex.unlock() }; return records[identity] }
}
