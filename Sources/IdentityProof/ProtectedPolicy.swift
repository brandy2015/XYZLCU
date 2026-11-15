import Foundation
import CryptoKit
import Darwin

/// The catalog seeds remain denials when publisher pins have not been reviewed.
/// No name/title heuristic and no publisher-wide allow rule is used here.
public struct ProtectedAppPolicy {
    public struct Verdict: Equatable {
        public let classification: String
        public let decision: String
        public let code: String?
    }
    public static let builtins: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.lastpass.LastPass", "com.dashlane.Dashlane", "org.keepassxc.keepassxc",
        "com.apple.Passwords", "com.apple.keychainaccess", "com.apple.systempreferences",
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "dev.warp.Warp-Preview", "com.mitchellh.ghostty", "org.alacritty",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "com.tencent.xinWeChat",
        "com.yourcompany.PPClient", "com.alipay.iphoneclient"
    ]
    public let revision: String
    public let digest: String
    public let removals: Set<String>
    private let rules: [[String: JSONValue]]

    public init(overlay: Data? = nil, continuity: Data? = nil) throws {
        var rules: [[String: JSONValue]] = []
        var removed: Set<String> = []
        var revision = "0"
        if let overlay {
            let value = try JSONValue.parse(overlay)
            guard let o = value.object,
                  Set(o.keys) == Set(["schema_version", "revision", "additions", "allow_builtin_removals", "removed_builtin_rule_ids"]),
                  o["schema_version"]?.number == 1,
                  let rev = o["revision"]?.string, UInt64(rev) != nil,
                  rev.range(of: "^[1-9][0-9]{0,19}$", options: .regularExpression) != nil,
                  case .array(let additions)? = o["additions"], additions.count <= 256,
                  let allow = o["allow_builtin_removals"]?.bool,
                  case .array(let removals)? = o["removed_builtin_rule_ids"], removals.count <= 256 else {
                throw IdentityFailure(code: "POLICY_INVALID", message: "Invalid owner policy schema")
            }
            revision = rev
            var ids = Set<String>()
            for addition in additions {
                guard let r = addition.object,
                      Set(r.keys) == Set(["rule_id", "category", "bundle_id_pattern", "team_id", "designated_requirement", "signing_identifiers"]),
                      let id = r["rule_id"]?.string, !id.isEmpty, id.utf8.count <= 128, ids.insert(id).inserted,
                      let category = r["category"]?.string,
                      ["password_manager", "apple_secrets", "system_security", "terminal", "banking_payment", "owner_addition"].contains(category),
                      let pattern = r["bundle_id_pattern"]?.string, pattern.utf8.count <= 255,
                      pattern.range(of: "^[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+(?:\\.\\*)?$", options: .regularExpression) != nil,
                      let requirement = r["designated_requirement"]?.string, !requirement.isEmpty, requirement.utf8.count <= 8192,
                      case .array(let signing)? = r["signing_identifiers"], (1...32).contains(signing.count),
                      signing.allSatisfy({ ($0.string?.utf8.count ?? 0) > 0 && ($0.string?.utf8.count ?? 513) <= 512 }),
                      Set(signing.compactMap(\.string)).count == signing.count else {
                    throw IdentityFailure(code: "POLICY_INVALID", message: "Invalid owner protection rule")
                }
                if r["team_id"] == .null {
                    guard requirement.contains("anchor apple") else { throw IdentityFailure(code: "POLICY_INVALID", message: "Apple rule requires anchor") }
                } else {
                    guard let team = r["team_id"]?.string, !team.isEmpty, team.utf8.count <= 128 else { throw IdentityFailure(code: "POLICY_INVALID", message: "Missing publisher pin") }
                }
                rules.append(r)
            }
            for item in removals {
                guard allow, let id = item.string, Self.builtins.contains(id), removed.insert(id).inserted else {
                    throw IdentityFailure(code: "POLICY_INVALID", message: "Invalid explicit builtin removal")
                }
            }
            guard let continuity, let state = try JSONValue.parse(continuity).object,
                  Set(state.keys) == Set(["schema_version", "revision", "overlay_sha256"]),
                  state["schema_version"]?.number == 1, state["revision"]?.string == rev,
                  state["overlay_sha256"]?.string == Self.sha(overlay) else {
                throw IdentityFailure(code: "POLICY_INVALID", message: "Missing or unreconciled owner policy continuity")
            }
        } else if continuity != nil {
            throw IdentityFailure(code: "POLICY_INVALID", message: "Accepted owner overlay disappeared")
        }
        self.rules = rules; self.removals = removed; self.revision = revision
        let effective = JSONValue.object(["catalog_revision": .string("xyzlcu-0.8.0-seeds-1"),
            "builtins": .array(Self.builtins.sorted().map(JSONValue.string)),
            "overlay": try overlay.map { try JSONValue.parse($0) } ?? .null])
        self.digest = Self.sha(Data("XYZLCU/POLICY/1\0".utf8) + effective.canonicalData())
    }

    public func evaluate(bundleID: String, teamID: String?, signingID: String?, validSignature: Bool, appleAnchor: Bool = false, requirementMatched: Bool = false) -> Verdict {
        if Self.builtins.contains(bundleID), !removals.contains(bundleID) {
            // Vendor seeds without independently reviewed pins never become Allowed.
            let verifiedApple = bundleID.hasPrefix("com.apple.") && validSignature && appleAnchor
            return Verdict(classification: verifiedApple ? "protected" : "suspicious_identity", decision: "deny", code: verifiedApple ? "PROTECTED_APP_REFUSED" : "PROTECTED_IDENTITY_SUSPICIOUS")
        }
        for rule in rules {
            let pattern = rule["bundle_id_pattern"]!.string!
            let matches = pattern.hasSuffix(".*") ? bundleID.hasPrefix(String(pattern.dropLast())) : bundleID == pattern
            if matches {
                // Rule evaluation is conservative. Requirement validation is supplied
                // by the real SigningProvider; absent evidence cannot remove denial.
                let teamMatches = rule["team_id"] == .null ? appleAnchor : rule["team_id"]?.string == teamID
                let signing = rule["signing_identifiers"]!
                let identifiers: [JSONValue]; if case .array(let values) = signing { identifiers = values } else { identifiers = [] }
                let verified = validSignature && requirementMatched && teamMatches && identifiers.contains(.string(signingID ?? ""))
                return Verdict(classification: verified ? "protected" : "suspicious_identity", decision: "deny", code: verified ? "PROTECTED_APP_REFUSED" : "PROTECTED_IDENTITY_SUSPICIOUS")
            }
        }
        return Verdict(classification: "unknown", decision: validSignature ? "allow" : "deny", code: validSignature ? nil : "SIGNATURE_INVALID")
    }

    /// Fixed account-home path; environment and model input cannot redirect it.
    public static func loadUserPolicy(requireInitialized: Bool = true) throws -> ProtectedAppPolicy {
        guard let account = getpwuid(geteuid()), let home = account.pointee.pw_dir else { throw IdentityFailure(code: "POLICY_INVALID", message: "Account home unavailable") }
        let root = String(cString: home)
        let names = ["Library", "Application Support", "XYZLCU"]
        var fd = open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Unsafe account home") }
        defer { close(fd) }
        for (index, name) in names.enumerated() {
            let next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT {
                guard !requireInitialized else { throw IdentityFailure(code: "POLICY_INVALID", message: "Explicit owner policy initialization required") }
                return try ProtectedAppPolicy()
            }
            guard next >= 0 else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Unsafe owner policy directory") }
            var s = stat()
            guard fstat(next, &s) == 0, s.st_uid == geteuid(), s.st_mode & 0o022 == 0,
                  index != 2 || s.st_mode & 0o777 == 0o700 else {
                close(next); throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Invalid owner policy directory permissions")
            }
            close(fd); fd = next
        }
        return try loadDirectory(fd, requireInitialized: requireInitialized)
    }

    /// Internal descriptor seam for filesystem verification. Production always
    /// reaches it through fixed-account-home, no-follow directory traversal.
    /// Borrows fd: callers retain ownership and must never expose it to models.
    static func loadDirectory(_ fd: Int32, requireInitialized: Bool = true) throws -> ProtectedAppPolicy {
        func verifyDirectory() throws {
            var metadata = stat()
            guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
                  metadata.st_uid == geteuid(), metadata.st_mode & 0o777 == 0o700,
                  metadata.st_nlink > 0 else {
                throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Invalid owner policy directory descriptor")
            }
        }
        try verifyDirectory()
        func readFile(_ name: String) throws -> Data? {
            let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            if file < 0, errno == ENOENT { return nil }
            guard file >= 0 else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Unsafe owner policy file") }
            defer { close(file) }
            var before = stat()
            guard fstat(file, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
                  before.st_uid == geteuid(), before.st_nlink == 1, before.st_mode & 0o777 == 0o600,
                  before.st_size > 0, before.st_size <= 262144 else { throw IdentityFailure(code: "POLICY_PERMISSION_INVALID", message: "Invalid owner policy file permissions") }
            var data = Data(), bytes = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = read(file, &bytes, bytes.count)
                guard n >= 0 else { throw IdentityFailure(code: "POLICY_INVALID", message: "Owner policy read failed") }
                if n == 0 { break }; data.append(contentsOf: bytes.prefix(n))
                guard data.count <= 262144 else { throw IdentityFailure(code: "POLICY_INVALID", message: "Owner policy exceeds bound") }
            }
            var after = stat(), linked = stat()
            guard fstat(file, &after) == 0, fstatat(fd, name, &linked, AT_SYMLINK_NOFOLLOW) == 0,
                  before.st_dev == linked.st_dev, before.st_ino == linked.st_ino,
                  before.st_dev == after.st_dev, before.st_ino == after.st_ino,
                  after.st_uid == geteuid(), linked.st_uid == geteuid(),
                  after.st_nlink == 1, linked.st_nlink == 1,
                  after.st_mode & S_IFMT == S_IFREG, linked.st_mode & S_IFMT == S_IFREG,
                  after.st_mode & 0o777 == 0o600, linked.st_mode & 0o777 == 0o600,
                  before.st_size == after.st_size, before.st_size == linked.st_size,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw IdentityFailure(code: "POLICY_INVALID", message: "Owner policy changed while reading") }
            return data
        }
        let overlay = try readFile("protected-apps.v1.json"), continuity = try readFile("protected-apps.state.v1.json")
        guard !requireInitialized || overlay != nil && continuity != nil else { throw IdentityFailure(code: "POLICY_INVALID", message: "Explicit owner policy continuity required") }
        try verifyDirectory()
        return try ProtectedAppPolicy(overlay: overlay, continuity: continuity)
    }
    private static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
