import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/api_models.dart';
import '../models/content_create_request.dart';
import '../models/location_radius_policy.dart';
import 'device_location.dart';

class ApiReply {
  final int status;
  final String body;
  const ApiReply(this.status, this.body);
}

abstract interface class ApiTransport {
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  );
  void close();
}

class ApiRequestCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

abstract interface class CancellableApiTransport implements ApiTransport {
  Future<ApiReply> sendCancellable(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    ApiRequestCancellation cancellation,
  );
}

enum SecureUploadReadiness { unverified, testFixture }

const _debugBuild =
    !bool.fromEnvironment('dart.vm.product') &&
    !bool.fromEnvironment('dart.vm.profile');
const _anonymousProbePath = 'api/content/capabilities';
const classroomHttpMode = 'classroom-http-integration';
typedef ClassroomAccounts = ({String sender, String recipient});

const classroomFixtureSender = 'fixture-classroom-sender';
const classroomFixtureRecipient = 'fixture-classroom-recipient';

const configuredClassroomRecipient = String.fromEnvironment(
  'APERTURE_CLASSROOM_RECIPIENT',
  defaultValue: classroomFixtureRecipient,
);
const defaultClassroomAccounts = (
  sender: String.fromEnvironment(
    'APERTURE_CLASSROOM_SENDER',
    defaultValue: classroomFixtureSender,
  ),
  recipient: configuredClassroomRecipient,
);
const approvedClassroomOrigin = String.fromEnvironment(
  'APERTURE_CLASSROOM_APPROVED_ORIGIN',
);
const _classroomRoutes = {
  ('POST', 'api/auth/login'),
  ('GET', 'api/user/me'),
  ('GET', 'api/content'),
  ('POST', 'api/auth/logout'),
};

// Literal addresses keep DNS and private-LAN routing out of the sign-in path.
bool _isLoopback(Uri uri) => uri.host == '127.0.0.1' || uri.host == '::1';

/// Native mobile HTTP transport. Normal platform TLS, no redirects or logging
/// of headers/bodies. Each entire exchange has a deadline and bounded input.
class NativeApiTransport implements CancellableApiTransport {
  final Uri? _schoolDemoBase;
  final Uri? _classroomBase;
  late final HttpClient _client = _newClient();
  static const timeout = Duration(seconds: 4);
  static const classroomTimeout = Duration(seconds: 15);
  static const maxBytes = 8 * 1024 * 1024;

  NativeApiTransport() : _schoolDemoBase = null, _classroomBase = null;

  NativeApiTransport.schoolDemo(Uri base)
    : _classroomBase = null,
      _schoolDemoBase = ApiService.parseBaseUrl(
        base.toString(),
        schoolDemo: true,
      );

  NativeApiTransport.classroomHttp(Uri base)
    : _schoolDemoBase = null,
      _classroomBase = ApiService.parseBaseUrl(
        base.toString(),
        classroomHttp: true,
      );

  HttpClient _newClient() {
    final client = HttpClient();
    if (_schoolDemoBase != null || _classroomBase != null) {
      client.findProxy = (_) => 'DIRECT';
    }
    return client;
  }

