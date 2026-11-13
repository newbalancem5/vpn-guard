import 'package:material_ui/material_ui.dart';

import '../../../../app/app_metadata.dart';
import '../../../../l10n/l10n.dart';
import '../../application/dashboard_controller.dart';
import '../widgets/protection_status_card.dart';
import '../widgets/antigravity_control_card.dart';
import '../widgets/network_status_card.dart';
import '../widgets/service_status_card.dart';

class OverviewView extends StatelessWidget {
  const OverviewView({super.key, required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.appTitle,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 8),
      Text(context.l10n.subtitle),
      const SizedBox(height: 28),
      ProtectionStatusCard(
        loading: controller.loading,
        report: controller.report,
        onRefresh: () => controller.refresh(),
      ),
      const SizedBox(height: 20),
      AntigravityControlCard(controller: controller),
      const SizedBox(height: 20),
      NetworkStatusCard(controller: controller),
      const SizedBox(height: 28),
      Text(
        context.l10n.applications,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(context.l10n.applicationsHint),
      const SizedBox(height: 16),
      ServiceStatusCard(controller: controller),
      const SizedBox(height: 24),
      Text(
        context.l10n.footer(AppMetadata.version),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
