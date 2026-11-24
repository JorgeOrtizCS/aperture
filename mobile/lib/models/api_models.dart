// See ApiService.contractRevision for the source used to verify this contract.
// Endpoint-specific casing is intentional (DTOs versus anonymous responses).
import 'location_radius_policy.dart';

enum ApiFailure {
  configuration,
  httpDemoAnonymousOnly,
  credentials,
  denied,
  notFound,
  invalidRequest,
  timeout,
  network,
  server,
  malformed,
  stale,
  pending,
  ownerControlUnconfirmed,
  cancelled,
  uploadUnverified,
  uploadUnconfirmed,
  unsupportedViewingPolicy,
}

class ApiException implements Exception {
  final ApiFailure kind;
  const ApiException(this.kind);

  String get message => switch (kind) {
    ApiFailure.configuration =>
      'An approved HTTPS API environment is not configured.',
    ApiFailure.httpDemoAnonymousOnly =>
      'Sign-in requires HTTPS or an isolated loopback demo connection.',
    ApiFailure.credentials =>
      'Sign-in was rejected or has expired. Please sign in again.',
    ApiFailure.denied => 'The server denied this action.',
    ApiFailure.notFound =>
      'This content or session is unavailable to this account.',
    ApiFailure.invalidRequest => 'The server rejected this request.',
    ApiFailure.timeout => 'The request timed out. Its server outcome is unknown. Refresh before retrying.',
    ApiFailure.network =>
      'The API could not be reached. Check the connection and retry.',
    ApiFailure.server => 'The API could not complete the request.',
    ApiFailure.malformed =>
      'The API returned an unexpected response. Access remains locked.',
    ApiFailure.stale =>
      'The account or viewing session changed. This response was discarded.',
    ApiFailure.pending => 'An action is already pending.',
    ApiFailure.ownerControlUnconfirmed => 'An owner action is unconfirmed. Authoritative reconciliation is required before another change.',
    ApiFailure.cancelled => 'Submission cancelled.',
    ApiFailure.unsupportedViewingPolicy => 'This device cannot verify a required viewing policy. Content stays hidden.',
    ApiFailure.uploadUnverified =>
      'Secure upload is unavailable until the backend contract is verified.',
    ApiFailure.uploadUnconfirmed => 'The server outcome is unknown. Do not submit again until it has been reconciled.',
  };

  // Never include response bodies, credentials or tokens in errors/logs.
  @override
  String toString() => 'ApiException(${kind.name})';
}

Map<String, dynamic> apiObject(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const ApiException(ApiFailure.malformed);
  }
  return value;
}

String apiString(dynamic value) {
  if (value is! String || value.trim().isEmpty) {
    throw const ApiException(ApiFailure.malformed);
  }
  return value;
}

int apiId(dynamic value) {
  if (value is! int || value <= 0) {
    throw const ApiException(ApiFailure.malformed);
  }
  return value;
}

bool apiBool(dynamic value) {
  if (value is! bool) throw const ApiException(ApiFailure.malformed);
  return value;
}

DateTime apiUtc(dynamic value) {
  final match = value is String
      ? RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$',
        ).firstMatch(value)
      : null;
  if (match == null) {
    throw const ApiException(ApiFailure.malformed);
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final calendar = DateTime.utc(parts[0], parts[1], parts[2]);
  if (calendar.year != parts[0] ||
      calendar.month != parts[1] ||
      calendar.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59) {
    throw const ApiException(ApiFailure.malformed);
  }
  if (match[7] != 'Z') {
    final zone = match[7]!.substring(1).split(':').map(int.parse).toList();
    if (zone[0] > 23 || zone[1] > 59) {
      throw const ApiException(ApiFailure.malformed);
    }
  }
  final date = DateTime.tryParse(value as String);
  if (date == null) throw const ApiException(ApiFailure.malformed);
  return date.toUtc();
}

class ApiUser {
  final int id;
  final String username;
  const ApiUser(this.id, this.username);
}

class ApiCredentials {
  final String token;
  final DateTime expiresAt;
  final ApiUser user;
  const ApiCredentials(this.token, this.expiresAt, this.user);

  @override
  String toString() => 'ApiCredentials(redacted)';
}

class ApiContent {
  final int id;
  final String title, owner, status, policyStatus;
  final String? recipient;
  final bool mine;
  final bool requiresPreciseLocation, requiresTrustedDevice;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final LocationZone? locationZone;

  const ApiContent({
    required this.id,
    required this.title,
    required this.owner,
    required this.status,
    required this.policyStatus,
    required this.mine,
    required this.createdAt,
    this.expiresAt,
    this.recipient,
    this.requiresPreciseLocation = false,
    this.requiresTrustedDevice = false,
    this.locationZone,
  });

