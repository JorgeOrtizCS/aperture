part of 'api_acceptance.dart';

class _ClassroomRevocation extends _ClassroomSession {
  _ClassroomRevocation(
    super.config,
    super.transport,
    super.progress,
    super.journal,
  );

  @override
  Map<String, Object> get fixture => {
    ...super.fixture,
    'Title': 'Aperture synthetic acceptance - pause resume revoke',
    'Body': 'Synthetic text for pause, resume, session replacement, and revocation acceptance.',
    'MaxViews': 2,
  };

  Future<void> _change(
    String label,
    String sender,
    String recipient,
    int contentId, {
    String? policy,
  }) async {
    await _record({'event': '${label}Attempt'});
    try {
      final route = policy == null ? 'revoke' : 'policy';
      final reply = await _exchange(
        '$label acknowledgement',
        'POST',
        'api/content/$contentId/$route',
        sender,
        policy == null ? null : {'Status': policy},
      );
      _require(reply.status == 200);
      final body = apiObject(jsonDecode(reply.body));
      _require(
        policy == null ? body['success'] == true : body['status'] == policy,
      );
    } catch (_) {
      // A lost acknowledgement can follow a committed mutation. Only read back
      // metadata, and stop the workflow even if the expected state is visible.
      await _reconcileChange(label, sender, recipient, contentId, policy);
      rethrow;
    }
    await _record({'event': '${label}Acknowledged'});
  }

  Future<void> _reconcileChange(
    String label,
    String sender,
    String recipient,
    int contentId,
    String? policy,
  ) async {
    for (final (role, token) in [
      ('Sender', sender),
      ('Recipient', recipient),
    ]) {
      try {
        final rows = await _fixtureRows('$role $label reconciliation', token);
        final row = rows.single;
        _verifyRow(
          row,
          contentId,
          mine: role == 'Sender',
          status: policy == null ? 'Revoked' : 'Active',
          policy: policy ?? 'Active',
        );
        progress('$role $label reconciliation: expected state observed');
      } catch (_) {
        progress('$role $label reconciliation: expected state unconfirmed');
      }
    }
  }

  void _requireDenial(ApiReply reply, {bool allowTerminal403 = false}) {
    _require(reply.status == 404 || (allowTerminal403 && reply.status == 403));
    if (reply.status == 404 && reply.body.trim().isEmpty) return;
    final body = apiObject(jsonDecode(reply.body));
    _require(
      body['Body'] == null &&
          body['FileDataBase64'] == null &&
          body['Ciphertext'] == null &&
          body['FileBytes'] == null &&
          (body['AccessGranted'] == null || body['AccessGranted'] == false),
    );
    if (reply.status == 403) {
      _require(body['AccessGranted'] == false && body['SessionEnded'] == true);
      progress('Observed terminal HTTP 403 in place of the pinned HTTP 404');
    }
  }

  Future<void> _verifyInvalid(
    String label,
    String recipient,
    int sessionId,
  ) async {
    final reply = await _exchange(
      label,
      'POST',
      'api/content/sessions/$sessionId/check',
      recipient,
      {},
    );
    _requireDenial(reply, allowTerminal403: true);
    if (_knownSession?.id == sessionId) _knownSession = null;
  }

  @override
  Future<void> _exercise(String sender, String recipient, int contentId) async {
    final first = await _step(
      'First recipient session granted',
      () => _openRecipient('First recipient open', recipient, contentId),
    );
    await _step('Sender pause confirmed in both listings', () async {
      await _change('Pause', sender, recipient, contentId, policy: 'Paused');
      await _verifyListings(sender, recipient, contentId, policy: 'Paused');
    });
    await _step('Pause invalidates the first session', () async {
      await _verifyInvalid('First session after pause', recipient, first);
      await _record({'event': 'firstSessionInvalidated'});
    });
    await _step('Sender resume confirmed in both listings', () async {
      await _change('Resume', sender, recipient, contentId, policy: 'Active');
      await _verifyListings(sender, recipient, contentId);
    });
    await _step('Resume does not restore the first session', () async {
      // If the old session unexpectedly works again, it is eligible for cleanup.
      _knownSession = (token: recipient, id: first);
      await _verifyInvalid('First session after resume', recipient, first);
      await _record({'event': 'firstSessionStillInvalid'});
    });
    final second = await _step(
      'Fresh second recipient session granted',
      () async {
        final id = await _openRecipient(
          'Second recipient open',
          recipient,
          contentId,
        );
        _require(id != first);
        return id;
      },
    );
    await _step(
      'Sender revocation acknowledged',
      () => _change('Revoke', sender, recipient, contentId),
    );
    await _step('Revocation invalidates the second session', () async {
      await _verifyInvalid('Second session after revoke', recipient, second);
      await _record({'event': 'secondSessionInvalidated'});
    });
    await _step('Recipient cannot reopen revoked share', () async {
      final reply = await _open(
        'Recipient open after revoke',
        recipient,
        contentId,
      );
      _requireDenial(reply);
      await _record({'event': 'revokedOpenDenied'});
    });
    await _step('Both listings confirm revoked access', () async {
      await _verifyListings(sender, recipient, contentId, status: 'Revoked');
      await _record({'event': 'revokedListingsVerified'});
    });
  }
}
