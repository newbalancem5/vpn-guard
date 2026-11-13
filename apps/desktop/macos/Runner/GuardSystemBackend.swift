import Cocoa
import FlutterMacOS
import NetworkExtension
import Security
import SystemExtensions

/// Flutter controls the OS-owned configuration; an enabled preference is not an
/// acknowledgement from the data provider and is never returned as VPN protection.
final class GuardSystemBackend {
    private let channel: FlutterMethodChannel
    private var requests: [UUID: ExtensionOperation] = [:]
    private var activationState = "unknown"
    private var mutationInProgress = false
    private var extensionID: String { Bundle.main.bundleIdentifier! + ".filter" }
    private var extensionBundle: Bundle? {
        Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions/\(extensionID).systemextension"))
    }
    private var expectedVersion: String { extensionBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    private var capable: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.system-extension.install" as CFString, nil) as? Bool == true
    }

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "org.vpnguard/backend", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, reply in
            guard let self else { reply(FlutterError(code: "unavailable", message: nil, details: nil)); return }
            switch call.method {
            case "getStatus": self.status(reply)
            case "installFilter": self.install(reply)
            case "enableAntigravity": self.configure(enabled: true, reply: reply)
            case "disableFilter": self.configure(enabled: false, reply: reply)
            case "openAntigravity":
                guard let url = self.antigravityURL else { self.fail("app_missing", reply); return }
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    DispatchQueue.main.async { error == nil ? reply(nil) : self.fail("launch_failed", reply) }
                }
            default: reply(FlutterMethodNotImplemented)
            }
        }
    }

    private var antigravityURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity")
    }
    private func verifiedInfo(_ url: URL, identifier: String) -> [String: Any]? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        let rule = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(ApplicationBlockPolicy.team)\""
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess else { return nil }
        return info as? [String: Any]
    }
    private func applicationInfo() -> (found: Bool, hash: String?) {
        guard let url = antigravityURL, verifiedInfo(url, identifier: "com.google.antigravity") != nil else { return (false, nil) }
        let server = url.appendingPathComponent("Contents/Resources/bin/language_server")
        let hash = (verifiedInfo(server, identifier: "language_server")?[kSecCodeInfoUnique as String] as? Data)?
            .map { String(format: "%02x", $0) }.joined()
        return (true, hash)
    }
    private func fail(_ code: String, _ reply: @escaping FlutterResult, error: Error? = nil) {
        // Native diagnostics carry only domain/code, never arbitrary error payloads.
        let e = error as NSError?
        reply(FlutterError(code: code, message: nil,
                           details: e.map { ["domain": $0.domain, "code": $0.code] }))
    }
    private func queryExtension(_ completion: @escaping (String) -> Void) {
        guard capable, !expectedVersion.isEmpty else { completion("unavailable"); return }
        let id = UUID()
        let operation = ExtensionOperation(identifier: extensionID, expectedVersion: expectedVersion) { [weak self] state, error, finished in
            if finished { self?.requests.removeValue(forKey: id) }
            completion(error == nil ? state : "unknown")
        }
        requests[id] = operation
        operation.submit(activation: false)
    }
    private func status(_ reply: @escaping FlutterResult) {
        let app = applicationInfo()
        let base: [String: Any] = ["protocolVersion": 1, "platform": "macos", "capable": capable,
            "antigravityFound": app.found, "languageServerCovered": app.hash != nil, "protectionVerified": false]
        guard capable else { reply(base.merging(["extensionState": "unavailable", "configurationEnabled": false, "mode": "none"]) { _, b in b }); return }
        queryExtension { state in
            let manager = NEFilterManager.shared()
            manager.loadFromPreferences { error in
                DispatchQueue.main.async {
                    guard error == nil else { self.fail("status_failed", reply, error: error); return }
                    let own = manager.providerConfiguration?.filterDataProviderBundleIdentifier == self.extensionID
                    let config = own ? manager.providerConfiguration?.vendorConfiguration : nil
                    reply(base.merging([
                        "extensionState": self.activationState == "needsApproval" && state != "installed" ? "needsApproval" : state,
                        "configurationEnabled": own && manager.isEnabled,
                        "mode": config?["mode"] as? String ?? "none",
                        "languageServerCurrent": app.hash != nil && app.hash == config?["languageServerHash"] as? String,
                    ]) { _, b in b })
                }
            }
        }
    }
    private func install(_ reply: @escaping FlutterResult) {
        guard capable else { fail("signing_required", reply); return }
        guard !mutationInProgress else { fail("busy", reply); return }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { fail("move_to_applications", reply); return }
        guard !expectedVersion.isEmpty else { fail("extension_missing", reply); return }
        mutationInProgress = true
        let id = UUID()
        var pendingReply: FlutterResult? = reply
        let operation = ExtensionOperation(identifier: extensionID, expectedVersion: expectedVersion) { [weak self] state, error, finished in
            guard let self else { return }
            self.activationState = state
            if let callback = pendingReply {
                pendingReply = nil
                if let error { self.fail("installation_failed", callback, error: error) }
                else { callback(state) }
            }
            if finished { self.mutationInProgress = false; self.requests.removeValue(forKey: id) }
        }
        requests[id] = operation
        operation.submit(activation: true)
    }
    private func configure(enabled: Bool, reply: @escaping FlutterResult) {
        guard capable else { fail("signing_required", reply); return }
        guard !mutationInProgress else { fail("busy", reply); return }
        mutationInProgress = true
        let finish: FlutterResult = { value in self.mutationInProgress = false; reply(value) }
        let apply: () -> Void = {
            let app = enabled ? self.applicationInfo() : (found: false, hash: Optional<String>.none)
            if enabled && (!app.found || app.hash == nil) { self.fail("app_unverified", finish); return }
            let manager = NEFilterManager.shared()
            manager.loadFromPreferences { error in
                DispatchQueue.main.async {
                    guard error == nil else { self.fail("configuration_failed", finish, error: error); return }
                    if let existing = manager.providerConfiguration,
                       existing.filterDataProviderBundleIdentifier != self.extensionID {
                        self.fail("other_configuration", finish); return
                    }
                    if enabled {
                        let configuration = NEFilterProviderConfiguration()
                        configuration.filterSockets = true
                        configuration.filterPackets = false
                        configuration.filterDataProviderBundleIdentifier = self.extensionID
                        configuration.vendorConfiguration = ["mode": ApplicationBlockPolicy.mode, "languageServerHash": app.hash!]
                        manager.providerConfiguration = configuration
                        manager.localizedDescription = "VPN Guard — Antigravity"
                    } else if manager.providerConfiguration == nil { finish(nil); return }
                    manager.isEnabled = enabled
                    manager.saveToPreferences { error in
                        DispatchQueue.main.async {
                            if let error { self.fail("configuration_failed", finish, error: error) }
                            else { finish(nil) }
                        }
                    }
                }
            }
        }
        if enabled {
            queryExtension { state in
                guard state == "installed" else { self.fail("extension_not_ready", finish); return }
                apply()
            }
        } else { apply() }
    }
}

