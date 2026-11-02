import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'content_restrictions_section.dart';

class ContentRestrictionsSummary extends StatelessWidget {
  final ContentRestrictions restrictions;

  const ContentRestrictionsSummary({required this.restrictions, super.key});

  @override
  Widget build(BuildContext context) {
    final viewLimit = restrictions.viewLimit == null
        ? 'Maximum views: Unlimited'
        : 'Maximum views: ${restrictions.viewLimit}';

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
            label:
                'Configured expiration: ${restrictions.accessDuration.label}',
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
                    ? 'Downloads: allowed by policy'
                    : 'Downloads: disallowed by policy',
                blocked: !restrictions.allowDownload,
              ),
              _RestrictionChip(
                icon: Icons.share_outlined,
                label: restrictions.allowResharing
                    ? 'Resharing: allowed by policy'
                    : 'Resharing: disallowed by policy',
                blocked: !restrictions.allowResharing,
              ),
              _RestrictionChip(
                icon: Icons.screenshot_monitor_outlined,
                label: restrictions.restrictScreenshots
                    ? 'Screenshot restriction: requested'
                    : 'Screenshot restriction: not requested',
                blocked: restrictions.restrictScreenshots,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Local demo policy only. These selections are not enforced; capture protection operates independently.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
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
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
