import 'package:vpn_guard/features/network/domain/network_inspector.dart';

import 'dart:convert';
import 'dart:io';

import 'package:vpn_guard/features/network/data/https_network_inspector.dart';
import 'package:vpn_guard/features/admission/domain/region_policy.dart';

// Opt-in live check. No firewall changes. IP addresses are redacted from output.
Future<void> main() async {
  final session = CheckSession();
  try {
    final result = await HttpsNetworkInspector().inspect(session);
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'protectionVerified': false,
        'families': result.families
            .map(
              (family) => {
                ...family.toJson(),
                'ipPresent': family.ip != null,
                'countryPolicy': {
                  for (final service in GuardService.values)
                    service.name: RegionPolicy.evaluate(
                      service,
                      family.geo?.countryCode,
                      DateTime.now(),
                    ).name,
                },
              },
            )
            .toList(),
      }),
    );
    if (!result.families.any(
      (family) => family.geo != null && family.error == null,
    )) {
      exitCode = 2;
    }
  } finally {
    session.cancel();
  }
}
