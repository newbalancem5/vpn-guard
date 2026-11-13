enum NetworkIssue {
  cancelled,
  networkChanged,
  invalidIp,
  invalidGeolocation,
  rateLimited,
  proxyUnsupported,
  addressUnavailable,
  familyUnavailable,
  httpError,
  responseTooLarge,
  invalidResponse,
  timeout,
  connectionFailed,
  tlsFailed,
  failed,
  expired,
  resumed,
  networkStateUnavailable,
}

class NetworkFailure implements Exception {
  const NetworkFailure(this.code, {this.httpStatus});
  final NetworkIssue code;
  final int? httpStatus;
}
