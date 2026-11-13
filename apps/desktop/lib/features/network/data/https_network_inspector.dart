import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/network_models.dart';
import '../domain/network_inspector.dart';
import '../domain/network_failure.dart';
import 'system_route_lookup.dart';

class _Response {
  const _Response(this.json, this.route);
  final Map<String, dynamic> json;
  final RouteObservation? route;
}

class HttpsNetworkInspector implements NetworkInspector {
  final Map<String, GeoLocation> _geoCache = {};
  DateTime? _geoRetryAt;
  final _routes = SystemRouteLookup();

  static Future<List<NetworkInterface>> interfaces() => NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: false,
  ).timeout(const Duration(seconds: 3));

  static String describeInterfaces(List<NetworkInterface> interfaces) {
    final values = [
      for (final interface in interfaces)
        '${interface.index}:${interface.name}:${(interface.addresses.map((a) => a.address).toList()..sort()).join(',')}',
    ];
    return (values..sort()).join('|');
  }

  @override
  Future<String> fingerprint() async => describeInterfaces(await interfaces());

  @override
  Future<NetworkObservation> inspect(CheckSession session) async {
    final before = await interfaces();
    session.ensureActive();
    final results = await Future.wait([
      for (final family in AddressFamily.values)
        _inspectFamily(family, session),
    ]);
    session.ensureActive();
    final after = await interfaces();
    final stable = describeInterfaces(before) == describeInterfaces(after);
    return NetworkObservation(
      fingerprint: describeInterfaces(after),
      families: stable
          ? results
          : [
              for (final family in AddressFamily.values)
                FamilyObservation(
                  family: family,
                  checkedAt: DateTime.now(),
                  error: const NetworkFailure(NetworkIssue.networkChanged),
                ),
            ],
    );
  }

  Future<FamilyObservation> _inspectFamily(
    AddressFamily family,
    CheckSession session,
  ) async {
    String? ip;
    RouteObservation? route;
    try {
      final type = family == AddressFamily.ipv4
          ? InternetAddressType.IPv4
          : InternetAddressType.IPv6;
      final host = family == AddressFamily.ipv4
          ? 'api.ipify.org'
          : 'api6.ipify.org';
      final response = await _getJson(
        Uri.https(host, '/', {'format': 'json'}),
        session,
        type: type,
      );
      session.ensureActive();
      ip = parseIp(response.json, family);
      route = response.route;
      final geo = await _geolocate(ip, session);
      session.ensureActive();
      return FamilyObservation(
        family: family,
        checkedAt: DateTime.now(),
        ip: ip,
        geo: geo,
        route: route,
      );
    } catch (error) {
      session.ensureActive();
      return FamilyObservation(
        family: family,
        checkedAt: DateTime.now(),
        ip: ip,
        route: route,
        error: failureFor(error),
      );
    }
  }

  static String parseIp(Map<String, dynamic> json, AddressFamily family) {
    final value = json['ip'];
    final address = value is String ? InternetAddress.tryParse(value) : null;
    final expected = family == AddressFamily.ipv4
        ? InternetAddressType.IPv4
        : InternetAddressType.IPv6;
    if (address == null ||
        address.type != expected ||
        address.isLoopback ||
        address.isLinkLocal ||
        address.address == '0.0.0.0' ||
        address.address == '::') {
      throw const NetworkFailure(NetworkIssue.invalidIp);
    }
    return address.address;
  }

  static bool sameIp(String? first, String? second) {
    if (first == null || second == null) return false;
    final a = InternetAddress.tryParse(first)?.rawAddress;
    final b = InternetAddress.tryParse(second)?.rawAddress;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static GeoLocation parseGeo(
    Map<String, dynamic> json,
    String requestedIp,
    DateTime now,
  ) {
    final responseIp = json['ip'];
    final code = json['country_code'];
    if (json['success'] != true ||
        responseIp is! String ||
        !sameIp(responseIp, requestedIp) ||
        code is! String ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(code) ||
        {'XX', 'ZZ'}.contains(code)) {
      throw const NetworkFailure(NetworkIssue.invalidGeolocation);
    }
    return GeoLocation(
      ip: requestedIp,
      countryCode: code,
      country: json['country'] is String ? json['country'] as String : code,
      region: json['region'] is String ? json['region'] as String : '',
      checkedAt: now,
    );
  }

  Future<GeoLocation> _geolocate(String ip, CheckSession session) async {
    final now = DateTime.now();
    final cached = _geoCache[ip];
    if (cached != null &&
        !now.isBefore(cached.checkedAt) &&
        now.difference(cached.checkedAt) < const Duration(hours: 6)) {
      return cached;
    }
    if (_geoRetryAt != null && now.isBefore(_geoRetryAt!)) {
      throw const NetworkFailure(NetworkIssue.rateLimited);
    }
    final response = await _getJson(
      Uri.https('ipwho.is', '/$ip', {
        'fields': 'ip,success,country,country_code,region',
      }),
      session,
      geolocation: true,
    );
    final geo = parseGeo(response.json, ip, now);
    session.ensureActive();
    if (_geoCache.length >= 32) _geoCache.remove(_geoCache.keys.first);
    _geoCache[ip] = geo;
    return geo;
  }

  Future<_Response> _getJson(
    Uri uri,
    CheckSession session, {
    InternetAddressType type = InternetAddressType.any,
    bool geolocation = false,
  }) async {
    session.ensureActive();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..findProxy = (_) => 'DIRECT';
    final removeClient = session.onCancel(() => client.close(force: true));
    InternetAddress? remote;
    String? routeBefore;
    bool closed = false;
    final removeTasks = <void Function()>[];
    final tasks = <ConnectionTask<Socket>>[];
    final sockets = <Socket>{};
    client.connectionFactory = (url, proxyHost, proxyPort) async {
      if (proxyHost != null || url.scheme != 'https') {
        throw const NetworkFailure(NetworkIssue.proxyUnsupported);
      }
      final List<InternetAddress> addresses;
      try {
        addresses = await InternetAddress.lookup(
          url.host,
          type: type,
        ).timeout(const Duration(seconds: 5));
      } on SocketException {
        if (type == InternetAddressType.any) rethrow;
        // macOS returns no records of a family the host cannot route, so a
        // failed lookup without a global local address means "no such family".
        final local = await interfaces().catchError(
          (_) => const <NetworkInterface>[],
        );
        throw NetworkFailure(
          lookupFailure(type, [for (final i in local) ...i.addresses]),
        );
      }
      session.ensureActive();
      if (closed) throw const NetworkFailure(NetworkIssue.cancelled);
      if (addresses.isEmpty) {
        throw const NetworkFailure(NetworkIssue.addressUnavailable);
      }
      // Numeric address preserves the requested family; there is no IPv6 -> IPv4 fallback.
      if (type != InternetAddressType.any) {
        routeBefore = await _routes.interfaceFor(addresses.first);
      }
      session.ensureActive();
      if (closed) throw const NetworkFailure(NetworkIssue.cancelled);
      final task = await Socket.startConnect(addresses.first, url.port);
      tasks.add(task);
      removeTasks.add(session.onCancel(task.cancel));
      if (session.cancelled || closed) {
        task.cancel();
        throw const NetworkFailure(NetworkIssue.cancelled);
      }
      return ConnectionTask.fromSocket(
        task.socket.then((socket) async {
          if (session.cancelled || closed) {
            socket.destroy();
            throw const NetworkFailure(NetworkIssue.cancelled);
          }
          sockets.add(socket);
          remote = socket.remoteAddress;
          // A custom HttpClient factory owns TLS as well as TCP. Keep the original
          // hostname for SNI and certificate verification while forcing IP family.
          final unregister = session.onCancel(socket.destroy);
          try {
            final secure = await SecureSocket.secure(socket, host: url.host);
            if (session.cancelled || closed) {
              secure.destroy();
              throw const NetworkFailure(NetworkIssue.cancelled);
            }
            sockets.remove(socket);
            sockets.add(secure);
            return secure;
          } finally {
            unregister();
          }
        }),
        task.cancel,
      );
    };
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode == 429 && geolocation) {
          final retry =
              int.tryParse(
                response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
              ) ??
              86400;
          _geoRetryAt = DateTime.now().add(
            Duration(seconds: retry.clamp(60, 86400)),
          );
          throw const NetworkFailure(NetworkIssue.rateLimited);
        }
        if (response.statusCode != 200) {
          throw NetworkFailure(
            NetworkIssue.httpError,
            httpStatus: response.statusCode,
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 16384) {
            throw const NetworkFailure(NetworkIssue.responseTooLarge);
          }
        }
        session.ensureActive();
        final json = jsonDecode(utf8.decode(bytes));
        if (json is! Map<String, dynamic>) {
          throw const NetworkFailure(NetworkIssue.invalidResponse);
        }
        RouteObservation? route;
        if (remote != null && type != InternetAddressType.any) {
          final after = await _routes.interfaceFor(remote!);
          if (routeBefore != null && after != null && after != routeBefore) {
            throw const NetworkFailure(NetworkIssue.networkChanged);
          }
          final name = after == routeBefore ? after : null;
          route = RouteObservation(
            remoteAddress: remote!.address,
            interfaceName: name,
            tunnelCandidate:
                name != null &&
                (RegExp(r'^utun\d+$').hasMatch(name) ||
                    RegExp(
                      r'amnezia|wireguard|wintun|\btun\b',
                      caseSensitive: false,
                    ).hasMatch(name)),
          );
        }
        return _Response(json, route);
      })().timeout(const Duration(seconds: 10));
    } finally {
      closed = true;
      for (final remove in removeTasks) {
        remove();
      }
      for (final task in tasks) {
        task.cancel();
      }
      for (final socket in sockets) {
        socket.destroy();
      }
      client.close(force: true);
      removeClient();
    }
  }

  /// Distinguishes a network without the requested family from a DNS failure.
  /// IPv6 counts only with a global unicast address (2000::/3): link-local and
  /// ULA addresses such as a VPN's `fd00::/8` do not reach the internet.
  static NetworkIssue lookupFailure(
    InternetAddressType type,
    Iterable<InternetAddress> local,
  ) {
    final routable = local.any((address) {
      if (address.type != type || address.isLoopback || address.isLinkLocal) {
        return false;
      }
      if (type == InternetAddressType.IPv6) {
        return address.rawAddress[0] & 0xE0 == 0x20;
      }
      return true;
    });
    return routable
        ? NetworkIssue.connectionFailed
        : NetworkIssue.familyUnavailable;
  }

  static NetworkFailure failureFor(Object error) {
    if (error is NetworkFailure) return error;
    if (error is TimeoutException) {
      return const NetworkFailure(NetworkIssue.timeout);
    }
    if (error is SocketException) {
      return const NetworkFailure(NetworkIssue.connectionFailed);
    }
    if (error is HandshakeException) {
      return const NetworkFailure(NetworkIssue.tlsFailed);
    }
    return const NetworkFailure(NetworkIssue.failed);
  }
}
