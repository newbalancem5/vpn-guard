import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'platform/guard_backend.dart';

void main() => runApp(const VpnGuardApp(backend: NativeGuardBackend()));

class VpnGuardApp extends StatelessWidget {
  const VpnGuardApp({super.key, required this.backend});
  final GuardBackend backend;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'VPN Guard',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff335c81)),
      scaffoldBackgroundColor: const Color(0xfff5f6f8),
      useMaterial3: true,
    ),
    home: GuardHome(backend: backend),
  );
}

class GuardHome extends StatefulWidget {
  const GuardHome({super.key, required this.backend});
  final GuardBackend backend;
  @override
  State<GuardHome> createState() => _GuardHomeState();
}

class _GuardHomeState extends State<GuardHome> {
  BackendReport? _report;
  bool _loading = true;
  int _page = 0;
  DateTime? _checkedAt;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    BackendReport report;
    try {
      report = await widget.backend.inspect().timeout(const Duration(seconds: 5));
    } catch (_) {
      report = const BackendReport(platform: 'unknown', code: 'backend_error',
        reason: 'Не удалось получить состояние системного компонента.');
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
      _checkedAt = DateTime.now();
    });
  }

  String get _diagnostics => const JsonEncoder.withIndent('  ').convert({
    'app': 'VPN Guard', 'version': '0.1.0',
    'platform': _report?.platform ?? 'unknown',
    'backend': _report?.code ?? 'checking',
    'protectionVerified': false, 'externalIp': null,
    'checkedAt': _checkedAt?.toUtc().toIso8601String(),
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Row(children: [
      NavigationRail(
        selectedIndex: _page,
        onDestinationSelected: (index) => setState(() => _page = index),
        labelType: NavigationRailLabelType.all,
        backgroundColor: Colors.white,
        leading: const Padding(padding: EdgeInsets.symmetric(vertical: 20),
          child: Icon(Icons.shield_outlined, size: 30)),
        destinations: const [
          NavigationRailDestination(icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield), label: Text('Защита')),
          NavigationRailDestination(icon: Icon(Icons.receipt_long_outlined),
            label: Text('Диагностика')),
        ],
      ),
      const VerticalDivider(width: 1, thickness: 1),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Align(alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
            child: _page == 0 ? _overview(context) : _diagnosticPage(context))),
      )),
    ])),
  );

  Widget _overview(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('VPN Guard', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      const Text('Сетевой доступ приложений под контролем'),
      const SizedBox(height: 28),
      _panel(color: const Color(0xfffff4df), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 32, color: Color(0xff825800)),
          const SizedBox(height: 16),
          Text(_loading ? 'Проверяем компонент…' : 'Защита не подключена',
            style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(_report?.reason ?? 'Запрашиваем состояние системного компонента.'),
          const SizedBox(height: 8),
          const Text('В этой версии приложения сетевой доступ не ограничивается.'),
          const SizedBox(height: 20),
          OutlinedButton.icon(onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh), label: const Text('Проверить компонент')),
        ],
      )),
      const SizedBox(height: 20),
      _panel(child: const Wrap(spacing: 48, runSpacing: 20, children: [
        _Metric(label: 'Внешний IP', value: 'Не проверен'),
        _Metric(label: 'Страна', value: 'Не проверена'),
        _Metric(label: 'Маршрут VPN', value: 'Не подтверждён'),
      ])),
      const SizedBox(height: 28),
      Text('Приложения', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Первые приложения для поддержки. Обнаружение и защита ещё не подключены.'),
      const SizedBox(height: 16),
      _panel(child: const Column(children: [
        _AppRow(name: 'Claude Desktop'), Divider(height: 28), _AppRow(name: 'ChatGPT Desktop'),
      ])),
      const SizedBox(height: 24),
      Text('Прототип 0.1.0 · macOS и Windows · Локально, без аккаунта VPN Guard',
        style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _diagnosticPage(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Диагностика', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 12),
      const Text('Техническое состояние приложения. Содержимое сетевых запросов не собирается.'),
      const SizedBox(height: 24),
      _panel(child: SelectableText(_diagnostics, style: const TextStyle(fontFamily: 'monospace'))),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, children: [
        OutlinedButton.icon(onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh), label: const Text('Обновить')),
        OutlinedButton.icon(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: _diagnostics));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Диагностика скопирована')));
          }
        }, icon: const Icon(Icons.copy_outlined), label: const Text('Скопировать')),
      ]),
    ],
  );

  Widget _panel({required Widget child, Color color = Colors.white}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffe3e5e8))),
    child: child,
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(height: 8),
    Text(value, style: Theme.of(context).textTheme.titleMedium),
  ]);
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Row(children: [
    const Icon(Icons.apps_outlined, color: Color(0xff677385)),
    const SizedBox(width: 16),
    Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
    const SizedBox(width: 12),
    const Text('Не защищено', style: TextStyle(color: Color(0xff825800))),
  ]);
}
