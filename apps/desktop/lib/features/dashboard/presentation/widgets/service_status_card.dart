import 'package:material_ui/material_ui.dart';

import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../admission/domain/region_policy.dart';
import '../../../network/domain/network_models.dart';
import '../../application/dashboard_controller.dart';

class ServiceStatusCard extends StatelessWidget {
  const ServiceStatusCard({super.key, required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      children: [
        for (final service in GuardService.values) ...[
          if (service != GuardService.values.first) const Divider(height: 28),
          ServiceStatusRow(service: service, observation: controller.family),
        ],
      ],
    ),
  );
}

class ServiceStatusRow extends StatelessWidget {
  const ServiceStatusRow({
    super.key,
    required this.service,
    required this.observation,
  });
  final GuardService service;
  final FamilyObservation? Function(AddressFamily) observation;

  String _summary(BuildContext context) {
    final l10n = context.l10n;
    return AddressFamily.values
        .map((family) {
          final data = observation(family);
          final verdict =
              data == null ||
                  !data.isFresh(DateTime.now()) ||
                  data.error != null
              ? RegionVerdict.unknown
              : AdmissionAssessment.assess(
                  service,
                  data,
                  DateTime.now(),
                ).country;
          final label = switch (verdict) {
            RegionVerdict.supported => l10n.countrySupported,
            RegionVerdict.unsupported => l10n.countryUnsupported,
            RegionVerdict.unknown => l10n.countryUnknown,
            RegionVerdict.regionalReview => l10n.regionReview,
            RegionVerdict.expiredRules => l10n.expiredCountryRules,
          };
          return l10n.familyCountryStatus(
            family == AddressFamily.ipv4 ? l10n.ipv4 : l10n.ipv6,
            label,
          );
        })
        .join('\n');
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.apps_outlined, color: Color(0xff677385)),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service == GuardService.chatgpt
                  ? context.l10n.chatgptDesktop
                  : context.l10n.claudeDesktop,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _summary(context),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Text(
        context.l10n.notProtected,
        style: const TextStyle(color: Color(0xff825800)),
      ),
    ],
  );
}
