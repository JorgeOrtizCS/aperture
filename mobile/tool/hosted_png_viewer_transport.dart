import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aperture/models/api_models.dart';
import 'package:aperture/services/api_service.dart';
import 'package:aperture/widgets/recipient_png_renderer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'flutter_png_fixture_spec.dart';

const hostedPngContentId = 900012;
const hostedPngTitle = 'Aperture synthetic hosted PNG fixture';
const hostedPngRecipient = configuredClassroomRecipient;
const hostedPngLabel = 'Unencrypted Classroom Test Content';
const hostedPngMime = 'image/png';
const hostedPngSha256 =
    '4afc448186f1260fc52d84be9f7273e6b4243ac3d32b541ad5921cddd1eb524f';

typedef _Identity = ({
  String header,
  int id,
  String username,
  DateTime expires,
});

class _ViewAttempt {
  _ViewAttempt(this.identityVersion, this.owner, this.captureReady);
  final int identityVersion;
  final _Identity owner;
  final Future<bool> Function() captureReady;
  int? session;
  Uint8List? bytes;

  void clear() {
    bytes?.fillRange(0, bytes!.length, 0);
    bytes = null;
  }
}

/// Private to the alternate target. ApiService receives sanitized decisions,
/// while the renderer receives the verified bytes through a one-time handoff.
class HostedPngTransport implements ApiTransport {
  HostedPngTransport(ApiTransport backend)
    : this._(
        backend,
        contentId: hostedPngContentId,
        title: hostedPngTitle,
        maxViews: 2,
      );

  HostedPngTransport._(
    this._backend, {
    required this.contentId,
    required this.title,
    required this.maxViews,
  }) {
    if (!kDebugMode) throw const ApiException(ApiFailure.configuration);
  }

  factory HostedPngTransport.live(String url) {
    const approved = bool.fromEnvironment('APERTURE_HOSTED_PNG_LIVE_APPROVED');
    const freshId = int.fromEnvironment('APERTURE_HOSTED_PNG_FRESH_ID');
    if (!kDebugMode ||
        !approved ||
        defaultClassroomAccounts.sender.trim().isEmpty ||
        hostedPngRecipient.trim().isEmpty ||
        defaultClassroomAccounts.sender.toLowerCase() ==
            hostedPngRecipient.toLowerCase()) {
      throw const ApiException(ApiFailure.configuration);
    }
    final base = ApiService.parseApprovedClassroomBaseUrl(
      url,
      approvedClassroomOrigin,
    );
    if (base.port != 80 || base.path != '/') {
      throw const ApiException(ApiFailure.configuration);
    }
    const archive = String.fromEnvironment(
      'APERTURE_CLASSROOM_ARCHIVED_PNG_IDS',
    );
    final archivedIds = parseArchivedPngIds(archive);
    return HostedPngTransport.forFlutterAcceptance(
      _ClassroomHttp(base),
      freshId,
      archivedIds: archivedIds,
    );
  }

  factory HostedPngTransport.forFlutterAcceptance(
    ApiTransport backend,
    int id, {
    Set<int> archivedIds = const {},
  }) {
    if (id <= 0 ||
        id > 0x7fffffff ||
        flutterPngFixtureArchivedIds.contains(id) ||
        archivedIds.contains(id)) {
      throw const ApiException(ApiFailure.configuration);
    }
    return HostedPngTransport._(
      backend,
      contentId: id,
      title: flutterPngFixtureTitle,
      maxViews: flutterPngFixtureMaxViews,
    );
  }

  final ApiTransport _backend;
  final int contentId, maxViews;
  final String title;
  _Identity? _identity;
  bool _verified = false, _listed = false, _closed = false;
  bool _openDispatched = false;
  bool get openDispatched => _openDispatched;
  _ViewAttempt? _attempt;
  final _owners = <int, _Identity>{};

  bool get _currentIdentity =>
      !_closed &&
      _verified &&
      (_identity?.expires.isAfter(DateTime.now().toUtc()) ?? false);

