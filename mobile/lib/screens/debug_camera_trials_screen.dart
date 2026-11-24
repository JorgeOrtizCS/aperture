import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/debug_camera_trial.dart';
import '../widgets/content_restrictions_section.dart';
import 'secure_content_viewer_screen.dart';
import 'welcome_screen.dart';

/// Debug-only launcher for the ordinary protected placeholder demo.
/// Uses the existing viewer/service, including its first-positive permanent latch.
class DebugCameraTrialsScreen extends StatefulWidget {
  const DebugCameraTrialsScreen({super.key});

  @override
  State<DebugCameraTrialsScreen> createState() =>
      _DebugCameraTrialsScreenState();
}

class _DebugCameraTrialsScreenState extends State<DebugCameraTrialsScreen> {
  static const conditions = {
    'A': 'Without glasses; no second phone; 60 seconds',
    'B': 'With glasses; no second phone; 60 seconds',
    'C': 'Glasses removed again; no second phone; 60 seconds',
    'D': 'With glasses; different lighting; no second phone; 60 seconds',
    'E': 'Actual second phone; without glasses',
    'F': 'Actual second phone; wearing glasses',
    'G': 'Actual second phone near face; glasses unobstructed',
  };

  String selected = 'A';
  bool running = false;
  DebugCameraTrial? trial;

  Future<void> start() async {
    if (!kDebugMode || running) return;
    final current = DebugCameraTrial.begin(selected, conditions[selected]!);
    setState(() {
      running = true;
      trial = current;
    });
    var timedOut = false;
    final route = MaterialPageRoute<SecureContentViewerExitReason>(
      builder: (_) => SecureContentViewerScreen.demo(
        contentTitle: 'Project Document — Trial ${current.label}',
        restrictions: ContentRestrictions.demoDefaults,
        onSecurityViolation: (reason) {
          current.finish('security_violation:${reason.name}');
        },
      ),
    );
    final completion = Navigator.of(context).push(route);
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (current.ended && (current.reason?.startsWith('camera_') ?? false)) {
        if (route.isCurrent) Navigator.of(context).pop();
        return;
      }
      final first = current.firstFrameAt;
      if (current.ended || first == null || current.phoneFrames != 0) return;
      final seconds = current.label.compareTo('D') <= 0 ? 60 : 10;
      if (DateTime.now().toUtc().difference(first).inSeconds >= seconds &&
          route.isCurrent) {
        timedOut = true;
        current.finish('observation_window_complete');
        Navigator.of(context).pop();
      }
    });
    try {
      final result = await completion;
      current.finish(
        result == SecureContentViewerExitReason.securityViolation
            ? 'security_violation'
            : timedOut
            ? 'observation_window_complete'
            : 'viewer_closed_or_interrupted',
      );
    } finally {
      timer.cancel();
      if (identical(DebugCameraTrial.current, current)) {
        DebugCameraTrial.current = null;
      }
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const WelcomeScreen();
    return Scaffold(
      appBar: AppBar(title: const Text('Camera trials — DEBUG ONLY')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Placeholder demo only. Normal camera, capture and permanent-lockout protections remain active. No images are saved.',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            items: conditions.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text('Trial ${e.key}'),
                  ),
                )
                .toList(),
            onChanged: running
                ? null
                : (value) => setState(() => selected = value!),
          ),
          const SizedBox(height: 12),
          Text(conditions[selected]!),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: running ? null : start,
            child: Text('Start trial $selected'),
          ),
          const Text(
            'A–D end after 60 seconds from the first valid frame, or earlier on a violation. E–G use a 10-second observation window. Test outcomes still require your observation.',
          ),
          if (trial != null) ...[
            const Divider(height: 32),
            Text('Last trial: ${trial!.label} · ${trial!.id}'),
            Text('End: ${trial!.reason ?? "running"}'),
            Text(
              'Frames: ${trial!.frames} · Phone events: ${trial!.phoneFrames}',
            ),
            Text('Maximum phone confidence: ${trial!.maxPhoneConfidence}'),
          ],
          const SizedBox(height: 24),
          TextButton(
            onPressed: running
                ? null
                : () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const WelcomeScreen(),
                    ),
                  ),
            child: const Text('Open normal app'),
          ),
        ],
      ),
    );
  }
}
