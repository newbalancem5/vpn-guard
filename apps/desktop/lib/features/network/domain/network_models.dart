import 'network_failure.dart';

enum AddressFamily { ipv4, ipv6 }

class GeoLocation {
  const GeoLocation({
    required this.ip,
    required this.countryCode,
    required this.country,
    required this.region,
    required this.checkedAt,
  });
  final String ip;
  final String countryCode;
  final String country;
  final String region;
  final DateTime checkedAt;
}

class RouteObservation {
  const RouteObservation({
    required this.remoteAddress,
    required this.interfaceName,
    required this.tunnelCandidate,
  });
  final String remoteAddress;
  final String? interfaceName;
  final bool tunnelCandidate;

  Map<String, Object?> toJson() => {
    'interface': interfaceName,
    'tunnelCandidate': tunnelCandidate,
    'routeEnforced': false,
  };
}

class FamilyObservation {
  const FamilyObservation({
    required this.family,
    required this.checkedAt,
    this.ip,
    this.geo,
    this.route,
    this.error,
  });
  final AddressFamily family;
  final DateTime checkedAt;
  final String? ip;
  final GeoLocation? geo;
  final RouteObservation? route;
  final NetworkFailure? error;

  bool isFresh(DateTime now) =>
      !now.isBefore(checkedAt) &&
      now.difference(checkedAt) < const Duration(seconds: 75);

  Map<String, Object?> toJson({bool includeIp = false}) => {
    'family': family.name,
    'ip': includeIp ? ip : null,
    'countryCode': geo?.countryCode,
    'region': geo?.region,
    'route': route?.toJson(),
    'error': error?.code.name,
    'httpStatus': error?.httpStatus,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
  };
}

class NetworkObservation {
  const NetworkObservation({required this.families, required this.fingerprint});
  final List<FamilyObservation> families;
  final String fingerprint;
}
