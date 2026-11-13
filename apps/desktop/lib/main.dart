import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/vpn_guard_app.dart';
import 'features/network/application/network_controller.dart';
import 'features/network/data/https_network_inspector.dart';
import 'features/protection/data/native_guard_backend.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    VpnGuardApp(
      backend: const NativeGuardBackend(),
      network: NetworkController(HttpsNetworkInspector()),
      networkChanges: const EventChannel('org.vpnguard/network_changes')
          .receiveBroadcastStream()
          .skip(1)
          .map((_) {}),
    ),
  );
}
