import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../app/app_metadata.dart';
import '../../admission/domain/region_policy.dart';
import '../../network/application/network_controller.dart';
import '../../network/domain/network_failure.dart';
import '../../network/domain/network_models.dart';
import '../../protection/domain/guard_backend.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({
    required this.backend,
    this.network,
    this.networkChanges,
  });
  final GuardBackend backend;
  final NetworkController? network;
  final Stream<void>? networkChanges;
  BackendReport? report;
  bool loading = true;
  bool performingAction = false;
  String? actionError;
  DateTime? checkedAt;
  StreamSubscription<void>? _pathEvents;
  bool _disposed = false;
  bool _started = false;
  int _generation = 0;

  void start() {
    if (_started) return;
    _started = true;
    network?.addListener(_networkChanged);
    network?.start();
    _pathEvents = networkChanges?.listen(
      (_) => recheck(NetworkIssue.networkChanged),
      onError: (_) {},
    );
    refresh(includeNetwork: false);
  }

  void _networkChanged() {
    if (!_disposed) notifyListeners();
  }

  void recheck(NetworkIssue reason) {
    network?.invalidate(reason);
    network?.refresh();
  }

  Future<void> refresh({bool includeNetwork = true}) async {
    if (_disposed) return;
    if (includeNetwork) unawaited(network?.refresh());
    final generation = ++_generation;
    loading = true;
    notifyListeners();
    BackendReport result;
    try {
      result = await backend.inspect().timeout(const Duration(seconds: 5));
    } catch (_) {
      result = const BackendReport(
        platform: 'unknown',
        issue: BackendIssue.unavailable,
      );
    }
    if (_disposed || generation != _generation) return;
    report = result;
    loading = false;
    checkedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> perform(GuardAction action) async {
    if (_disposed || performingAction) return;
    performingAction = true;
    actionError = null;
    notifyListeners();
    try {
      await backend.perform(action);
    } on GuardOperationFailure catch (error) {
      actionError = error.code;
    } catch (_) {
      actionError = 'unknown';
    }
    if (_disposed) return;
    performingAction = false;
    await refresh(includeNetwork: false);
  }

  FamilyObservation? family(AddressFamily family) {
    for (final observation
        in network?.observation?.families ?? <FamilyObservation>[]) {
      if (observation.family == family) return observation;
    }
    return null;
  }

  String get diagnostics => const JsonEncoder.withIndent('  ').convert({
    'app': AppMetadata.name,
    'version': AppMetadata.version,
    'platform': report?.platform ?? 'unknown',
    'backend': report?.issue.name ?? 'checking',
    'extensionState': report?.extensionState.name,
    'configurationEnabled': report?.configurationEnabled,
    'filterMode': report?.mode,
    'antigravityFound': report?.antigravityFound,
    'languageServerCurrent': report?.languageServerCurrent,
    'actionError': actionError,
    'protectionVerified': false,
    'externalIp': null,
    'admissionGranted': false,
    'network': network?.observation?.families.map((f) => f.toJson()).toList(),
    'networkError': network?.error?.code.name,
    'countryRulesVerifiedAt': RegionPolicy.verifiedAt.toIso8601String(),
    'countryRulesExpiresAt': RegionPolicy.expiresAt.toIso8601String(),
    'countryRulesSources': {
      for (final item in RegionPolicy.sources.entries)
        item.key.name: item.value,
    },
    'checkedAt': checkedAt?.toUtc().toIso8601String(),
  });

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pathEvents?.cancel();
    network?.removeListener(_networkChanged);
    network?.dispose();
    super.dispose();
  }
}
