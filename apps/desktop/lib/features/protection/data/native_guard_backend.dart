import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/guard_backend.dart';

class NativeGuardBackend extends GuardBackend {
  const NativeGuardBackend();
  static const channel = MethodChannel('org.vpnguard/backend');

  @override
  Future<BackendReport> inspect() async {
    final platform = Platform.operatingSystem;
    try {
      final raw = await channel.invokeMapMethod<String, Object?>('getStatus');
      final states = ExtensionState.values.where(
        (v) => v.name == raw?['extensionState'],
      );
      if (raw == null ||
          raw['protocolVersion'] != 1 ||
          raw['platform'] != 'macos' ||
          states.isEmpty ||
          raw['capable'] is! bool ||
          raw['configurationEnabled'] is! bool ||
          raw['antigravityFound'] is! bool ||
          raw['languageServerCovered'] is! bool ||
          raw['mode'] is! String ||
          raw['protectionVerified'] != false) {
        return BackendReport(
          platform: platform,
          issue: BackendIssue.unsupportedProtocol,
        );
      }
      return BackendReport(
        platform: platform,
        issue: BackendIssue.none,
        capable: raw['capable'] == true,
        extensionState: states.single,
        configurationEnabled: raw['configurationEnabled'] == true,
        antigravityFound: raw['antigravityFound'] == true,
        languageServerCovered: raw['languageServerCovered'] == true,
        languageServerCurrent: raw['languageServerCurrent'] == true,
        mode: raw['mode'] as String,
      );
    } on MissingPluginException {
      return BackendReport(
        platform: platform,
        issue: BackendIssue.notConnected,
      );
    } on PlatformException {
      return BackendReport(platform: platform, issue: BackendIssue.unavailable);
    } catch (_) {
      return BackendReport(
        platform: platform,
        issue: BackendIssue.unsupportedProtocol,
      );
    }
  }

  @override
  Future<void> perform(GuardAction action) async {
    try {
      await channel
          .invokeMethod<Object?>(action.name)
          .timeout(const Duration(seconds: 30));
    } on PlatformException catch (error) {
      throw GuardOperationFailure(error.code);
    } on MissingPluginException {
      throw const GuardOperationFailure('unsupported');
    } catch (_) {
      throw const GuardOperationFailure('unknown');
    }
  }
}