private final class ExtensionOperation: NSObject, OSSystemExtensionRequestDelegate {
    let identifier: String
    let expectedVersion: String
    let completion: (String, Error?, Bool) -> Void
    private var completed = false
    private var activating = false
    init(identifier: String, expectedVersion: String, completion: @escaping (String, Error?, Bool) -> Void) {
        self.identifier = identifier; self.expectedVersion = expectedVersion; self.completion = completion
    }
    func submit(activation: Bool) {
        activating = activation
        let request = activation
            ? OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
            : OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    private func finish(_ state: String, error: Error? = nil) {
        guard !completed else { return }; completed = true
        completion(state, error, true)
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { completion("needsApproval", nil, false) }
    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let current = properties.first { $0.bundleIdentifier == identifier && $0.bundleVersion == expectedVersion && $0.isEnabled }
        let awaiting = properties.contains { $0.bundleIdentifier == identifier && $0.isAwaitingUserApproval }
        finish(current != nil ? "installed" : (awaiting ? "needsApproval" : (properties.isEmpty ? "notInstalled" : "updateRequired")))
    }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        finish(activating ? (result == .completed ? "installed" : "rebootRequired") : "unknown")
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) { finish("unknown", error: error) }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        guard existing.bundleIdentifier == identifier, ext.bundleIdentifier == identifier,
              existing.bundleVersion.compare(ext.bundleVersion, options: .numeric) != .orderedDescending else { return .cancel }
        return .replace
    }
}
