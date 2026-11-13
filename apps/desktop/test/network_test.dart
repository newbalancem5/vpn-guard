import 'package:vpn_guard/features/network/domain/network_failure.dart';
import 'package:vpn_guard/features/network/domain/network_inspector.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_guard/features/network/data/https_network_inspector.dart';
import 'package:vpn_guard/features/network/application/network_controller.dart';
import 'package:vpn_guard/features/network/domain/network_models.dart';
import 'package:vpn_guard/features/admission/domain/region_policy.dart';

class PendingInspector implements NetworkInspector {
  final checks = <Completer<NetworkObservation>>[];
  final sessions = <CheckSession>[];
  @override
  Future<NetworkObservation> inspect(CheckSession session) {
    sessions.add(session);
    final result = Completer<NetworkObservation>();
    checks.add(result);
    return result.future;
  }

  @override
  Future<String> fingerprint() async => 'test-network';
}

NetworkObservation snapshot(String fingerprint) =>
    NetworkObservation(families: const [], fingerprint: fingerprint);

void main() {
  final now = DateTime.utc(2026, 11, 13);

  test('Failed lookup without a global address means the family is absent', () {
    InternetAddress ip(String value) => InternetAddress(value);
    const v6 = InternetAddressType.IPv6;
    const v4 = InternetAddressType.IPv4;
    // VPN ULA plus link-local only: IPv6 cannot reach the internet.
    expect(
      HttpsNetworkInspector.lookupFailure(v6, [
        ip('192.168.1.10'),
        ip('10.8.1.2'),
        ip('fd58:baa6:dead::1'),
        ip('fe80::1'),
        ip('::1'),
      ]),
      NetworkIssue.familyUnavailable,
    );
    expect(
      HttpsNetworkInspector.lookupFailure(v6, []),
      NetworkIssue.familyUnavailable,
    );
    // With a global address, a failed lookup is a DNS/connection problem.
    expect(
      HttpsNetworkInspector.lookupFailure(v6, [ip('2001:db8::5')]),
      NetworkIssue.connectionFailed,
    );
    expect(
      HttpsNetworkInspector.lookupFailure(v4, [ip('2001:db8::5')]),
      NetworkIssue.familyUnavailable,
    );
    expect(
      HttpsNetworkInspector.lookupFailure(v4, [ip('10.8.1.2')]),
      NetworkIssue.connectionFailed,
    );
  });

  test('Different services have independent official country lists', () {
    expect(
      RegionPolicy.evaluate(GuardService.chatgpt, 'AF', now),
      RegionVerdict.supported,
    );
    expect(
      RegionPolicy.evaluate(GuardService.claude, 'AF', now),
      RegionVerdict.unsupported,
    );
    for (final service in GuardService.values) {
      for (final code in ['DE', 'NL', 'US', 'FI']) {
        expect(
          RegionPolicy.evaluate(service, code, now),
          RegionVerdict.supported,
        );
      }
      for (final code in ['RU', 'BY', 'CN', 'IR', 'KP']) {
        expect(
          RegionPolicy.evaluate(service, code, now),
          RegionVerdict.unsupported,
        );
      }
    }
  });

  test('Unknown, exceptional and expired regions never pass', () {
    expect(
      RegionPolicy.evaluate(GuardService.chatgpt, null, now),
      RegionVerdict.unknown,
    );
    expect(
      RegionPolicy.evaluate(GuardService.chatgpt, 'XX', now),
      RegionVerdict.unknown,
    );
    expect(
      RegionPolicy.evaluate(GuardService.claude, 'UA', now),
      RegionVerdict.regionalReview,
    );
    expect(
      RegionPolicy.evaluate(GuardService.chatgpt, 'UA', now),
      RegionVerdict.regionalReview,
    );
    expect(
      RegionPolicy.evaluate(GuardService.claude, 'NL', RegionPolicy.expiresAt),
      RegionVerdict.expiredRules,
    );
    expect(
      RegionPolicy.evaluate(GuardService.claude, 'NL', DateTime.utc(2020)),
      RegionVerdict.expiredRules,
    );
  });

  test('Claude territory rule does not leak into ChatGPT policy', () {
    expect(
      RegionPolicy.evaluate(GuardService.claude, 'PR', now),
      RegionVerdict.supported,
    );
    expect(
      RegionPolicy.evaluate(GuardService.chatgpt, 'PR', now),
      RegionVerdict.unsupported,
    );
  });

  test('IP responses must match their family', () {
    expect(
      HttpsNetworkInspector.parseIp({'ip': '8.8.8.8'}, AddressFamily.ipv4),
      '8.8.8.8',
    );
    for (final value in [
      '::1',
      '127.0.0.1',
      'not-an-ip',
      '2001:4860:4860::8888',
    ]) {
      expect(
        () => HttpsNetworkInspector.parseIp({'ip': value}, AddressFamily.ipv4),
        throwsA(isA<NetworkFailure>()),
      );
    }
    expect(
      () =>
          HttpsNetworkInspector.parseIp({'ip': '8.8.8.8'}, AddressFamily.ipv6),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test(
    'Geolocation must reference the exact IP, including normalized IPv6',
    () {
      final geo = {
        'success': true,
        'ip': '8.8.8.8',
        'country_code': 'US',
        'country': 'United States',
      };
      expect(
        HttpsNetworkInspector.parseGeo(geo, '8.8.8.8', now).countryCode,
        'US',
      );
      expect(
        () => HttpsNetworkInspector.parseGeo(geo, '1.1.1.1', now),
        throwsA(isA<NetworkFailure>()),
      );
      expect(
        () => HttpsNetworkInspector.parseGeo(
          {...geo, 'success': false},
          '8.8.8.8',
          now,
        ),
        throwsA(isA<NetworkFailure>()),
      );
      expect(
        () => HttpsNetworkInspector.parseGeo(
          {...geo, 'country_code': 'XX'},
          '8.8.8.8',
          now,
        ),
        throwsA(isA<NetworkFailure>()),
      );
      expect(
        HttpsNetworkInspector.sameIp(
          '2001:4860:4860:0:0:0:0:8888',
          '2001:4860:4860::8888',
        ),
        isTrue,
      );
    },
  );

  test(
    'A supported exit country never authorizes apps without enforcement',
    () {
      final observation = FamilyObservation(
        family: AddressFamily.ipv4,
        checkedAt: now,
        ip: '8.8.8.8',
        geo: GeoLocation(
          ip: '8.8.8.8',
          countryCode: 'US',
          country: 'United States',
          region: '',
          checkedAt: now,
        ),
      );
      final result = AdmissionAssessment.assess(
        GuardService.chatgpt,
        observation,
        now,
      );
      expect(result.country, RegionVerdict.supported);
      expect(result.mayAuthorizeTraffic, isFalse);
      expect(
        observation.isFresh(now.add(const Duration(seconds: 75))),
        isFalse,
      );
      expect(observation.toJson()['ip'], isNull);
      expect(observation.toJson(includeIp: true)['ip'], '8.8.8.8');
    },
  );

  test('A late response cannot overwrite a newer network generation', () async {
    final inspector = PendingInspector();
    final controller = NetworkController(inspector);
    addTearDown(controller.dispose);
    final first = controller.refresh();
    final second = controller.refresh();
    expect(inspector.sessions.first.cancelled, isTrue);
    inspector.checks[1].complete(snapshot('new'));
    await second;
    inspector.checks[0].complete(snapshot('old'));
    await first;
    expect(controller.observation!.fingerprint, 'new');
    expect(controller.checking, isFalse);
  });

  test(
    'Invalidation clears stale results and ignores in-flight completion',
    () async {
      final inspector = PendingInspector();
      final controller = NetworkController(inspector);
      addTearDown(controller.dispose);
      final pending = controller.refresh();
      controller.invalidate(NetworkIssue.networkChanged);
      inspector.checks.single.complete(snapshot('old'));
      await pending;
      expect(controller.observation, isNull);
      expect(controller.checking, isFalse);
    },
  );
}
