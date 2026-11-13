import 'package:material_ui/material_ui.dart';

import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../protection/domain/guard_backend.dart';
import '../../application/dashboard_controller.dart';

class AntigravityControlCard extends StatelessWidget {
  const AntigravityControlCard({super.key, required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final r = controller.report;
    final busy = controller.loading || controller.performingAction;
    final connected = r?.issue == BackendIssue.none;
    final state = switch (r?.extensionState) {
      ExtensionState.installed => l.filterInstalled,
      ExtensionState.needsApproval => l.filterNeedsApproval,
      ExtensionState.updateRequired => l.filterUpdateRequired,
      ExtensionState.rebootRequired => l.filterRebootRequired,
      ExtensionState.notInstalled => l.filterNotInstalled,
      _ => l.filterStateUnknown,
    };
    final error = switch (controller.actionError) {
      null => null,
      'move_to_applications' => l.filterMoveToApplications,
      'signing_required' => l.filterSigningRequired,
      'app_missing' || 'app_unverified' => l.antigravityUnverified,
      'extension_not_ready' => l.filterNotReady,
      'other_configuration' => l.filterOtherConfiguration,
      'busy' => l.filterBusy,
      _ => l.filterActionFailed,
    };
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.antigravityTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(l.antigravityTestExplanation),
          const SizedBox(height: 12),
          Text(
            r?.antigravityFound == true && r?.languageServerCovered == true
                ? l.antigravityDetected
                : l.antigravityUnverified,
          ),
          const SizedBox(height: 8),
          Text(
            connected && r?.capable != true ? l.filterSigningRequired : state,
          ),
          const SizedBox(height: 8),
          Text(
            !connected ||
                    (r?.configurationEnabled == true &&
                        r?.antigravityConfigured != true)
                ? l.filterStateUnknown
                : (r?.antigravityConfigured == true
                      ? l.antigravityBlockConfigured
                      : l.antigravityBlockDisabled),
          ),
          if (r?.antigravityConfigured == true &&
              r?.languageServerCurrent != true)
            Text(l.antigravityUpdated),
          const SizedBox(height: 8),
          Text(l.antigravityRestartHint),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: !busy && r?.capable == true
                    ? () => controller.perform(GuardAction.installFilter)
                    : null,
                icon: const Icon(Icons.settings_outlined),
                label: Text(l.installFilter),
              ),
              FilledButton.icon(
                onPressed:
                    !busy &&
                        r?.canEnable == true &&
                        r?.configurationEnabled != true
                    ? () => controller.perform(GuardAction.enableAntigravity)
                    : null,
                icon: const Icon(Icons.block),
                label: Text(l.blockAntigravity),
              ),
              OutlinedButton.icon(
                // Keep recovery available even if inspection failed or mode is unknown.
                onPressed:
                    !controller.performingAction &&
                        (r?.capable == true || controller.actionError != null)
                    ? () => controller.perform(GuardAction.disableFilter)
                    : null,
                icon: const Icon(Icons.power_settings_new),
                label: Text(l.disableFilter),
              ),
              OutlinedButton.icon(
                onPressed: !busy && r?.antigravityFound == true
                    ? () => controller.perform(GuardAction.openAntigravity)
                    : null,
                icon: const Icon(Icons.open_in_new),
                label: Text(l.openAntigravity),
              ),
            ],
          ),
          if (controller.performingAction) ...[
            const SizedBox(height: 12),
            Text(l.filterBusy),
          ],
        ],
      ),
    );
  }
}