  bool begin(int identityVersion, Future<bool> Function() captureReady) {
    if (!_currentIdentity || !_listed || openDispatched || _attempt != null) {
      return false;
    }
    _attempt = _ViewAttempt(identityVersion, _identity!, captureReady);
    return true;
  }

  bool _current(_ViewAttempt attempt) =>
      _currentIdentity &&
      _listed &&
      identical(_attempt, attempt) &&
      identical(_identity, attempt.owner);

  void _evidence(String message) {
    if (_backend is _ClassroomHttp) debugPrint('[Classroom PNG] $message');
  }

  void retire() {
    _attempt?.clear();
    _attempt = null;
  }

  RecipientPngPayload take(int identityVersion, int session) {
    final attempt = _attempt;
    if (attempt == null ||
        !_current(attempt) ||
        attempt.identityVersion != identityVersion ||
        attempt.session != session ||
        !identical(_owners[session], attempt.owner) ||
        attempt.bytes == null) {
      throw const ApiException(ApiFailure.stale);
    }
    final bytes = attempt.bytes!;
    attempt.bytes = null;
    return RecipientPngPayload(contentType: hostedPngMime, bytes: bytes);
  }

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final path = uri.path;
    if (_closed || uri != Uri(path: path)) {
      throw const ApiException(ApiFailure.configuration);
    }
    Future<ApiReply> forward() => _backend.send(method, uri, headers, body);
    final route = (method, path);
    if (route == ('POST', '/api/auth/login')) {
      if (_identity != null || _json(body)?['Username'] != hostedPngRecipient) {
        return const ApiReply(401, '');
      }
      final reply = await forward();
      if (reply.status == 200 && !_closed) {
        final j = _json(reply.body);
        if (j?['Success'] == true) {
          final bearer = apiString(j!['Token']);
          if (bearer.contains(RegExp(r'\s'))) {
            throw const ApiException(ApiFailure.malformed);
          }
          final user = apiObject(j['User']);
          _identity = (
            header: 'Bearer $bearer',
            id: apiId(user['Id']),
            username: apiString(user['Username']),
            expires: apiUtc(j['ExpiresAt']),
          );
          _verified = _listed = false;
        }
      }
      return reply;
    }
    final bearer = headers['Authorization'];

    // Cleanup is scoped to the session's original credential. It stays
    // available after local retirement, including for a late open response.
    final end = RegExp(r'^/api/content/sessions/([1-9][0-9]*)/end$')
        .firstMatch(path);
    final ending = end == null ? null : int.tryParse(end[1]!);
    if (method == 'POST' && ending != null) {
      final owner = _owners[ending];
      if (owner == null || owner.header != bearer) {
        throw const ApiException(ApiFailure.denied);
      }
      if (_attempt?.session == ending) retire();
      final ApiReply reply;
      try {
        reply = await forward();
      } catch (_) {
        _evidence('End response unavailable');
        rethrow;
      }
      final acknowledged =
          reply.status == 200 && _json(reply.body)?['success'] == true;
      _evidence('End HTTP ${reply.status}. Acknowledged: $acknowledged');
      if (reply.status == 404 || reply.status == 401 || acknowledged) {
        _owners.remove(ending);
      }
      return reply;
    }

