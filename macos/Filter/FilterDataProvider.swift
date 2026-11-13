import Foundation
import NetworkExtension
import Security
import os

final class FilterDataProvider: NEFilterDataProvider {
    private let logger = Logger(subsystem: "org.vpnguard.prototype", category: "filter")

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        // Every new socket flow reaches the identity decision, regardless of IP family.
        // This does not bind flows to a VPN and deliberately has no allow-probe mode.
        let settings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(settings) { [self] error in
            if let error { logger.error("Filter settings failed: \(error.localizedDescription, privacy: .public)") }
            else { logger.notice("Block-only probe filter settings applied; VPN protection is NOT verified") }
            completionHandler(error)
        }
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let appID = signingIdentifier(for: flow.sourceAppAuditToken)
        let processID = signingIdentifier(for: flow.sourceProcessAuditToken)
        switch ProbePolicy.evaluate(appID: appID, processID: processID) {
        case .blockProbe:
            logger.notice("Dropping probe flow \(flow.identifier.uuidString, privacy: .public)")
            return .drop()
        case .allowUnrelated:
            return .allow()
        case .unresolvedIdentity:
            // This experimental target must not cut off the entire machine.
            // Unknown identities remain an explicit coverage gap, never 'protected'.
            logger.error("Unresolved flow identity; allowing unclassified traffic; coverage incomplete")
            return .allow()
        }
    }

    private func signingIdentifier(for token: Data?) -> String? {
        guard let token else { return nil }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                           &information) == errSecSuccess,
              let info = information as? [String: Any] else { return nil }
        // Identifier is used only to deny our probe, not to authorize trusted traffic.
        return info[kSecCodeInfoIdentifier as String] as? String
    }
}

