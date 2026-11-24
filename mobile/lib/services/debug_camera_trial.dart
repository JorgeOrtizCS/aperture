import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Numeric/text metadata only. Never stores camera pixels or document content.
class DebugCameraTrial extends ChangeNotifier {
  DebugCameraTrial._(this.label, this.condition)
    : startedAt = DateTime.now().toUtc(),
      id = '${label}_${DateTime.now().toUtc().microsecondsSinceEpoch}';

  static DebugCameraTrial? current;
  static int _logSequence = 0;

  /// Split numeric metadata to avoid the iPhone console's line-size limit.
  static List<String> cameraLogLines(Map<dynamic, dynamic> payload) {
    if (!kDebugMode) return const [];
    final core = Map<String, dynamic>.from(payload);
    final boxes = core.remove('debug_detections') as List? ?? const [];
    final eventId = ++_logSequence;
    core.addAll({
      ...?current?.tags,
      'debug_event_id': eventId,
      'debug_candidate_count': boxes.length,
      if (current?.ended ?? false) 'debug_after_trial_end': true,
    });
    return [
      '[ApertureCameraBridge] event ${jsonEncode(core)}',
      for (var index = 0; index < boxes.length; index++)
        '[ApertureCameraBox] ${jsonEncode({'debug_event_id': eventId, 'session_id': payload['session_id'], 'candidate_index': index, 'candidate': boxes[index]})}',
    ];
  }

  static DebugCameraTrial begin(String label, String condition) {
    if (!kDebugMode) throw StateError('Camera trials require a debug build.');
    final trial = DebugCameraTrial._(label, condition);
    current = trial;
    trial.log('begin');
    return trial;
  }

  final String id;
  final String label;
  final String condition;
  final DateTime startedAt;
  DateTime? firstFrameAt;
  int frames = 0;
  int phoneFrames = 0;
  double maxPhoneConfidence = 0;
  bool ended = false;
  String? reason;

  Map<String, Object> get tags => {
    'debug_trial_id': id,
    'debug_trial_label': label,
    'debug_trial_condition': condition,
  };

  void frame(Map<dynamic, dynamic> payload) {
    if (!kDebugMode || ended) return;
    firstFrameAt ??= DateTime.now().toUtc();
    frames++;
    final confidence = (payload['phone_confidence'] as num).toDouble();
    if (confidence > maxPhoneConfidence) maxPhoneConfidence = confidence;
    if (payload['phone_detected'] == true) phoneFrames++;
    notifyListeners();
  }

  void log(String action, [Map<String, Object?> extra = const {}]) {
    if (!kDebugMode) return;
    debugPrintSynchronously(
      '[ApertureTrial] ${jsonEncode({...tags, 'action': action, 'timestamp': DateTime.now().toUtc().toIso8601String(), ...extra})}',
    );
  }

  void finish(String endReason) {
    if (!kDebugMode || ended) return;
    ended = true;
    reason = endReason;
    log('end', {
      'reason': endReason,
      'frames': frames,
      'phone_frames': phoneFrames,
      'maximum_phone_confidence': maxPhoneConfidence,
      'elapsed_since_first_frame_ms': firstFrameAt == null
          ? null
          : DateTime.now().toUtc().difference(firstFrameAt!).inMilliseconds,
      'user_observation': 'pending',
    });
    notifyListeners();
  }
}
