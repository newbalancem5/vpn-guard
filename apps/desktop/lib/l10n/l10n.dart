import 'package:flutter/widgets.dart';

import '../features/network/domain/network_failure.dart';
import '../features/protection/domain/guard_backend.dart';
import 'generated/app_localizations.dart';

extension LocalizedContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension LocalizedNetworkFailure on NetworkFailure {
  String localized(AppLocalizations l10n) => switch (code) {
    NetworkIssue.cancelled => l10n.networkCancelled,
    NetworkIssue.networkChanged => l10n.networkChanged,
    NetworkIssue.invalidIp => l10n.invalidIp,
    NetworkIssue.invalidGeolocation => l10n.invalidGeolocation,
    NetworkIssue.rateLimited => l10n.rateLimited,
    NetworkIssue.proxyUnsupported => l10n.proxyUnsupported,
    NetworkIssue.addressUnavailable => l10n.addressUnavailable,
    NetworkIssue.familyUnavailable => l10n.familyUnavailable,
    NetworkIssue.httpError => l10n.httpError(httpStatus ?? 0),
    NetworkIssue.responseTooLarge => l10n.responseTooLarge,
    NetworkIssue.invalidResponse => l10n.invalidResponse,
    NetworkIssue.timeout => l10n.networkTimeout,
    NetworkIssue.connectionFailed => l10n.connectionFailed,
    NetworkIssue.tlsFailed => l10n.networkTlsFailed,
    NetworkIssue.failed => l10n.networkFailed,
    NetworkIssue.expired => l10n.networkExpired,
    NetworkIssue.resumed => l10n.networkResumed,
    NetworkIssue.networkStateUnavailable => l10n.networkStateUnavailable,
  };
}

extension LocalizedBackendIssue on BackendIssue {
  String localized(AppLocalizations l10n) => switch (this) {
    BackendIssue.none => l10n.filterConnected,
    BackendIssue.notConnected => l10n.backendNotConnected,
    BackendIssue.unsupportedProtocol => l10n.backendUnsupported,
    BackendIssue.unavailable => l10n.backendUnavailable,
  };
}
