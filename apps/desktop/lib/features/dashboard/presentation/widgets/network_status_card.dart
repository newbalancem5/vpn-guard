import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/l10n.dart';
import '../../../../l10n/country_names.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared/widgets/metric_tile.dart';
import '../../../admission/domain/region_policy.dart';
import '../../../network/domain/network_models.dart';
import '../../application/dashboard_controller.dart';

class NetworkStatusCard extends StatelessWidget {
  const NetworkStatusCard({super.key, required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final network = controller.network;
    final results = network?.observation?.families;
    final time = results == null || results.isEmpty
        ? null
        : results.first.checkedAt;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.networkTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              OutlinedButton.icon(
                onPressed: network == null || network.checking
                    ? null
                    : network.refresh,
                icon: const Icon(Icons.public),
                label: Text(
                  network?.checking == true
                      ? l10n.checkingNetwork
                      : l10n.checkNetwork,
                ),
              ),
            ],
          ),
          if (time != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.lastChecked(DateFormat.Hms(l10n.localeName).format(time)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (network?.error != null) ...[
            const SizedBox(height: 12),
            Text(
              network!.error!.localized(l10n),
              style: const TextStyle(color: Color(0xff825800)),
            ),
          ],
          for (final family in AddressFamily.values)
            FamilyStatusSection(
              family: family,
              observation: controller.family(family),
            ),
          const Divider(height: 32),
          Text(l10n.noAdmission),
          const SizedBox(height: 8),
          Text(l10n.routeHint),
          const SizedBox(height: 12),
          Text(
            l10n.providerNotice,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.countryRulesNotice(
              DateFormat.yMd(l10n.localeName).format(RegionPolicy.verifiedAt),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class FamilyStatusSection extends StatelessWidget {
  const FamilyStatusSection({
    super.key,
    required this.family,
    required this.observation,
  });
  final AddressFamily family;
  final FamilyObservation? observation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final geo = observation?.geo;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            family == AddressFamily.ipv4 ? l10n.ipv4 : l10n.ipv6,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 30,
            runSpacing: 16,
            children: [
              MetricTile(
                label: l10n.externalIp,
                value: observation?.ip ?? l10n.notChecked,
              ),
              MetricTile(
                label: l10n.country,
                value: geo == null
                    ? l10n.countryNotChecked
                    : '${l10n.countryName(geo.countryCode)} (${geo.countryCode})',
              ),
              MetricTile(
                label: l10n.checkInterface,
                value: observation?.route?.interfaceName ?? l10n.notDetected,
              ),
            ],
          ),
          if (observation?.error != null) ...[
            const SizedBox(height: 8),
            Text(
              observation!.error!.localized(l10n),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
