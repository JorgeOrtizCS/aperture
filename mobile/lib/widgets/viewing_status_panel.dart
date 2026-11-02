import 'package:flutter/material.dart';

import '../controllers/viewing_state_controller.dart';
import '../services/screen_capture_protection.dart';
import '../services/viewing_conditions.dart';
import '../theme/app_theme.dart';

String viewingConditionLabel(String id) => switch (id) {
  ViewingCondition.authorization => 'Recipient authorization',
  ViewingCondition.expiration => 'Expiration',
  ViewingCondition.viewLimit => 'Maximum views',
  'location' => 'Approved location',
  'presence' => 'Viewer presence',
  DemoViewingConditions.condition => 'Demo viewing condition',
  _ => 'Required viewing condition',
};

({String title, String message, IconData icon}) viewingIssueMessage(
  ViewingIssue issue,
) {
  final condition = viewingConditionLabel(issue.condition ?? '');
  return switch (issue.kind) {
    ViewingIssueKind.phoneDetected => (
      title: 'Phone detected',
      message: 'A phone was detected by the camera. Protected content is hidden and this viewing session has ended. Clear frames and rechecking cannot restore this session.',
      icon: Icons.phonelink_lock_outlined,
    ),
    ViewingIssueKind.screenshot => (
      title: 'Screenshot detected',
      message: 'This viewing session has ended. A screenshot may already have been saved. Rechecking cannot restore this session.',
      icon: Icons.screenshot_monitor_outlined,
    ),
    ViewingIssueKind.simulatedViolation => (
      title: 'Demo security violation',
      message: 'A simulated violation ended this viewing session. This is a demo result, not a detected security event.',
      icon: Icons.science_outlined,
    ),
    ViewingIssueKind.expired => (
      title: 'Content expired',
      message: 'The viewing period has ended. Ask the owner for new access.',
      icon: Icons.event_busy_outlined,
    ),
    ViewingIssueKind.viewLimitReached => (
      title: 'View limit reached',
      message: 'The maximum number of views has been reached. Ask the owner for new access.',
      icon: Icons.visibility_off_outlined,
    ),
    ViewingIssueKind.authorizationDenied => (
      title: 'Authorization denied',
      message: 'You are not authorized to view this content. Contact the owner if you believe this is a mistake.',
      icon: Icons.person_off_outlined,
    ),
    ViewingIssueKind.conditionDenied => (
      title: '$condition denied',
      message: 'A required check denied access. This session cannot be restored with Recheck Conditions.',
      icon: Icons.block_outlined,
    ),
    ViewingIssueKind.conditionFailed => (
      title: '$condition failed',
      message: 'Content stays hidden while this requirement is not met. Restore the required conditions, then recheck.',
      icon: Icons.lock_outline,
    ),
    ViewingIssueKind.unknownCondition => (
      title: '$condition not confirmed',
      message: 'No verified result is available for this required check. Content stays hidden.',
      icon: Icons.help_outline,
    ),
    ViewingIssueKind.captureDetected => (
      title: 'Screen capture detected',
      message: 'Screen recording or mirroring is active. Stop recording or sharing your screen. Viewing can resume only when all required checks pass.',
      icon: Icons.screen_share_outlined,
    ),
    ViewingIssueKind.protectionUnavailable => (
      title: 'Capture protection unavailable',
      message: 'Aperture could not confirm native capture protection. Content stays hidden. Close and reopen the viewer; if the problem continues, restart the app.',
      icon: Icons.gpp_bad_outlined,
    ),
    ViewingIssueKind.monitoringUnavailable => (
      title: 'Condition monitoring unavailable',
      message: 'Required viewing checks could not be completed or monitored. Rechecking must succeed before content can appear.',
      icon: Icons.sensors_off_outlined,
    ),
    ViewingIssueKind.inactive => (
      title: 'App inactive',
      message: 'Content is hidden while the app is inactive. Security checks run again when you return.',
      icon: Icons.pause_circle_outline,
    ),
  };
}

class ViewingActionButton extends StatelessWidget {
  const ViewingActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.refresh_outlined,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool secondary;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, textAlign: TextAlign.center),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        backgroundColor: secondary ? Colors.white : AppTheme.primary,
        foregroundColor: secondary ? AppTheme.primary : Colors.white,
        elevation: 0,
        side: secondary ? const BorderSide(color: AppTheme.inputBorder) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

