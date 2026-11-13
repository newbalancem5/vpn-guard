import AppKit
import NetworkExtension
import SystemExtensions

final class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private var extensionID: String { Bundle.main.bundleIdentifier! + ".filter" }
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString:
        NSLocalizedString("initialStatus", comment: ""))
    private var buttons: [NSButton] = []

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 330),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        // Retain the AppKit window when its close button is used so the dock
        // reopen handler cannot reference a window released by NSWindow.close().
        window.isReleasedWhenClosed = false
        window.title = NSLocalizedString("windowTitle", comment: "")
        let title = NSTextField(labelWithString: NSLocalizedString("heading", comment: ""))
        title.font = .boldSystemFont(ofSize: 20)
        let description = NSTextField(wrappingLabelWithString:
            NSLocalizedString("description", comment: ""))
        let actions = NSStackView()
        actions.orientation = .horizontal
        for (label, action) in [(NSLocalizedString("install", comment: ""), #selector(activate)),
                                (NSLocalizedString("enable", comment: ""), #selector(enable)),
                                (NSLocalizedString("disable", comment: ""), #selector(disable)),
                                (NSLocalizedString("removeFilter", comment: ""), #selector(remove))] {
            let button = NSButton(title: label, target: self, action: action)
            button.bezelStyle = .rounded
            buttons.append(button)
            actions.addArrangedSubview(button)
        }
        let stack = NSStackView(views: [title, description, actions, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: NSLocalizedString("quit", comment: ""),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func report(_ message: String, busy: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        status.stringValue = message
        buttons.forEach { $0.isEnabled = !busy }
    }

    @objc private func activate() {
        report(NSLocalizedString("installing", comment: ""), busy: true)
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    @objc private func enable() {
        report(NSLocalizedString("saving", comment: ""), busy: true)
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { error in
            DispatchQueue.main.async {
                if let error { self.report(error.localizedDescription); return }
                if let existing = manager.providerConfiguration,
                   existing.filterDataProviderBundleIdentifier != self.extensionID {
                    self.report(NSLocalizedString("existingConfig", comment: ""))
                    return
                }
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterPackets = false
                configuration.filterDataProviderBundleIdentifier = self.extensionID
                manager.providerConfiguration = configuration
                manager.localizedDescription = NSLocalizedString("filterDescription", comment: "")
                manager.isEnabled = true
                manager.saveToPreferences { error in
                    DispatchQueue.main.async {
                        self.report(error?.localizedDescription ??
                            NSLocalizedString("saved", comment: ""))
                    }
                }
            }
        }
    }

    @objc private func disable() {
        report(NSLocalizedString("disabling", comment: ""), busy: true)
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { error in
            DispatchQueue.main.async {
                if let error { self.report(error.localizedDescription); return }
                guard let configuration = manager.providerConfiguration else {
                    self.report(NSLocalizedString("alreadyDisabled", comment: "")); return
                }
                guard configuration.filterDataProviderBundleIdentifier == self.extensionID else {
                    self.report(NSLocalizedString("otherConfigUnchanged", comment: "")); return
                }
                guard manager.isEnabled else {
                    self.report(NSLocalizedString("alreadyDisabled", comment: "")); return
                }
                manager.isEnabled = false
                manager.saveToPreferences { error in
                    DispatchQueue.main.async {
                        self.report(error?.localizedDescription ??
                            NSLocalizedString("disabled", comment: ""))
                    }
                }
            }
        }
    }

    @objc private func remove() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("removeTitle", comment: "")
        alert.informativeText = NSLocalizedString("removeExplanation", comment: "")
        alert.addButton(withTitle: NSLocalizedString("remove", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        report(NSLocalizedString("removing", comment: ""), busy: true)
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { error in
            DispatchQueue.main.async {
                if let error { self.report(error.localizedDescription); return }
                guard let configuration = manager.providerConfiguration else { self.deactivate(); return }
                guard configuration.filterDataProviderBundleIdentifier == self.extensionID else {
                    self.report(NSLocalizedString("otherConfigUnchanged", comment: ""))
                    return
                }
                manager.removeFromPreferences { error in
                    DispatchQueue.main.async {
                        if let error { self.report(error.localizedDescription); return }
                        self.deactivate()
                    }
                }
            }
        }
    }

    private func deactivate() {
        let request = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        report(NSLocalizedString("approvalNeeded", comment: ""), busy: true)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        report(result == .completed ?
            NSLocalizedString("requestCompleted", comment: "") :
            NSLocalizedString("rebootNeeded", comment: ""))
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        report(String(format: NSLocalizedString("requestFailed", comment: ""), error.localizedDescription))
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // Only upgrade this lab's own extension. SystemExtensions validates its
        // signing team; never replace an unrelated identifier or downgrade.
        guard existing.bundleIdentifier == extensionID,
              ext.bundleIdentifier == extensionID,
              existing.bundleVersion.compare(ext.bundleVersion, options: .numeric) == .orderedAscending
        else { return .cancel }
        return .replace
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
