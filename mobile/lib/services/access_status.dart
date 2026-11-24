import 'package:flutter/foundation.dart';

enum AccessStatusSource { serverResponse, serverMetadata, device }

enum AccessStatusKind {
  accessGranted,
  accessDenied,
  sessionSuspended,
  sessionEnded,
  contentPaused,
  contentRevoked,
  viewingWindowExpired,
  locationDenied,
  locationBlocked,
  locationApproximate,
  locationUnavailable,
  cameraDenied,
  cameraBlocked,
  cameraUnavailable,
  biometricUnavailable,
  biometricCancelled,
  networkInterrupted,
  securityUnavailable,
}

enum AccessStatusTopic {
  server,
  connection,
  location,
  camera,
  biometric,
  policy,
  security,
}

typedef AccessStatus = ({AccessStatusKind kind, AccessStatusSource source});

/// Latest observations for the signed-in account. The feed stores typed
/// statuses only, with content IDs used internally to replace older checks.
class AccessStatusFeed extends ChangeNotifier {
  static const _maxContentItems = 24;
  final _entries = <int, AccessStatusReporter>{};

  Iterable<AccessStatus> get entries => _entries.values
      .toList()
      .reversed
      .expand((reporter) => reporter._latest.values.toList().reversed);

  AccessStatusReporter beginViewing(int contentId) {
    final previous = _entries.remove(contentId);
    final reporter = AccessStatusReporter._(this, contentId);
    _entries[contentId] = reporter;
    AccessStatusReporter? evicted;
    if (_entries.length > _maxContentItems) {
      evicted = _entries.remove(_entries.keys.first);
    }
    if (previous?._latest.isNotEmpty == true ||
        evicted?._latest.isNotEmpty == true) {
      notifyListeners();
    }
    return reporter;
  }

  void _changed() => notifyListeners();

  void clear() {
    final hadEntries = _entries.values.any((entry) => entry._latest.isNotEmpty);
    _entries.clear(); // Invalidates every reporter, including in-flight work.
    if (hadEntries) notifyListeners();
  }

  @override
  void dispose() {
    _entries.clear();
    super.dispose();
  }
}

/// The owner closes its reporter when its viewing route is disposed. Results
/// remain readable until a new attempt for that content or an account change.
class AccessStatusReporter {
  AccessStatusReporter._(this._feed, this._contentId);
  final AccessStatusFeed _feed;
  final int _contentId;
  final _latest = <AccessStatusTopic, AccessStatus>{};
  bool _closed = false;

  void record(
    AccessStatusTopic topic,
    AccessStatusKind? kind, {
    AccessStatusSource source = AccessStatusSource.device,
  }) {
    if (_closed || !identical(_feed._entries[_contentId], this)) return;
    final next = kind == null ? null : (kind: kind, source: source);
    if (_latest[topic] == next) return;
    _latest.remove(topic);
    if (next != null) _latest[topic] = next;
    _feed._changed();
  }

  void close() => _closed = true;
}
