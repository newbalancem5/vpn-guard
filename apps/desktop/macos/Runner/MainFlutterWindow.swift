import Cocoa
import FlutterMacOS
import Network

class MainFlutterWindow: NSWindow {
  private var pathHandler: NetworkPathHandler?
  private var guardBackend: GuardSystemBackend?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 720, height: 600)
    self.setContentSize(NSSize(width: 1060, height: 780))

    RegisterGeneratedPlugins(registry: flutterViewController)
    guardBackend = GuardSystemBackend(messenger: flutterViewController.engine.binaryMessenger)
    let handler = NetworkPathHandler()
    pathHandler = handler
    FlutterEventChannel(name: "org.vpnguard/network_changes",
      binaryMessenger: flutterViewController.engine.binaryMessenger).setStreamHandler(handler)

    super.awakeFromNib()
  }
}

// Public network-path notifications. This does not install a filter or authorize traffic.
final class NetworkPathHandler: NSObject, FlutterStreamHandler {
  private var monitor: NWPathMonitor?
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    monitor?.cancel()
    let watcher = NWPathMonitor()
    monitor = watcher
    watcher.pathUpdateHandler = { path in
      DispatchQueue.main.async { events(["connected": path.status == .satisfied]) }
    }
    watcher.start(queue: DispatchQueue(label: "org.vpnguard.network-path"))
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    monitor?.cancel()
    monitor = nil
    return nil
  }
}