    final identity = _identity;
    if (identity == null || bearer != identity.header) {
      return const ApiReply(401, '');
    }
    if (route == ('POST', '/api/auth/logout')) {
      retire();
      _identity = null;
      _listed = _verified = false;
      _owners.removeWhere((_, owner) => identical(owner, identity));
      return forward();
    }
    if (route == ('GET', '/api/user/me')) {
      final reply = await forward();
      final j = _json(reply.body);
      final me = j?['user'];
      final matched =
          reply.status == 200 &&
          j?['success'] == true &&
          me is Map<String, dynamic> &&
          me['id'] == identity.id &&
          identity.username == hostedPngRecipient &&
          me['username'] == hostedPngRecipient;
      if (identical(_identity, identity)) _verified = matched;
      return matched ? reply : const ApiReply(401, '');
    }
    if (!_currentIdentity) return const ApiReply(401, '');
    if (route == ('GET', '/api/content')) {
      _listed = false;
      final reply = await forward();
      if (reply.status != 200) {
        retire();
        return reply;
      }
      if (!identical(_identity, identity) || !_currentIdentity) {
        throw const ApiException(ApiFailure.stale);
      }
      final rows = _decode(reply.body);
      if (rows is! List) {
        retire();
        throw const ApiException(ApiFailure.malformed);
      }
      final matches = rows
          .whereType<Map<String, dynamic>>()
          .where((row) => row['Id'] == contentId)
          .toList();
      _listed = matches.length == 1 && _eligible(matches.single);
      if (!_listed) retire();
      return ApiReply(
        200,
        jsonEncode([
          if (_listed)
            {
              for (final field in const [
                'Id',
                'Title',
                'Owner',
                'Mine',
                'CreatedAt',
                'Status',
                'PolicyStatus',
                'RequireTrustedDevice',
              ])
                field: matches.single[field],
            },
        ]),
      );
    }

