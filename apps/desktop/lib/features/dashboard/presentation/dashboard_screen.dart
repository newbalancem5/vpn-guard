import 'package:material_ui/material_ui.dart';

import '../../../l10n/l10n.dart';
import '../../network/domain/network_failure.dart';
import '../application/dashboard_controller.dart';
import 'views/overview_view.dart';
import 'views/diagnostics_view.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.locale,
    required this.onLocaleChanged,
  });
  final DashboardController controller;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _page = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.recheck(NetworkIssue.resumed);
      if (!widget.controller.performingAction) {
        widget.controller.refresh(includeNetwork: false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _page,
              onDestinationSelected: (index) => setState(() => _page = index),
              labelType: NavigationRailLabelType.all,
              backgroundColor: Theme.of(context).colorScheme.surface,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Icon(Icons.shield_outlined, size: 30),
              ),
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.shield_outlined),
                  selectedIcon: const Icon(Icons.shield),
                  label: Text(l10n.protectionTab),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(l10n.diagnosticsTab),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: DropdownButton<Locale>(
                              key: const Key('language-selector'),
                              value: widget.locale,
                              hint: Text(l10n.language),
                              items: [
                                DropdownMenuItem(
                                  value: const Locale('ru'),
                                  child: Text(l10n.russian),
                                ),
                                DropdownMenuItem(
                                  value: const Locale('en'),
                                  child: Text(l10n.english),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  widget.onLocaleChanged(value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_page == 0)
                            OverviewView(controller: widget.controller)
                          else
                            DiagnosticsView(controller: widget.controller),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
