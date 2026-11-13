import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Read-only route observation for the actual numeric peer. Failure remains unknown.
/// No route is changed, and no interface name is treated as authenticated VPN proof.
class SystemRouteLookup {
  Future<String?> interfaceFor(InternetAddress address) async {
    final numeric = address.address;
    if (!RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(numeric)) return null;
    Process? process;
    try {
      if (Platform.isMacOS) {
        process = await Process.start('/sbin/route', ['-n', 'get', numeric]);
      } else if (Platform.isWindows) {
        final systemRoot = Platform.environment['SystemRoot'];
        if (systemRoot == null) return null;
        process = await Process.start(
          '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
          [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            '\$ErrorActionPreference = "Stop"; (Find-NetRoute -RemoteIPAddress "$numeric" | Select-Object -First 1).InterfaceAlias',
          ],
        );
      } else {
        return null;
      }
      final output = process.stdout
          .transform(utf8.decoder)
          .join()
          .catchError((Object _) => '');
      final errors = process.stderr.drain<void>().catchError((Object _) {});
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
      );
      final text = await output;
      await errors;
      if (exitCode != 0) return null;
      return Platform.isMacOS
          ? parseMacRoute(text)
          : (text.trim().isEmpty ? null : text.trim());
    } catch (_) {
      return null;
    } finally {
      process?.kill();
    }
  }

  static String? parseMacRoute(String output) => RegExp(
    r'^\s*interface:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(output)?.group(1);
}