    final attempt = _attempt;
    if (attempt == null || !_current(attempt)) {
      throw const ApiException(ApiFailure.denied);
    }
    if (route == ('POST', '/api/content/$contentId/sessions') &&
        !openDispatched) {
      if (!await attempt.captureReady() ||
          !_current(attempt) ||
          openDispatched) {
        return const ApiReply(403, '');
      }
      _openDispatched = true;
      _evidence('Open dispatched after biometric and capture checks');
      try {
        final reply = await forward();
        _evidence('Open HTTP ${reply.status}');
        return _grant(reply, attempt, opening: true);
      } catch (_) {
        _evidence('Open could not be confirmed');
        if (identical(_attempt, attempt)) retire();
        return _denied(attempt.session);
      }
    }
    final session = attempt.session;
    if (session != null &&
        route == ('POST', '/api/content/sessions/$session/check')) {
      try {
        return _grant(await forward(), attempt, opening: false);
      } catch (_) {
        if (identical(_attempt, attempt)) retire();
        return _denied(session);
      }
    }
    throw const ApiException(ApiFailure.denied);
  }

  bool _eligible(Map<String, dynamic> row) =>
      row['Title'] == title &&
      row['Mine'] == false &&
      row['Owner'] == defaultClassroomAccounts.sender &&
      (row['Recipient'] == null || row['Recipient'] == hostedPngRecipient) &&
      row['Status'] == 'Active' &&
      row['PolicyStatus'] == 'Active' &&
      row['MaxViews'] == maxViews &&
      (row['RemainingViews'] == null || row['RemainingViews'] == 1) &&
      (row['ViewCount'] == null || row['ViewCount'] == maxViews - 1) &&
      (row['ViewsUsed'] == null || row['ViewsUsed'] == maxViews - 1) &&
      row['RequireTrustedDevice'] == false &&
      row['ScreenshotRestriction'] == false &&
      (row['FileType'] == null || row['FileType'] == hostedPngMime) &&
      _hasNoExtraPolicy(row) &&
      (row['CameraRestrictions'] == null ||
          _disabledCamera(row['CameraRestrictions']));

  static bool _hasNoExtraPolicy(Map<String, dynamic> value) => const [
    'RequiredLocation',
    'AllowedCountry',
    'AllowedRegion',
    'AllowedCity',
    'Latitude',
    'Longitude',
    'RadiusMeters',
    'StartTime',
    'ExpiresAt',
  ].every((key) => value[key] == null);

  static bool _disabledCamera(Object? camera) =>
      camera is Map<String, dynamic> &&
      const [
        'Enabled',
        'BlockPhones',
        'BlockMultiplePeople',
        'RequireViewer',
      ].every((key) => camera[key] == false);

  ApiReply _grant(
    ApiReply reply,
    _ViewAttempt attempt, {
    required bool opening,
  }) {
    final j = _json(reply.body);
    final id = j?['SessionId'];
    final known = id is int && id > 0 ? id : null;
    final fixtureMatches =
        j != null &&
        const ['ContentId', 'ContentID'].every(
          (key) =>
              !j.containsKey(key) || (j[key] is int && j[key] == contentId),
        ) &&
        (j['Title'] == null || j['Title'] == title);
    if (opening &&
        known != null &&
        fixtureMatches &&
        (reply.status == 200 || j['AccessGranted'] == true)) {
      // A response that identifies another share cannot name a cleanup target.
      _owners[known] = attempt.owner;
      attempt.session = known;
    }
    final session = attempt.session;
    Uint8List? bytes;
    try {
      if (reply.status == 200 &&
          _current(attempt) &&
          session != null &&
          known == session &&
          fixtureMatches &&
          j['Title'] == title &&
          j['AccessGranted'] == true &&
          j['Suspended'] == false &&
          j['SessionEnded'] == false &&
          j['DeviceVerified'] == false &&
          j['LocationVerified'] == true &&
          _disabledCamera(j['CameraRestrictions']) &&
          _hasNoExtraPolicy(j) &&
          (j['RequireTrustedDevice'] == null ||
              j['RequireTrustedDevice'] == false) &&
          (j['ScreenshotRestriction'] == null ||
              j['ScreenshotRestriction'] == false) &&
          j['Body'] == null &&
          j['FileType'] == hostedPngMime) {
        final encoded = j['FileDataBase64'];
        if (encoded is String && encoded.length == 1316) {
          bytes = base64Decode(encoded);
          if (bytes.length == 986 &&
              sha256.convert(bytes).toString() == hostedPngSha256) {
            if (opening) {
              attempt.bytes = bytes;
              bytes = null;
              _evidence('Verified $hostedPngMime. SHA-256 $hostedPngSha256');
            }
            return ApiReply(
              200,
              jsonEncode({
                'SessionId': session,
                'AccessGranted': true,
                'Suspended': false,
                'SessionEnded': false,
                'DeviceVerified': false,
                'LocationVerified': true,
                'CameraRestrictions': j['CameraRestrictions'],
              }),
            );
          }
        }
      }
    } on FormatException {
      // Reject invalid Base64 without including any payload in an error.
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
    if (identical(_attempt, attempt)) retire();
    return _denied(session);
  }

  static ApiReply _denied(int? session) => ApiReply(
    200,
    jsonEncode({
      'SessionId': session ?? 0,
      'AccessGranted': false,
      'SessionEnded': true,
    }),
  );

  static Object? _decode(String? value) {
    try {
      return value == null ? null : jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _json(String? value) {
    final decoded = _decode(value);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  @override
  void close() {
    _closed = true;
    retire();
    _owners.clear();
    _identity = null;
    _backend.close();
  }
}

/// Its only caller validates methods, paths and the recipient. Resolve those
/// relative paths against the pinned classroom origin, using direct HTTP.
class _ClassroomHttp implements ApiTransport {
  _ClassroomHttp(this.base);
  final Uri base;

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    HttpClient.enableTimelineLogging = false;
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      return await (() async {
        final request = await client.openUrl(method, base.resolveUri(uri));
        request
          ..followRedirects = false
          ..persistentConnection = false;
        headers.forEach(request.headers.set);
        if (body != null) request.add(utf8.encode(body));
        final response = await request.close();
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > NativeApiTransport.maxBytes) {
            throw const ApiException(ApiFailure.malformed);
          }
          bytes.add(chunk);
        }
        final received = bytes.takeBytes();
        try {
          return ApiReply(response.statusCode, utf8.decode(received));
        } finally {
          received.fillRange(0, received.length, 0);
        }
      })().timeout(NativeApiTransport.classroomTimeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.timeout);
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException(ApiFailure.malformed);
    } catch (_) {
      throw const ApiException(ApiFailure.network);
    } finally {
      client.close(force: true);
    }
  }

  @override
  void close() {}
}