  factory ApiContent.fromJson(dynamic value) {
    final j = apiObject(value);
    final status = apiString(j['Status']);
    final policy = apiString(j['PolicyStatus']);
    if (!{'Active', 'Revoked'}.contains(status) ||
        !{'Active', 'Paused'}.contains(policy)) {
      throw const ApiException(ApiFailure.malformed);
    }
    final mine = apiBool(j['Mine']);
    final recipient = j['Recipient'];
    if (recipient != null && recipient is! String) {
      throw const ApiException(ApiFailure.malformed);
    }
    if (mine) apiString(recipient);
    final coordinates = [j['Latitude'], j['Longitude'], j['RadiusMeters']];
    final precise = coordinates.any((v) => v != null);
    if (precise &&
        (coordinates.any((v) => v is! num || !v.isFinite) ||
            (coordinates[0] as num).abs() > 90 ||
            (coordinates[1] as num).abs() > 180 ||
            (coordinates[2] as num) <= 0)) {
      throw const ApiException(ApiFailure.malformed);
    }
    // Listing metadata never authorizes rendering. Body/image fields, if sent,
    // are not retained in this model. No guessed policy defaults grant access.
    return ApiContent(
      id: apiId(j['Id']),
      title: apiString(j['Title']),
      owner: apiString(j['Owner']),
      status: status,
      policyStatus: policy,
      mine: mine,
      createdAt: apiUtc(j['CreatedAt']),
      expiresAt: _optionalExpiry(j['ExpiresAt']),
      recipient: recipient as String?,
      requiresPreciseLocation: precise,
      locationZone: precise
          ? LocationZone(
              (coordinates[0] as num).toDouble(),
              (coordinates[1] as num).toDouble(),
              (coordinates[2] as num).toDouble(),
            )
          : null,
      requiresTrustedDevice: j['RequireTrustedDevice'] == null
          ? false
          : apiBool(j['RequireTrustedDevice']),
    );
  }

  // An optional listing timestamp is used only for a status notice.
  static DateTime? _optionalExpiry(Object? value) {
    if (value == null) return null;
    try {
      return apiUtc(value);
    } on ApiException {
      return null;
    }
  }

  ApiContent confirmed({
    String? status,
    String? policyStatus,
    LocationZone? zone,
  }) => ApiContent(
    id: id,
    title: title,
    owner: owner,
    mine: mine,
    createdAt: createdAt,
    expiresAt: expiresAt,
    recipient: recipient,
    requiresPreciseLocation: requiresPreciseLocation || zone != null,
    locationZone: zone ?? locationZone,
    requiresTrustedDevice: requiresTrustedDevice,
    status: status ?? this.status,
    policyStatus: policyStatus ?? this.policyStatus,
  );
}

class ApiAccessDecision {
  final int? sessionId;
  final bool granted, suspended, ended;
  final bool refusedByHttp;
  final bool deviceVerified;
  const ApiAccessDecision({
    this.sessionId,
    required this.granted,
    this.suspended = false,
    this.ended = false,
    this.refusedByHttp = false,
    this.deviceVerified = false,
  });

  factory ApiAccessDecision.fromJson(dynamic value) {
    final j = apiObject(value);
    final ended = apiBool(j['SessionEnded']);
    final id = j['SessionId'];
    // A terminal assertion wins even when the rest of the response is
    // contradictory/malformed. A later grant must not resurrect that session.
    final safeId = id is int && id > 0 ? id : null;
    if (ended) {
      return ApiAccessDecision(sessionId: safeId, granted: false, ended: true);
    }
    final suspended = apiBool(j['Suspended']);
    if (suspended) {
      return ApiAccessDecision(
        sessionId: safeId,
        granted: false,
        suspended: true,
      );
    }
    final granted = apiBool(j['AccessGranted']);
    if (id != null && (id is! int || id < 0)) {
      throw const ApiException(ApiFailure.malformed);
    }
    if (granted) {
      apiId(id);
      apiBool(j['DeviceVerified']);
      if (!apiBool(j['LocationVerified'])) {
        throw const ApiException(ApiFailure.malformed);
      }
      final camera = apiObject(j['CameraRestrictions']);
      for (final key in [
        'Enabled',
        'BlockPhones',
        'BlockMultiplePeople',
        'RequireViewer',
      ]) {
        apiBool(camera[key]);
      }
      // Mobile does not claim protocol-v1 sender camera semantics. An enabled
      // policy unexpectedly accepted by a server must still fail closed here.
      if (camera['Enabled'] == true ||
          camera['BlockPhones'] == true ||
          camera['BlockMultiplePeople'] == true ||
          camera['RequireViewer'] == true) {
        throw const ApiException(ApiFailure.unsupportedViewingPolicy);
      }
    }
    // File Body/Base64 is deliberately discarded. The encrypted delivery and
    // rendering lifecycle is not supplied by this API contract.
    return ApiAccessDecision(
      sessionId: id is int && id > 0 ? id : null,
      granted: granted,
      suspended: suspended,
      ended: ended,
      deviceVerified: granted && apiBool(j['DeviceVerified']),
    );
  }
}
