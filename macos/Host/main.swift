import AppKit
import NetworkExtension
import SystemExtensions

final class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private var extensionID: String { Bundle.main.bundleIdentifier! + ".filter" }
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString:
        "Экспериментальный прототип. Защита VPN не реализована и не проверена.")
    private var buttons: [NSButton] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 330),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "VPN Guard — лаборатория macOS"
        let title = NSTextField(labelWithString: "Проверка блокировки guard-probe")
        title.font = .boldSystemFont(ofSize: 20)
        let description = NSTextField(wrappingLabelWithString:
            "Фильтр блокирует только тестовый процесс guard-probe по идентификатору подписи. " +
            "Установка требует подписи Apple Developer и системного разрешения. " +
            "Сначала запустите baseline, затем включите фильтр и повторите тест.")
        let actions = NSStackView()
        actions.orientation = .horizontal
        for (label, action) in [("1. Установить", #selector(activate)),
                                ("2. Включить", #selector(enable)),
                                ("Удалить фильтр", #selector(remove))] {
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
    }

    private func report(_ message: String, busy: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        status.stringValue = message
        buttons.forEach { $0.isEnabled = !busy }
    }

    @objc private func activate() {
        report("Ожидание установки и системного разрешения…", busy: true)
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    @objc private func enable() {
        report("Сохранение конфигурации тестового фильтра…", busy: true)
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { error in
            DispatchQueue.main.async {
                if let error { self.report(error.localizedDescription); return }
                if let existing = manager.providerConfiguration,
                   existing.filterDataProviderBundleIdentifier != self.extensionID {
                    self.report("Обнаружена другая конфигурация: она не будет перезаписана.")
                    return
                }
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterPackets = false
                configuration.filterDataProviderBundleIdentifier = self.extensionID
                manager.providerConfiguration = configuration
                manager.localizedDescription = "VPN Guard — block-only probe experiment"
                manager.isEnabled = true
                manager.saveToPreferences { error in
                    DispatchQueue.main.async {
                        self.report(error?.localizedDescription ??
                            "Конфигурация сохранена. Работа фильтра ещё не подтверждена: проверьте журнал и трафик guard-probe.")
                    }
                }
            }
        }
    }

    @objc private func remove() {
        let alert = NSAlert()
        alert.messageText = "Удалить тестовый фильтр?"
        alert.informativeText = "После удаления guard-probe сможет выходить в сеть без этой блокировки."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        report("Удаление собственной конфигурации…", busy: true)
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { error in
            DispatchQueue.main.async {
                if let error { self.report(error.localizedDescription); return }
                guard let configuration = manager.providerConfiguration else { self.deactivate(); return }
                guard configuration.filterDataProviderBundleIdentifier == self.extensionID else {
                    self.report("Другая конфигурация не изменена.")
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
        report("macOS ожидает разрешения системного расширения в Настройках системы.", busy: true)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        report(result == .completed ?
            "Системный запрос выполнен. Это не подтверждение сетевой защиты." :
            "Для завершения системного запроса нужна перезагрузка.")
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        report("Системный запрос отклонён: \(error.localizedDescription)")
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // Seamless replacement is not validated in this prototype.
        return .cancel
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
