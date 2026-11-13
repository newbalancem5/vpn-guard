import 'dart:io';
import 'package:flutter/services.dart';

/// Read-only UI boundary. Traffic permissions belong to the OS backend.
abstract interface class GuardBackend {
  Future<BackendReport> inspect();
}

class BackendReport {
  const BackendReport({required this.platform, required this.reason, required this.code});
  final String platform;
  final String reason;
  final String code;
}

class NativeGuardBackend implements GuardBackend {
  const NativeGuardBackend();
  static const channel = MethodChannel('org.vpnguard/backend');

  @override
  Future<BackendReport> inspect() async {
    final platform = Platform.operatingSystem;
    try {
      // Native adapters are not registered in milestone 0. Do not turn a future
      // response into proof of enforcement until the protocol is implemented.
      await channel.invokeMethod<Object?>('getStatus');
      return BackendReport(platform: platform, code: 'unsupported_backend_protocol',
        reason: 'Версия системного компонента не поддерживается этим прототипом.');
    } on MissingPluginException {
      return BackendReport(platform: platform, code: 'backend_not_connected',
        reason: 'Системный компонент ещё не подключён к приложению.');
    } on PlatformException {
      return BackendReport(platform: platform, code: 'backend_error',
        reason: 'Системный компонент не ответил. Состояние защиты неизвестно.');
    }
  }
}
