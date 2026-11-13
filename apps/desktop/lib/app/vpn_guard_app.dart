import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import '../features/dashboard/application/dashboard_controller.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/network/application/network_controller.dart';
import '../features/protection/domain/guard_backend.dart';
import '../l10n/generated/app_localizations.dart';

class VpnGuardApp extends StatefulWidget {
  const VpnGuardApp({
    super.key,
    required this.backend,
    this.network,
    this.networkChanges,
    this.initialLocale = const Locale('ru'),
  });
  final GuardBackend backend;
  final NetworkController? network;
  final Stream<void>? networkChanges;
  final Locale initialLocale;

  @override
  State<VpnGuardApp> createState() => _VpnGuardAppState();
}

class _VpnGuardAppState extends State<VpnGuardApp> {
  late Locale _locale = widget.initialLocale;
  late final _controller = DashboardController(
    backend: widget.backend,
    network: widget.network,
    networkChanges: widget.networkChanges,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    debugShowCheckedModeBanner: false,
    locale: _locale,
    // Flutter's generator still emits delegates for the legacy widget libraries.
    // Use the delegates belonging to the extracted Material/Cupertino packages.
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff335c81)),
      scaffoldBackgroundColor: const Color(0xfff5f6f8),
      useMaterial3: true,
    ),
    home: DashboardScreen(
      controller: _controller,
      locale: _locale,
      onLocaleChanged: (locale) => setState(() => _locale = locale),
    ),
  );
}
