import 'network_failure.dart';
import 'network_models.dart';

abstract interface class NetworkInspector {
  Future<NetworkObservation> inspect(CheckSession session);
  Future<String> fingerprint();
}

/// Cancellation is independent of HTTP, sockets and Flutter.
class CheckSession {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  final _callbacks = <void Function()>{};

  void ensureActive() {
    if (_cancelled) throw const NetworkFailure(NetworkIssue.cancelled);
  }

  void Function() onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in _callbacks.toList()) {
      callback();
    }
    _callbacks.clear();
  }
}
