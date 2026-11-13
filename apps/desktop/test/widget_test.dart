import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_guard/main.dart';
import 'package:vpn_guard/platform/guard_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGuardBackend.channel, (_) async {
          throw MissingPluginException();
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGuardBackend.channel, null);
  });

  testWidgets(
    'Missing backend never claims that traffic is blocked or protected',
    (tester) async {
      await tester.pumpWidget(const VpnGuardApp(backend: NativeGuardBackend()));
      await tester.pumpAndSettle();
      expect(find.text('Защита не подключена'), findsOneWidget);
      expect(find.text('Не защищено'), findsNWidgets(2));
      expect(find.text('Защищено'), findsNothing);
      expect(find.text('Заблокировано'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'An unversioned allowed response cannot become an enforcement claim',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeGuardBackend.channel,
            (_) async => {'state': 'ALLOWED'},
          );
      final report = await const NativeGuardBackend().inspect();
      expect(report.code, 'unsupported_backend_protocol');
    },
  );

  testWidgets('Backend errors remain visible and refresh recovers', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGuardBackend.channel, (_) async {
          throw PlatformException(code: 'service_offline');
        });
    await tester.pumpWidget(const VpnGuardApp(backend: NativeGuardBackend()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Системный компонент не ответил'),
      findsOneWidget,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGuardBackend.channel, (_) async {
          throw MissingPluginException();
        });
    await tester.tap(find.text('Проверить компонент'));
    await tester.pumpAndSettle();
    expect(
      find.text('Системный компонент ещё не подключён к приложению.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Диагностика'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"protectionVerified": false'), findsOneWidget);
    expect(find.textContaining('"externalIp": null'), findsOneWidget);
  });
}
