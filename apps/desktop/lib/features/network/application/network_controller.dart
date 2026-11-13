import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/network_inspector.dart';
import '../domain/network_failure.dart';
import '../domain/network_models.dart';

/// Diagnostic lifecycle only. It never modifies system firewall permissions.
class NetworkController extends ChangeNotifier {
  NetworkController(this.inspector);
  final NetworkInspector inspector;
  NetworkObservation? observation;
  bool checking = false;
  NetworkFailure? error;
  int _generation = 0;
  bool _disposed = false;
  bool _polling = false;
  String? _fingerprint;
  CheckSession? _session;
  Timer? _refreshTimer;
  Timer? _interfaceTimer;
  Timer? _expiryTimer;

  void start() {
    if (_refreshTimer != null) return;
    refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!checking) refresh();
    });
    _interfaceTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollInterfaces(),
    );
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (observation != null &&
          observation!.families.any((f) => !f.isFresh(DateTime.now()))) {
        invalidate(NetworkIssue.expired);
        refresh();
      }
    });
  }

  void invalidate(NetworkIssue reason) {
    if (_disposed) return;
    _generation++;
    _session?.cancel();
    observation = null;
    checking = false;
    error = NetworkFailure(reason);
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    _session?.cancel();
    final generation = ++_generation;
    final session = CheckSession();
    _session = session;
    observation = null;
    error = null;
    checking = true;
    notifyListeners();
    try {
      final result = await inspector
          .inspect(session)
          .timeout(const Duration(seconds: 25));
      if (_disposed || generation != _generation || session.cancelled) return;
      observation = result;
      _fingerprint = result.fingerprint;
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      error = exception is NetworkFailure
          ? exception
          : NetworkFailure(
              exception is TimeoutException
                  ? NetworkIssue.timeout
                  : NetworkIssue.failed,
            );
    } finally {
      session.cancel();
      if (!_disposed && generation == _generation) {
        checking = false;
        notifyListeners();
      }
    }
  }

  Future<void> _pollInterfaces() async {
    if (_disposed || _polling) return;
    _polling = true;
    final generation = _generation;
    try {
      final current = await inspector.fingerprint();
      if (_disposed || generation != _generation) return;
      if (_fingerprint != null && current != _fingerprint) {
        _fingerprint = current;
        invalidate(NetworkIssue.networkChanged);
        refresh();
      } else {
        _fingerprint ??= current;
      }
    } catch (_) {
      if (!_disposed && generation == _generation && observation != null) {
        invalidate(NetworkIssue.networkStateUnavailable);
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _session?.cancel();
    _refreshTimer?.cancel();
    _interfaceTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }
}
