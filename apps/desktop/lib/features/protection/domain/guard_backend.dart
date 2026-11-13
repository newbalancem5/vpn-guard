enum BackendIssue { none, notConnected, unsupportedProtocol, unavailable }

enum GuardAction {
  installFilter,
  enableAntigravity,
  disableFilter,
  openAntigravity,
}

enum ExtensionState {
  unavailable,
  unknown,
  notInstalled,
  needsApproval,
  installed,
  updateRequired,
  rebootRequired,
}

abstract class GuardBackend {
  const GuardBackend();
  Future<BackendReport> inspect();
  Future<void> perform(GuardAction action) =>
      Future.error(const GuardOperationFailure('unsupported'));
}

class GuardOperationFailure implements Exception {
  const GuardOperationFailure(this.code);
  final String code;
}

class BackendReport {
  const BackendReport({
    required this.platform,
    required this.issue,
    this.capable = false,
    this.extensionState = ExtensionState.unavailable,
    this.configurationEnabled = false,
    this.antigravityFound = false,
    this.languageServerCovered = false,
    this.languageServerCurrent = false,
    this.mode = 'none',
  });
  final String platform;
  final BackendIssue issue;
  final bool capable;
  final ExtensionState extensionState;
  final bool configurationEnabled;
  final bool antigravityFound;
  final bool languageServerCovered;
  final bool languageServerCurrent;
  final String mode;
  bool get antigravityConfigured =>
      configurationEnabled && mode == 'block-antigravity-v1';
  bool get canEnable =>
      capable &&
      extensionState == ExtensionState.installed &&
      antigravityFound &&
      languageServerCovered;
}
