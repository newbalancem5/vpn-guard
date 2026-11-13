import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../application/dashboard_controller.dart';

class DiagnosticsView extends StatelessWidget {
  const DiagnosticsView({super.key, required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.diagnosticsTab,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      Text(context.l10n.diagnosticsDescription),
      const SizedBox(height: 24),
      SectionCard(
        child: SelectionArea(
          child: Text(
            controller.diagnostics,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: controller.loading ? null : () => controller.refresh(),
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.refresh),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              var success = true;
              try {
                await Clipboard.setData(
                  ClipboardData(text: controller.diagnostics),
                );
              } catch (_) {
                success = false;
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? context.l10n.diagnosticsCopied
                          : context.l10n.copyFailed,
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(context.l10n.copy),
          ),
        ],
      ),
    ],
  );
}
