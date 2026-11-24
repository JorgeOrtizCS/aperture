part of 'api_acceptance.dart';

const _pngApprovalFlag = '--approve-one-png-db97004e5740';
const _pngJournalPath = 'config/local/live-png-db97004e5740.jsonl';
const _flutterPngApprovalFlag = '--approve-create-flutter-png-63f66a533056';
const _flutterPngJournalPath =
    'config/local/live-flutter-png-63f66a533056.jsonl';
const _pngTitle = 'Aperture synthetic classroom acceptance PNG';
const _pngAssetPath = 'docs/week11/task11-3/Aperture-Demo.png';
const _pngSize = 986;
const _pngSha256 =
    '4afc448186f1260fc52d84be9f7273e6b4243ac3d32b541ad5921cddd1eb524f';

/// Runs only from the acceptance CLI. The normal app never sees this payload.
class _ClassroomPng extends _ClassroomSession {
  _ClassroomPng(super.config, super.transport, super.progress, super.journal);

  late final Map<String, Object> _fixture;
  String get title => _pngTitle;
  int get maxViews => 2;

  @override
  Map<String, Object> get fixture => _fixture;

  @override
  Future<void> _run() async {
    await _step('Verify the exact synthetic PNG on disk', () async {
      final source = await File(_pngAssetPath).open();
      final Uint8List bytes;
      try {
        bytes = await source.read(_pngSize + 1);
      } finally {
        await source.close();
      }
      try {
        _require(bytes.length == _pngSize);
        _require(base64Encode(bytes) == classroomSyntheticPng);
        final header = ByteData.sublistView(bytes);
        _require(header.getUint32(16) == 320 && header.getUint32(20) == 180);
        _require(await _sha256(bytes) == _pngSha256);
        _fixture = {
          ...ContentCreateRequest.validate(
            title: title,
            sender: config.sender.username,
            recipient: config.recipient.username,
            now: DateTime.now().toUtc(),
            maxViews: maxViews,
            screenshotRestriction: false,
          ).encode(bytes, maxBytes: _pngSize),
          'CameraRestrictions': _cameraDisabled,
        };
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    });
    await super._run();
  }

  @override
  Future<void> _reserveCreate() async {
    await super._reserveCreate();
    await _record({
      'event': 'fixtureVerified',
      'title': title,
      'sourceByteSize': _pngSize,
      'sourceSha256': _pngSha256,
    });
  }

  static Future<String> _sha256(Uint8List bytes) async {
    // Use the host tool (macOS/Linux); only the digest goes to stdout.
    final process = await Process.start('shasum', ['-a', '256']);
    final output = process.stdout.transform(utf8.decoder).join();
    final error = process.stderr.drain<void>();
    process.stdin.add(bytes);
    await process.stdin.close();
    final digest = (await output).split(' ').first;
    await error;
    _require(await process.exitCode == 0);
    _require(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest));
    return digest;
  }

  static void _requireNoPayload(ApiReply reply) {
    if (reply.body.trim().isEmpty) return;
    final json = apiObject(jsonDecode(reply.body));
    _require(
      const [
        'Body',
        'FileDataBase64',
        'FileBytes',
        'Ciphertext',
      ].every((field) => json[field] == null),
    );
    _require(json['AccessGranted'] == null || json['AccessGranted'] == false);
  }

  @override
  Future<void> _exercise(String sender, String recipient, int contentId) async {
    await _step('Sender open denied without a payload', () async {
      final reply = await _open('Sender open', sender, contentId);
      _require(reply.status == 404);
      _requireNoPayload(reply);
      await _record({'event': 'senderOpenDenied', 'status': reply.status});
    });
    final sessionId = await _step('Verify recipient PNG delivery', () async {
      await _record({'event': 'recipientOpenAttempt'});
      final reply = await _open('Recipient open', recipient, contentId);
      final session = _knownSession;
      if (session != null) {
        await _record({'event': 'sessionObserved', 'sessionId': session.id});
      }
      _require(reply.status == 200);
      final json = apiObject(jsonDecode(reply.body));
      final decision = ApiAccessDecision.fromJson(json);
      _require(
        decision.granted &&
            !decision.suspended &&
            !decision.ended &&
            !decision.deviceVerified &&
            decision.sessionId == session?.id &&
            session?.token == recipient &&
            json['Title'] == _pngTitle &&
            (!json.containsKey('ContentId') ||
                json['ContentId'] == contentId) &&
            (!json.containsKey('ContentID') ||
                json['ContentID'] == contentId) &&
            json['FileType'] == 'image/png' &&
            json['Body'] == null,
      );
      final encoded = apiString(json['FileDataBase64']);
      _require(encoded.length == classroomSyntheticPng.length);
      final bytes = base64Decode(encoded);
      final String digest;
      try {
        _require(bytes.length == _pngSize);
        digest = await _sha256(bytes);
        _require(digest == _pngSha256);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      await _record({
        'event': 'pngVerified',
        'status': reply.status,
        'mime': 'image/png',
        'byteSize': _pngSize,
        'sha256': digest,
      });
      progress('Recipient PNG: image/png, $_pngSize bytes, SHA-256 $digest');
      return session!.id;
    });

    final check = 'api/content/sessions/$sessionId/check';
    await _step(
      'Authenticated non-recipient cannot use the active session',
      () async {
        // The sender is the only approved authenticated non-recipient. Check
        // while active so denial tests account binding, not session expiry.
        final reply = await _exchange(
          'Non-recipient active check',
          'POST',
          check,
          sender,
          {},
        );
        _require(reply.status == 404);
        _requireNoPayload(reply);
        await _record({'event': 'nonRecipientDenied', 'status': reply.status});
      },
    );
    await _step(
      'Recipient session ended',
      () => _endKnownSession('Recipient end'),
    );
    await _step('Ended session cannot retrieve the PNG', () async {
      final reply = await _exchange(
        'Recipient post-end check',
        'POST',
        check,
        recipient,
        {},
      );
      _requireNoPayload(reply);
      if (reply.status != 404) {
        final json = apiObject(jsonDecode(reply.body));
        _require(
          reply.status == 403 &&
              json['AccessGranted'] == false &&
              json['SessionEnded'] == true,
        );
      }
      await _record({'event': 'endedSessionRejected', 'status': reply.status});
    });
  }
}

/// Leaves the first and only recipient view for the separately approved app run.
class _ClassroomFlutterPngSetup extends _ClassroomPng {
  _ClassroomFlutterPngSetup(
    super.config,
    super.transport,
    super.progress,
    super.journal,
  );

  @override
  String get title => flutterPngFixtureTitle;

  @override
  int get maxViews => flutterPngFixtureMaxViews;

  @override
  Future<void> _exercise(String sender, String recipient, int contentId) async {
    _require(
      !flutterPngFixtureArchivedIds.contains(contentId) &&
          !config.archivedPngIds.contains(contentId),
    );
    await _record({
      'event': 'fixtureReadyForFlutter',
      'contentId': contentId,
      'title': title,
      'maxViews': maxViews,
    });
    progress(
      'Fresh fixture verified in both listings. No viewing routes used.',
    );
  }
}
