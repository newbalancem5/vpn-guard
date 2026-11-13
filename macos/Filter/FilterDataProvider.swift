import Foundation
import NetworkExtension
import Security
import os

final class FilterDataProvider: NEFilterDataProvider {
    private let logger = Logger(subsystem: "org.vpnguard.prototype", category: "filter")
    private var identities: [Data: SignedProcessIdentity] = [:]
    private let identitiesLock = NSLock()

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        // Every new socket flow reaches the identity decision, regardless of IP family.
        // This does not bind flows to a VPN and deliberately has no allow-probe mode.
        // Wildcard rules omit loopback. Explicit rules make the local dual-stack
        // laboratory endpoint observable without changing unrelated-app verdicts.
        let loopbackRules = [("127.0.0.1", 32), ("::1", 128)].map { address, prefix in
            NEFilterRule(networkRule: NENetworkRule(
                destinationNetwork: NWHostEndpoint(hostname: address, port: "0"),
                prefix: prefix, protocol: .any), action: .filterData)
        }
        let settings = NEFilterSettings(rules: loopbackRules, defaultAction: .filterData)
        apply(settings) { [self] error in
            if let error { logger.error("Filter settings failed: \(error.localizedDescription, privacy: .public)") }
            else { logger.notice("Block-only filter v5 settings applied; VPN protection is NOT verified") }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // NEFilterProvider requires subclasses to acknowledge shutdown. This
        // provider owns no sockets, timers or pending flow verdicts to drain.
        logger.notice("Probe filter stopped; reason=\(reason.rawValue, privacy: .public)")
        identitiesLock.withLock { identities.removeAll() }
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let app = signingIdentity(for: flow.sourceAppAuditToken)
        let process = signingIdentity(for: flow.sourceProcessAuditToken)
        let configuration = filterConfiguration.vendorConfiguration
        if ApplicationBlockPolicy.shouldBlock(mode: configuration?["mode"] as? String,
            app: app, process: process,
            languageServerHash: configuration?["languageServerHash"] as? String) {
            let socket = flow as? NEFilterSocketFlow
            logger.notice("Dropping Antigravity flow \(flow.identifier.uuidString, privacy: .public) family=\(socket?.socketFamily ?? -1) protocol=\(socket?.socketProtocol ?? -1)")
            return .drop()
        }
        switch ProbePolicy.evaluate(appID: app?.identifier, processID: process?.identifier) {
        case .blockProbe:
            let socket = flow as? NEFilterSocketFlow
            logger.notice("Dropping probe flow \(flow.identifier.uuidString, privacy: .public) family=\(socket?.socketFamily ?? -1) protocol=\(socket?.socketProtocol ?? -1)")
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

    private func signingIdentity(for token: Data?) -> SignedProcessIdentity? {
        guard let token else { return nil }
        if let cached = identitiesLock.withLock({ identities[token] }) { return cached }
        var code: SecCode?
        // Use the kernel's dynamic signature, avoiding access to arbitrary app
        // files from the filter sandbox. Audit tokens also prevent PID reuse.
        let attributes = [kSecGuestAttributeAudit as String: token,
                          kSecGuestAttributeDynamicCode as String: true] as CFDictionary
        let lookup = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard lookup == errSecSuccess, let code else {
            logger.debug("Identity lookup failed: \(lookup)")
            return nil
        }
        // Identity is used only for deny rules, not to authorize trusted traffic.
        // The team is reported only after an Apple-anchored requirement check.
        let identity: SignedProcessIdentity
        do {
            guard let resolved = try SignedProcessIdentity.resolve(code) else { return nil }
            identity = resolved
        } catch let error as CodeSigningLookupError {
            logger.debug("Identity \(error.stage, privacy: .public) failed: \(error.status)")
            return nil
        } catch { return nil }
        // Audit tokens contain the process generation; never key this cache by PID.
        identitiesLock.withLock {
            if identities.count >= 512 { identities.removeAll(keepingCapacity: true) }
            identities[token] = identity
        }
        return identity
    }
}

