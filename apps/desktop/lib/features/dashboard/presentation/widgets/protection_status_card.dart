import 'package:material_ui/material_ui.dart';

import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../protection/domain/guard_backend.dart';

class ProtectionStatusCard extends StatelessWidget {
  const ProtectionStatusCard({
    super.key,
    required this.loading,
    required this.report,
    required this.onRefresh,
  });
  final bool loading;
  final BackendReport? report;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SectionCard(
      warning: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 32, color: Color(0xff825800)),
          const SizedBox(height: 16),
          Text(
            loading
                ? l10n.checkingComponent
                : (report?.issue == BackendIssue.none
                      ? l10n.filterConnected
                      : l10n.protectionDisconnected),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          if (report?.issue != BackendIssue.none)
            Text(report?.issue.localized(l10n) ?? l10n.backendChecking),
          const SizedBox(height: 8),
          Text(
            report?.issue == BackendIssue.none
                ? l10n.filterScopeNotice
                : l10n.noEnforcement,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.checkComponent),
          ),
        ],
      ),
    );
  }
}
