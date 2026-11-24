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
  usernameUnavailable,
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
    ApiFailure.usernameUnavailable => 'This username is already in use.',
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

typedef ApiTimeWindow = ({DateTime? startTime, DateTime? expiresAt});
typedef ApiListedPolicy = ({
  ApiTimeWindow window,
  int? maxViews,
  bool? screenshotRestriction,
  bool requiresTrustedDevice,
  LocationZone? locationZone,
  NetworkLocation networkLocation,
});

class ApiContent {
  final int id;
  final String title, owner, status, policyStatus;
  final String? recipient;
  final bool mine;
  final bool requiresPreciseLocation, requiresTrustedDevice;
  final DateTime createdAt;
  final DateTime? startTime, expiresAt;
  final int? maxViews;
  final bool? screenshotRestriction;
  final LocationZone? locationZone;
  final NetworkLocation networkLocation;

  const ApiContent({
    required this.id,
    required this.title,
    required this.owner,
    required this.status,
    required this.policyStatus,
    required this.mine,
    required this.createdAt,
    this.startTime,
    this.expiresAt,
    this.maxViews,
    this.screenshotRestriction,
    this.recipient,
    this.requiresPreciseLocation = false,
    this.requiresTrustedDevice = false,
    this.locationZone,
    this.networkLocation = const NetworkLocation(),
  });

  ApiListedPolicy get listedPolicy => (
    window: (startTime: startTime, expiresAt: expiresAt),
    maxViews: maxViews,
    screenshotRestriction: screenshotRestriction,
    requiresTrustedDevice: requiresTrustedDevice,
    locationZone: locationZone,
    networkLocation: networkLocation,
  );

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
    final networkLocation = precise
        ? const NetworkLocation()
        : NetworkLocation(
            country: _optionalLocation(j['AllowedCountry']),
            region: _optionalLocation(j['AllowedRegion']),
            city: _optionalLocation(j['AllowedCity']),
          );
    if (!networkLocation.valid) throw const ApiException(ApiFailure.malformed);
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
      startTime: _optionalTime(j['StartTime']),
      expiresAt: _optionalTime(j['ExpiresAt']),
      maxViews: j['MaxViews'] == null ? null : apiId(j['MaxViews']),
      screenshotRestriction: j['ScreenshotRestriction'] == null
          ? null
          : apiBool(j['ScreenshotRestriction']),
      networkLocation: networkLocation,
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

  static String _optionalLocation(Object? value) {
    if (value == null) return '';
    if (value is! String) throw const ApiException(ApiFailure.malformed);
    return value.trim();
  }

  // An optional listing timestamp is used only for a status notice.
  static DateTime? _optionalTime(Object? value) {
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
    startTime: startTime,
    expiresAt: expiresAt,
    maxViews: maxViews,
    screenshotRestriction: screenshotRestriction,
    recipient: recipient,
    requiresPreciseLocation: requiresPreciseLocation || zone != null,
    locationZone: zone ?? locationZone,
    networkLocation: zone == null ? networkLocation : const NetworkLocation(),
    requiresTrustedDevice: requiresTrustedDevice,
    status: status ?? this.status,
    policyStatus: policyStatus ?? this.policyStatus,
  );
}

// Source-defined denial messages are mapped to local copy. Unknown messages,
// and any payload included with a denial, are never shown or retained.
enum ApiAccessDenial {
  notStarted('The sender’s viewing window has not opened yet.'),
  policyExpired('The sender’s viewing time limit has expired.'),
  viewLimit('The sender’s viewing limit has been reached.'),
  deviceApproval('The sender requires a device approved by the service.'),
  networkLocation(
    'The service reported that the network location did not meet the viewing policy.',
  ),
  cameraPolicy(
    'The server requires a camera policy this client cannot verify.',
  ),
  screenshotPolicy(
    'The service cannot verify screenshot protection for this client.',
  ),
  sessionExpired('The server reported that this viewing session expired.');

  final String description;
  const ApiAccessDenial(this.description);

  static ApiAccessDenial? fromMessage(Object? value) => switch (value) {
    'Access has not begun.' => notStarted,
    'Access has expired.' ||
    'Viewing time expired. Waiting for the sender to extend it.' =>
      policyExpired,
    'Maximum views reached.' => viewLimit,
    'Approved device required.' => deviceApproval,
    'Country restriction was not satisfied.' ||
    'State/region restriction was not satisfied.' ||
    'City restriction was not satisfied.' => networkLocation,
    'This content requires camera protection. Use an updated Aperture desktop client.' =>
      cameraPolicy,
    'Screenshot restriction cannot be enforced by this desktop client.' =>
      screenshotPolicy,
    'Session expired; open the content again.' => sessionExpired,
    _ => null,
  };
}

class ApiAccessDecision {
  final int? sessionId;
  final bool granted, suspended, ended;
  final bool refusedByHttp;
  final bool deviceVerified;
  final ApiAccessDenial? denial;
  const ApiAccessDecision({
    this.sessionId,
    required this.granted,
    this.suspended = false,
    this.ended = false,
    this.refusedByHttp = false,
    this.deviceVerified = false,
    this.denial,
  });

  factory ApiAccessDecision.fromJson(dynamic value) {
    final j = apiObject(value);
    final ended = apiBool(j['SessionEnded']);
    final id = j['SessionId'];
    // A terminal assertion wins even when the rest of the response is
    // contradictory/malformed. A later grant must not resurrect that session.
    final safeId = id is int && id > 0 ? id : null;
    final denial = j['AccessGranted'] == false
        ? ApiAccessDenial.fromMessage(j['Message'])
        : null;
    if (ended) {
      return ApiAccessDecision(
        sessionId: safeId,
        granted: false,
        ended: true,
        denial: denial,
      );
    }
    final suspended = apiBool(j['Suspended']);
    if (suspended) {
      return ApiAccessDecision(
        sessionId: safeId,
        granted: false,
        suspended: true,
        denial: denial,
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
      denial: denial,
    );
  }
}
