import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/aperture_button.dart';
import '../widgets/content_restrictions_section.dart';
import '../widgets/section_header.dart';
import 'secure_content_viewer_screen.dart';

class SecureViewerScreen extends StatefulWidget {
  final String contentTitle;
  final String ownerName;

  const SecureViewerScreen({
    super.key,
    this.contentTitle = 'Project Document',
    this.ownerName = 'Alex Morgan',
  });

  @override
  State<SecureViewerScreen> createState() => _SecureViewerScreenState();
}

class _SecureViewerScreenState extends State<SecureViewerScreen> {
  bool _accessSuspended = false;
  static const ContentRestrictions _sampleRestrictions = ContentRestrictions(
    allowDownload: false,
    allowResharing: false,
    restrictScreenshots: true,
    accessDuration: AccessDuration.twoDays,
    viewLimit: 3,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: const Text('Secure Viewer'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.contentTitle,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Shared by ${widget.ownerName}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _accessSuspended
                  ? 'Access is suspended until the required conditions are satisfied again.'
                  : 'Viewing conditions are currently satisfied.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: _accessSuspended
                    ? AppTheme.warning
                    : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Content',
              icon: Icons.visibility_outlined,
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _accessSuspended
                  ? const _SuspendedPanel()
                  : _ProtectedContentSummary(contentTitle: widget.contentTitle),
            ),
            const SizedBox(height: 16),
            ApertureButton(
              label: 'Open Secure Content',
              icon: Icons.open_in_full_outlined,
              onPressed: _accessSuspended
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SecureContentViewerScreen(
                            contentTitle: widget.contentTitle,
                          ),
                        ),
                      );
                    },
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Security Policy',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 14),
            _PolicySummary(
              restrictions: _sampleRestrictions,
              expiresLabel:
                  'Expires in ${_sampleRestrictions.accessDuration.label}',
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Condition Checks',
              icon: Icons.verified_outlined,
            ),
            const SizedBox(height: 14),
            _ConditionRow(
              title: 'Recipient authorization',
              satisfied: true,
              detail: 'You are listed as an approved viewer.',
            ),
            _ConditionRow(
              title: 'Location requirement',
              satisfied: !_accessSuspended,
              detail: _accessSuspended
                  ? 'Approved location is not currently confirmed.'
                  : 'Approved location confirmed.',
            ),
            const _ConditionRow(
              title: 'Time window',
              satisfied: true,
              detail: 'Content has not expired.',
            ),
            const _ConditionRow(
              title: 'Capture protection',
              satisfied: true,
              detail: 'Screenshot protection is active when supported.',
            ),
            const SizedBox(height: 28),
            ApertureButton(
              label: _accessSuspended
                  ? 'Simulate Conditions Restored'
                  : 'Simulate Condition Violation',
              icon: _accessSuspended
                  ? Icons.refresh_outlined
                  : Icons.warning_amber_outlined,
              isSecondary: !_accessSuspended,
              onPressed: () {
                setState(() {
                  _accessSuspended = !_accessSuspended;
                });
              },
            ),
            const SizedBox(height: 12),
            ApertureButton(
              label: 'Request Temporary Access',
              icon: Icons.lock_clock_outlined,
              isSecondary: true,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Temporary access requests will connect to notifications later.',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicySummary extends StatelessWidget {
  final ContentRestrictions restrictions;
  final String expiresLabel;

  const _PolicySummary({
    required this.restrictions,
    required this.expiresLabel,
  });

  @override
  Widget build(BuildContext context) {
    final viewLimit = restrictions.viewLimit == null
        ? 'No view limit'
        : '${restrictions.viewLimit} views maximum';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _PolicyLine(
            icon: Icons.schedule_outlined,
            label: expiresLabel,
            emphasized: true,
          ),
          const SizedBox(height: 12),
          _PolicyLine(
            icon: Icons.visibility_outlined,
            label: viewLimit,
            emphasized: true,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RestrictionChip(
                icon: Icons.file_download_off_outlined,
                label: restrictions.allowDownload
                    ? 'Download allowed'
                    : 'Download blocked',
                blocked: !restrictions.allowDownload,
              ),
              _RestrictionChip(
                icon: Icons.share_outlined,
                label: restrictions.allowResharing
                    ? 'Reshare allowed'
                    : 'Reshare blocked',
                blocked: !restrictions.allowResharing,
              ),
              _RestrictionChip(
                icon: Icons.screenshot_monitor_outlined,
                label: restrictions.restrictScreenshots
                    ? 'Screenshots restricted'
                    : 'Screenshots not restricted',
                blocked: restrictions.restrictScreenshots,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PolicyLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasized;

  const _PolicyLine({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _RestrictionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool blocked;

  const _RestrictionChip({
    required this.icon,
    required this.label,
    required this.blocked,
  });

  @override
  Widget build(BuildContext context) {
    final color = blocked ? AppTheme.warning : AppTheme.success;
    final background = blocked
        ? const Color(0xFFFFFBEB)
        : const Color(0xFFECFDF5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  final String title;
  final bool satisfied;
  final String detail;

  const _ConditionRow({
    required this.title,
    required this.satisfied,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final color = satisfied ? AppTheme.success : AppTheme.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Icon(
              satisfied ? Icons.check_circle_outline : Icons.error_outline,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtectedContentSummary extends StatelessWidget {
  final String contentTitle;

  const _ProtectedContentSummary({required this.contentTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('protected'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: AppTheme.primary,
                size: 36,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Aperture preview',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            contentTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Access is ready. Open the secure viewer to render the protected PDF, image, or text content when that renderer is connected.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: AppTheme.success),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Protected content remains behind the secure viewing step.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuspendedPanel extends StatelessWidget {
  const _SuspendedPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('suspended'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            color: AppTheme.warning,
            size: 36,
          ),
          SizedBox(height: 18),
          Text(
            'Content hidden',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'The secure viewer hides protected content when the backend reports that a viewing condition is no longer met.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
