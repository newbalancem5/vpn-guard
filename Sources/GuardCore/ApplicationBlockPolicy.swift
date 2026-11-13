import Foundation
import Security

/// Identity-only deny policy. No VPN admission or trusted-network decision.
public struct SignedProcessIdentity: Equatable {
    public let identifier: String
    /// Set only after the running code satisfied an Apple-anchored requirement
    /// for this exact team; a merely claimed team ID is never reported.
    public let team: String?
    public let codeHash: String?
    public init(identifier: String, team: String?, codeHash: String? = nil) {
        self.identifier = identifier
        self.team = team
        self.codeHash = codeHash
    }
}

public struct CodeSigningLookupError: Error, Equatable {
    public let stage: String
    public let status: OSStatus
}

public extension SignedProcessIdentity {
    /// Reads the identity of running code. Uses the kernel-provided (dynamic)
    /// signature when `code` was obtained with `kSecGuestAttributeDynamicCode`,
    /// so no on-disk app files are read from the filter sandbox.
    static func resolve(_ code: SecCode) throws -> SignedProcessIdentity? {
        var staticCode: SecStaticCode?
        let extraction = SecCodeCopyStaticCode(code, [], &staticCode)
        guard extraction == errSecSuccess, let staticCode else {
            throw CodeSigningLookupError(stage: "static", status: extraction)
        }
        var information: CFDictionary?
        // kSecCodeInfoTeamIdentifier is only returned with kSecCSSigningInformation;
        // the generic set contains the identifier and CDHash but no team.
        let signing = SecCodeCopySigningInformation(staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard signing == errSecSuccess, let info = information as? [String: Any] else {
            throw CodeSigningLookupError(stage: "information", status: signing)
        }
        // Unsigned code has no identifier.
        guard let identifier = info[kSecCodeInfoIdentifier as String] as? String else { return nil }
        let claimedTeam = info[kSecCodeInfoTeamIdentifier as String] as? String
        return SignedProcessIdentity(identifier: identifier,
            team: claimedTeam.flatMap { satisfies(code, team: $0) ? $0 : nil },
            codeHash: (info[kSecCodeInfoUnique as String] as? Data)?
                .map { String(format: "%02x", $0) }.joined())
    }

    /// Requirement text for a well-formed Apple team ID; nil rejects anything
    /// that could alter the requirement expression.
    static func teamRequirement(_ team: String) -> String? {
        guard team.utf8.count == 10,
              team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    private static func satisfies(_ code: SecCode, team: String) -> Bool {
        var requirement: SecRequirement?
        guard let text = teamRequirement(team),
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}

public enum ApplicationBlockPolicy {
    public static let mode = "block-antigravity-v1"
    public static let team = "EQHXZ8M8AV"
    public static let identifiers: Set<String> = [
        "com.google.antigravity", "com.google.antigravity.helper",
        "com.google.antigravity.helper.GPU", "com.google.antigravity.helper.Plugin",
        "com.google.antigravity.helper.Renderer",
    ]

    public static func matches(_ identity: SignedProcessIdentity?, languageServerHash: String?) -> Bool {
        guard let identity, identity.team == team else { return false }
        if identifiers.contains(identity.identifier) { return true }
        // A generic Google-signed language_server is not enough: pin the verified
        // executable from the selected installation. Recheck after app updates.
        guard identity.identifier == "language_server", let hash = languageServerHash,
              !hash.isEmpty else { return false }
        return identity.codeHash == hash
    }

    public static func shouldBlock(mode: String?, app: SignedProcessIdentity?,
                                   process: SignedProcessIdentity?, languageServerHash: String?) -> Bool {
        guard mode == self.mode else { return false }
        return matches(app, languageServerHash: languageServerHash)
            || matches(process, languageServerHash: languageServerHash)
    }
}