/// Presentation only: all status, reasons and recovery eligibility come from the
/// same controller that gates content. Actions always invoke reevaluation.
class ViewingStatusPanel extends StatelessWidget {
  const ViewingStatusPanel({
    super.key,
    required this.controller,
    this.onRecheck,
  });
  final ViewingStateController controller;
  final VoidCallback? onRecheck;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final title = switch (state) {
      ViewingState.checking =>
        controller.hasStarted ? 'Checking conditions' : 'Check before viewing',
      ViewingState.allowed =>
        controller.demoPreview ? 'Demo preview ready' : 'Ready to view',
      ViewingState.temporarilyLocked => 'Content Hidden',
      ViewingState.accessDenied =>
        controller.securityViolation ? 'Viewing ended' : 'Access denied',
      ViewingState.protectionUnavailable => 'Protection unavailable',
    };
    final color = switch (state) {
      ViewingState.allowed => AppTheme.success,
      ViewingState.accessDenied => AppTheme.danger,
      ViewingState.checking => AppTheme.primary,
      _ => AppTheme.warning,
    };
    final icon = switch (state) {
      ViewingState.allowed => Icons.check_circle_outline,
      ViewingState.checking => Icons.shield_outlined,
      ViewingState.accessDenied => Icons.block_outlined,
      ViewingState.protectionUnavailable => Icons.gpp_bad_outlined,
      _ => Icons.lock_outline,
    };
    final checkingOrAllowed =
        state == ViewingState.checking || state == ViewingState.allowed;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: ValueKey('viewing-status-${state.name}'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 40, color: color)),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (checkingOrAllowed)
              Text(
                state == ViewingState.allowed
                    ? controller.demoPreview
                          ? 'Only the placeholder demo checks passed. This does not verify access to real content.'
                          : 'Required checks passed for this session. Monitoring continues while you view.'
                    : !controller.hasStarted
                    ? 'Run the required security checks before opening content. No access has been verified yet.'
                    : controller.isRechecking
                    ? 'Security recheck in progress. Content stays hidden until all required checks pass again.'
                    : 'Security checks in progress. Content stays hidden until protection and all required conditions are confirmed.',
                style: const TextStyle(
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              )
            else
              for (final issue in controller.issues) ...[
                _IssueMessage(issue: issue),
                const SizedBox(height: 12),
              ],
            if (!controller.hasStarted &&
                !controller.sessionEnded &&
                onRecheck != null) ...[
              const SizedBox(height: 16),
              ViewingActionButton(
                label: 'Check Conditions',
                onPressed: onRecheck,
              ),
            ] else if (controller.canRecheck && onRecheck != null) ...[
              const SizedBox(height: 16),
              ViewingActionButton(
                label: 'Recheck Conditions',
                onPressed: onRecheck,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IssueMessage extends StatelessWidget {
  const _IssueMessage({required this.issue});
  final ViewingIssue issue;
  @override
  Widget build(BuildContext context) {
    final message = viewingIssueMessage(issue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                message.icon,
                size: 22,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          message.message,
          style: const TextStyle(height: 1.5, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class ViewingConditionList extends StatelessWidget {
  const ViewingConditionList({super.key, required this.controller});
  final ViewingStateController controller;

  @override
  Widget build(BuildContext context) {
    final capture = controller.captureState;
    return Column(
      children: [
        _ConditionRow(
          title: 'Native capture protection',
          status: !controller.hasStarted
              ? 'Not checked'
              : switch (capture) {
                  CaptureProtectionState.checking => 'Checking',
                  CaptureProtectionState.ready => 'Available for this session',
                  CaptureProtectionState.captureActive =>
                    'Recording or mirroring detected',
                  CaptureProtectionState.unavailable => 'Unavailable',
                },
          passed:
              controller.hasStarted && capture == CaptureProtectionState.ready,
        ),
        for (final id in controller.requiredConditions)
          _ConditionRow(
            title: viewingConditionLabel(id),
            status: switch (controller.results[id] ??
                ViewingConditionResult.unknown) {
              ViewingConditionResult.satisfied =>
                controller.demoPreview ? 'Met in demo only' : 'Met',
              ViewingConditionResult.failed => 'Not met',
              ViewingConditionResult.denied => 'Denied',
              ViewingConditionResult.unknown =>
                controller.state == ViewingState.checking &&
                        controller.hasStarted
                    ? 'Checking'
                    : 'Not confirmed',
            },
            passed: controller.results[id] == ViewingConditionResult.satisfied,
          ),
      ],
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.title,
    required this.status,
    required this.passed,
  });
  final String title;
  final String status;
  final bool passed;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            passed ? Icons.check_circle_outline : Icons.info_outline,
            color: passed ? AppTheme.success : AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                status,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