  @override
  Future<ApiReply> send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) => _send(_client, method, uri, headers, body);

  @override
  Future<ApiReply> sendCancellable(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    ApiRequestCancellation cancellation,
  ) async {
    if (cancellation.isCancelled) {
      throw const ApiException(ApiFailure.cancelled);
    }
    // Force-closing a per-request client never affects auth or viewing calls
    // using the shared client. TLS and redirect rules remain the same.
    final client = _newClient();
    unawaited(
      cancellation.whenCancelled.then((_) => client.close(force: true)),
    );
    try {
      final reply = await _send(client, method, uri, headers, body);
      if (cancellation.isCancelled) {
        throw const ApiException(ApiFailure.cancelled);
      }
      return reply;
    } on ApiException {
      if (cancellation.isCancelled) {
        throw const ApiException(ApiFailure.cancelled);
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<ApiReply> _send(
    HttpClient client,
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final demo = _schoolDemoBase;
    final classroom = _classroomBase;
    if (uri.host.isEmpty ||
        (demo == null && classroom == null && uri.scheme != 'https')) {
      throw const ApiException(ApiFailure.configuration);
    }
    if (classroom != null &&
        !_classroomRoutes.any(
          (route) => method == route.$1 && uri == classroom.resolve(route.$2),
        )) {
      throw const ApiException(ApiFailure.configuration);
    }
    if (demo != null) {
      if (uri.scheme != 'http' ||
          uri.origin != demo.origin ||
          !uri.path.startsWith(demo.path) ||
          uri.authority.contains('@') ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const ApiException(ApiFailure.configuration);
      }
      if (method == 'POST' && uri == demo.resolve('api/content')) {
        throw const ApiException(ApiFailure.uploadUnverified);
      }
      if (!_isLoopback(demo) &&
          (method != 'GET' ||
              uri != demo.resolve(_anonymousProbePath) ||
              headers.length != 1 ||
              headers['Accept'] != 'application/json' ||
              body != null)) {
        throw const ApiException(ApiFailure.httpDemoAnonymousOnly);
      }
    }
    HttpClientRequest? request;
    var expired = false;
    try {
      return await (() async {
        // Dart's debug network profiler can retain bodies and bearer headers.
        if (classroom != null) HttpClient.enableTimelineLogging = false;
        request = await client.openUrl(method, uri);
        if (expired) {
          request!.abort();
          throw const ApiException(ApiFailure.timeout);
        }
        request!.followRedirects = false;
        if (classroom != null) request!.persistentConnection = false;
        headers.forEach((key, value) => request!.headers.set(key, value));
        if (body != null) request!.write(body);
        final response = await request!.close();
        final bytes = <int>[];
        await for (final part in response) {
          if (bytes.length + part.length > maxBytes) {
            request!.abort();
            throw const ApiException(ApiFailure.malformed);
          }
          bytes.addAll(part);
        }
        return ApiReply(response.statusCode, utf8.decode(bytes));
      })().timeout(classroom == null ? timeout : classroomTimeout);
    } on TimeoutException {
      expired = true;
      request?.abort();
      throw const ApiException(ApiFailure.timeout);
    } on ApiException {
      rethrow;
    } on FormatException {
      throw const ApiException(ApiFailure.malformed);
    } catch (_) {
      throw const ApiException(ApiFailure.network);
    }
  }

  @override
  void close() => _client.close(force: true);
}

class ApiService {
  static const contractRevision = 'a634ed1d8c43b5a79e472c9026a803416b402844';
  static const cameraPolicyVersion = 0;
  final Uri? baseUri;
  final ApiTransport transport;
  final Duration timeout;
  final bool isFixture;
  final bool usesClassroomHttp;
  final bool canOpenContentRoutes;
  final SecureUploadReadiness uploadReadiness;
  final ClassroomAccounts _classroomAccounts;

  ApiService({
    required this.baseUri,
    required this.transport,
    this.timeout = const Duration(seconds: 4),
    bool schoolDemo = false,
    bool classroomHttp = false,
    ClassroomAccounts classroomAccounts = defaultClassroomAccounts,
  }) : _classroomAccounts = classroomAccounts,
       isFixture = false,
       usesClassroomHttp = classroomHttp,
       canOpenContentRoutes = !classroomHttp,
       uploadReadiness = SecureUploadReadiness.unverified {
    final uri = baseUri;
    final (sender: sender, recipient: recipient) = classroomAccounts;
    if ((classroomHttp &&
            (uri == null ||
                schoolDemo ||
                sender.trim().isEmpty ||
                recipient.trim().isEmpty ||
                sender.toLowerCase() == recipient.toLowerCase())) ||
        (uri != null &&
            (!_validBase(uri, allowHttp: schoolDemo || classroomHttp) ||
                !uri.path.endsWith('/')))) {
      throw const ApiException(ApiFailure.configuration);
    }
  }

  /// The injected transport owns routing. This service supplies no origin
  /// and keeps uploads disabled.
  ApiService.fixture({
    required this.transport,
    this.canOpenContentRoutes = false,
    this.timeout = const Duration(seconds: 4),
  }) : baseUri = null,
       _classroomAccounts = defaultClassroomAccounts,
       isFixture = true,
       usesClassroomHttp = false,
       uploadReadiness = SecureUploadReadiness.unverified;

  /// Injection seam for synthetic tests only. No URL can be supplied here.
  /// Neither the normal app nor its offline fixture mode uses this constructor.
  ApiService.uploadFixture({
    required CancellableApiTransport this.transport,
    this.timeout = const Duration(seconds: 4),
  }) : baseUri = null,
       _classroomAccounts = defaultClassroomAccounts,
       isFixture = true,
       usesClassroomHttp = false,
       canOpenContentRoutes = false,
       uploadReadiness = SecureUploadReadiness.testFixture;

  static Uri parseBaseUrl(
    String value, {
    bool schoolDemo = false,
    bool classroomHttp = false,
  }) {
    final uri = Uri.tryParse(value.endsWith('/') ? value : '$value/');
    if (uri == null ||
        RegExp(r'\s|\\').hasMatch(value) ||
        RegExp(r'^https?://[^/]*@', caseSensitive: false).hasMatch(value) ||
        (schoolDemo && classroomHttp) ||
        !_validBase(uri, allowHttp: schoolDemo || classroomHttp)) {
      throw const ApiException(ApiFailure.configuration);
    }
    return uri;
  }

  static Uri parseApprovedClassroomBaseUrl(
    String value,
    String approvedOrigin,
  ) {
    final uri = parseBaseUrl(value, classroomHttp: true);
    final approved = parseBaseUrl(approvedOrigin, classroomHttp: true);
    if (uri != approved) {
      throw const ApiException(ApiFailure.configuration);
    }
    return uri;
  }

  static bool _validBase(Uri uri, {required bool allowHttp}) =>
      (allowHttp
          ? _debugBuild && uri.scheme == 'http'
          : uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.port >= 1 &&
      uri.port <= 65535 &&
      !uri.authority.contains('@') &&
      !uri.hasQuery &&
      !uri.hasFragment;

  bool get configured => baseUri != null || isFixture;
  bool get usesSchoolDemoHttp =>
      !usesClassroomHttp && baseUri?.scheme == 'http';
  bool get anonymousOnly => usesSchoolDemoHttp && !_isLoopback(baseUri!);
  bool get canCreateContent =>
      uploadReadiness == SecureUploadReadiness.testFixture &&
      isFixture &&
      baseUri == null;

  Future<dynamic> _request(
    String method,
    String path, {
    String? token,
    Object? body,
    bool viewing = false,
    bool anonymousProbe = false,
    LocationFix? location,
    ApiRequestCancellation? cancellation,
    void Function()? onDispatch,
  }) async {
    if (!configured) throw const ApiException(ApiFailure.configuration);
    if (usesClassroomHttp && !_classroomRoutes.contains((method, path))) {
      throw const ApiException(ApiFailure.configuration);
    }
    if (anonymousOnly && !anonymousProbe) {
      throw const ApiException(ApiFailure.httpDemoAnonymousOnly);
    }
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (location != null) ...location.headers,
    };
    final ApiReply reply;
    try {
      final uri = baseUri?.resolve(path) ?? Uri(path: '/$path');
      final encoded = body == null ? null : jsonEncode(body);
      if (cancellation == null) {
        onDispatch?.call();
        reply = await transport
            .send(method, uri, headers, encoded)
            .timeout(timeout);
      } else {
        if (cancellation.isCancelled) {
          throw const ApiException(ApiFailure.cancelled);
        }
        final cancellable = transport as CancellableApiTransport;
        onDispatch?.call();
        final exchange = cancellable.sendCancellable(
          method,
          uri,
          headers,
          encoded,
          cancellation,
        );
        reply = await Future.any<ApiReply>([
          exchange,
          cancellation.whenCancelled.then<ApiReply>((_) {
            throw const ApiException(ApiFailure.cancelled);
          }),
        ]).timeout(timeout);
        if (cancellation.isCancelled) {
          throw const ApiException(ApiFailure.cancelled);
        }
      }
    } on TimeoutException {
      cancellation?.cancel();
      throw const ApiException(ApiFailure.timeout);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(ApiFailure.network);
    }
    if (reply.status == 401 && !anonymousProbe) {
      throw const ApiException(ApiFailure.credentials);
    }
    if (viewing && {403, 404}.contains(reply.status)) {
      return const ApiAccessDecision(
        granted: false,
        ended: true,
        refusedByHttp: true,
      );
    }
    if (reply.status == 403) throw const ApiException(ApiFailure.denied);
    if (reply.status == 404) throw const ApiException(ApiFailure.notFound);
    if (reply.status == 400) {
      throw const ApiException(ApiFailure.invalidRequest);
    }
    if (anonymousProbe && reply.status == 200) {
      throw const ApiException(ApiFailure.malformed);
    }
    if (reply.status != (anonymousProbe ? 401 : 200)) {
      throw const ApiException(ApiFailure.server);
    }
    if (reply.body.length > NativeApiTransport.maxBytes) {
      throw const ApiException(ApiFailure.malformed);
    }
    try {
      return jsonDecode(reply.body);
    } catch (_) {
      throw const ApiException(ApiFailure.malformed);
    }
  }

  /// Accept only the source contract's JSON authentication denial.
  Future<void> checkAnonymousAccess() async {
    final reply = apiObject(
      await _request('GET', _anonymousProbePath, anonymousProbe: true),
    );
    if (reply['success'] != false ||
        reply['message'] != 'Authentication required.') {
      throw const ApiException(ApiFailure.malformed);
    }
  }

  /// The current backend contract is a wire-format reference only. Do not
  /// build an image payload until the fixture-only gate has been checked.
  Future<int> createContent(
    String token,
    ContentCreateRequest request,
    Uint8List? png, {
    required int maxBytes,
    required ApiRequestCancellation cancellation,
    required void Function() onDispatch,
  }) async {
    final Map<String, Object> body;
    try {
      if (!canCreateContent) {
        throw const ApiException(ApiFailure.uploadUnverified);
      }
      if (token.trim().isEmpty) {
        throw const ApiException(ApiFailure.credentials);
      }
      if (cancellation.isCancelled) {
        throw const ApiException(ApiFailure.cancelled);
      }
      body = request.encode(png, maxBytes: maxBytes);
    } finally {
      png?.fillRange(0, png.length, 0);
    }
    final reply = apiObject(
      await _request(
        'POST',
        'api/content',
        token: token,
        body: body,
        cancellation: cancellation,
        onDispatch: onDispatch,
      ),
    );
    return apiId(reply['id']);
  }

  Future<ApiCredentials> login(String username, String password) async {
    if (usesClassroomHttp &&
        username != _classroomAccounts.sender &&
        username != _classroomAccounts.recipient) {
      throw const ApiException(ApiFailure.credentials);
    }
    final j = apiObject(
      await _request(
        'POST',
        'api/auth/login',
        body: {'Username': username, 'Password': password},
      ),
    );
    if (!apiBool(j['Success'])) {
      throw const ApiException(ApiFailure.credentials);
    }
    final user = apiObject(j['User']);
    final token = apiString(j['Token']);
    if (token.contains(RegExp(r'[\s\r\n]'))) {
      throw const ApiException(ApiFailure.malformed);
    }
    return ApiCredentials(
      token,
      apiUtc(j['ExpiresAt']),
      ApiUser(apiId(user['Id']), apiString(user['Username'])),
    );
  }

  Future<ApiUser> currentUser(String token) async {
    final j = apiObject(await _request('GET', 'api/user/me', token: token));
    if (!apiBool(j['success'])) {
      throw const ApiException(ApiFailure.credentials);
    }
    final u = apiObject(j['user']);
    return ApiUser(apiId(u['id']), apiString(u['username']));
  }

  Future<void> logout(String token) async {
    try {
      final j = apiObject(
        await _request('POST', 'api/auth/logout', token: token),
      );
      if (j['success'] != true) throw const ApiException(ApiFailure.malformed);
    } on ApiException catch (e) {
      // This route returns 401 when the token is no longer present.
      if (e.kind != ApiFailure.credentials) rethrow;
    }
  }

  Future<List<ApiContent>> list(String token) async {
    final result = await _request('GET', 'api/content', token: token);
    if (result is! List) throw const ApiException(ApiFailure.malformed);
    return List.unmodifiable(result.map(ApiContent.fromJson));
  }

  Future<int> serverCameraPolicyVersion(String token) async {
    final j = apiObject(
      await _request('GET', 'api/content/capabilities', token: token),
    );
    final version = j['CameraPolicyVersion'];
    if (version is! int || version < 0) {
      throw const ApiException(ApiFailure.malformed);
    }
    return version;
  }

  Future<void> policy(String token, int id, String status) async {
    apiId(id);
    if (!{'Active', 'Paused'}.contains(status)) {
      throw const ApiException(ApiFailure.invalidRequest);
    }
    final j = apiObject(
      await _request(
        'POST',
        'api/content/$id/policy',
        token: token,
        body: {'Status': status},
      ),
    );
    if (j['status'] != status) throw const ApiException(ApiFailure.malformed);
  }

  Future<void> setLocation(
    String token,
    int id,
    LocationZone zone, {
    void Function()? onDispatch,
  }) async {
    apiId(id);
    if (!zone.valid) throw const ApiException(ApiFailure.invalidRequest);
    final reply = apiObject(
      await _request(
        'POST',
        'api/situational/content/$id/location',
        token: token,
        body: {
          'Latitude': zone.latitude,
          'Longitude': zone.longitude,
          'RadiusMeters': zone.radiusMeters,
        },
        onDispatch: onDispatch,
      ),
    );
    if (reply['success'] != true) {
      throw const ApiException(ApiFailure.malformed);
    }
  }

  Future<void> revoke(String token, int id) async {
    apiId(id);
    final j = apiObject(
      await _request('POST', 'api/content/$id/revoke', token: token),
    );
    if (j['success'] != true) throw const ApiException(ApiFailure.malformed);
  }

  static void _validateDeviceKey(String deviceKey) {
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(deviceKey) ||
        deviceKey.replaceAll('-', '').split('').every((c) => c == '0')) {
      throw const ApiException(ApiFailure.configuration);
    }
  }

  Future<bool> registerDevice(
    String token,
    String deviceKey,
    String name,
  ) async {
    _validateDeviceKey(deviceKey);
    if (name.trim().isEmpty || name.trim().length > 100) {
      throw const ApiException(ApiFailure.invalidRequest);
    }
    final reply = apiObject(
      await _request(
        'POST',
        'api/devices',
        token: token,
        body: {'DeviceKey': deviceKey, 'DeviceName': name.trim()},
      ),
    );
    return apiBool(reply['trusted']);
  }

  Future<ApiAccessDecision> open(
    String token,
    int id,
    String deviceKey, {
    LocationFix? location,
  }) async {
    apiId(id);
    _validateDeviceKey(deviceKey);
    final raw = await _request(
      'POST',
      'api/content/$id/sessions',
      token: token,
      body: {
        'DeviceKey': deviceKey,
        'CameraPolicyVersion': cameraPolicyVersion,
      },
      viewing: true,
      location: location,
    );
    try {
      return raw is ApiAccessDecision ? raw : ApiAccessDecision.fromJson(raw);
    } on ApiException {
      // If a malformed open nevertheless reports a session identifier, attempt
      // to close it without treating any of its content/conditions as approved.
      if (raw is Map && raw['SessionId'] is int && raw['SessionId'] > 0) {
        await end(token, raw['SessionId'] as int).catchError((Object _) {});
      }
      rethrow;
    }
  }

  Future<ApiAccessDecision> check(
    String token,
    int id, {
    LocationFix? location,
  }) async {
    apiId(id);
    final raw = await _request(
      'POST',
      'api/content/sessions/$id/check',
      token: token,
      body: const {},
      viewing: true,
      location: location,
    );
    return raw is ApiAccessDecision ? raw : ApiAccessDecision.fromJson(raw);
  }

  Future<void> end(String token, int id) async {
    apiId(id);
    final j = apiObject(
      await _request('POST', 'api/content/sessions/$id/end', token: token),
    );
    if (j['success'] != true) throw const ApiException(ApiFailure.malformed);
  }

  void close() => transport.close();
}
