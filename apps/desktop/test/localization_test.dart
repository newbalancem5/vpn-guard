import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vpn_guard/app/vpn_guard_app.dart';
import 'package:vpn_guard/features/network/application/network_controller.dart';
import 'package:vpn_guard/features/network/domain/network_inspector.dart';
import 'package:vpn_guard/features/network/domain/network_models.dart';
import 'package:vpn_guard/features/protection/domain/guard_backend.dart';

class OfflineBackend extends GuardBackend {
  @override
  Future<BackendReport> inspect() async =>
      const BackendReport(platform: 'test', issue: BackendIssue.notConnected);
}

class ExampleNetwork implements NetworkInspector {
  @override
  Future<String> fingerprint() async => 'test';

  @override
  Future<NetworkObservation> inspect(CheckSession session) async {
    final now = DateTime.now();
    return NetworkObservation(
      fingerprint: 'test',
      families: [
        for (final family in AddressFamily.values)
          FamilyObservation(
            family: family,
            checkedAt: now,
            ip: family == AddressFamily.ipv4
                ? '8.8.8.8'
                : '2001:4860:4860:1234:5678:abcd:ef12:8888',
            geo: GeoLocation(
              ip: '8.8.8.8',
              countryCode: 'SE',
              country: 'Sweden',
              region: '',
              checkedAt: now,
            ),
          ),
      ],
    );
  }
}

void main() {
  test('Both ARB catalogs have identical messages and placeholder schemas', () {
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
    final ru =
        jsonDecode(File('lib/l10n/app_ru.arb').readAsStringSync()) as Map;
    expect(en.keys.toSet(), ru.keys.toSet());
    for (final key in en.keys.where(
      (key) => key.startsWith('@') && key != '@@locale',
    )) {
      expect(en[key], ru[key], reason: key);
    }
  });

  for (final width in [720.0, 1060.0]) {
    testWidgets('RU/EN delegates and long IPv6 fit a $width desktop window', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        VpnGuardApp(
          backend: OfflineBackend(),
          network: NetworkController(ExampleNetwork()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Швеция (SE)'), findsNWidgets(2));
      expect(find.text('Защита не подключена'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(find.text('Protection is not connected'), findsOneWidget);
      expect(find.text('Sweden (SE)'), findsNWidgets(2));
      expect(find.text('Not protected'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"admissionGranted": false'), findsOneWidget);
      expect(find.textContaining('2001:4860'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
