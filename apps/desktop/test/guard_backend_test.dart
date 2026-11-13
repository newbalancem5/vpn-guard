import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_guard/app/vpn_guard_app.dart';
import 'package:vpn_guard/features/protection/data/native_guard_backend.dart';
import 'package:vpn_guard/features/protection/domain/guard_backend.dart';

Map<String, Object?> status({
  bool enabled = false,
  String extension = 'installed',
}) => {
  'protocolVersion': 1,
  'platform': 'macos',
  'capable': true,
  'extensionState': extension,
  'configurationEnabled': enabled,
  'antigravityFound': true,
  'languageServerCovered': true,
  'languageServerCurrent': enabled,
  'protectionVerified': false,
  'mode': enabled ? 'block-antigravity-v1' : 'none',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(NativeGuardBackend.channel, null),
  );

  test('Enabled preferences do not imply VPN protection and require a known extension', () async {
    messenger.setMockMethodCallHandler(
      NativeGuardBackend.channel,
      (_) async => status(enabled: true, extension: 'needsApproval'),
    );
    final report = await const NativeGuardBackend().inspect();
    expect(report.antigravityConfigured, isTrue);
    expect(report.canEnable, isFalse);
  });
  test('Malformed or future backend responses fail closed in the UI', () async {
    for (final data in [
      {...status(), 'protocolVersion': 2},
      {...status(), 'configurationEnabled': 'true'},
      {...status(), 'extensionState': 'magic'},
      {...status(), 'protectionVerified': true},
    ]) {
      messenger.setMockMethodCallHandler(
        NativeGuardBackend.channel,
        (_) async => data,
      );
      expect(
        (await const NativeGuardBackend().inspect()).issue,
        BackendIssue.unsupportedProtocol,
      );
    }
  });
  testWidgets('Main UI enables and disables only the Antigravity experiment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var enabled = false;
    final actions = <String>[];
    messenger.setMockMethodCallHandler(NativeGuardBackend.channel, (
      call,
    ) async {
      if (call.method == 'getStatus') return status(enabled: enabled);
      actions.add(call.method);
      if (call.method == 'enableAntigravity') enabled = true;
      if (call.method == 'disableFilter') enabled = false;
      return null;
    });
    await tester.pumpWidget(const VpnGuardApp(backend: NativeGuardBackend()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Включить тестовую блокировку'));
    await tester.pumpAndSettle();
    expect(actions, ['enableAntigravity']);
    expect(
      find.textContaining('Тестовая блокировка включена в настройках macOS.'),
      findsOneWidget,
    );
    expect(find.text('Защищено'), findsNothing);
    await tester.tap(find.text('Отключить фильтр'));
    await tester.pumpAndSettle();
    expect(actions, ['enableAntigravity', 'disableFilter']);
    expect(
      find.text('Тестовая блокировка Antigravity выключена.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Failure to enable does not display a successful block', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    messenger.setMockMethodCallHandler(NativeGuardBackend.channel, (
      call,
    ) async {
      if (call.method == 'getStatus') return status();
      throw PlatformException(code: 'extension_not_ready');
    });
    await tester.pumpWidget(const VpnGuardApp(backend: NativeGuardBackend()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Включить тестовую блокировку'));
    await tester.pumpAndSettle();
    expect(
      find.text('Сначала установите расширение и разрешите его в macOS.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Тестовая блокировка включена в настройках macOS.'),
      findsNothing,
    );
  });
}
