import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'content_restrictions_section.dart';

class ContentRestrictionsSummary extends StatelessWidget {
  final ContentRestrictions restrictions;
  final bool senderDraft;

  const ContentRestrictionsSummary({
    required this.restrictions,
    super.key,
    this.senderDraft = false,
  });

  @override
  Widget build(BuildContext context) {
    final area = restrictions.locationArea;
    final radius = area.radiusMeters?.toStringAsFixed(1);
    final areaLabel = !area.enabled
        ? restrictions.networkLocation.enabled
              ? 'Network location · ${restrictions.networkLocation.parts.join(', ')}'
              : 'No area selected'
        : area.valid
        ? '$radius m radius'
        : 'Invalid area';
    final expirationLabel = senderDraft
        ? 'Expiration duration'
        : 'Configured expiration';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          if (senderDraft || area.enabled) ...[
            _PolicyLine(
              icon: Icons.location_on_outlined,
              label: senderDraft
                  ? 'Viewing area: $areaLabel'
                  : 'Viewing radius: ${radius ?? 'invalid'} m (local preview)',
              details: senderDraft && area.enabled
                  ? 'Review the center in Edit Policy.'
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          if (senderDraft && restrictions.viewingStartsAt != null) ...[
            _PolicyLine(
              icon: Icons.schedule_outlined,
              label:
                  'Viewing starts at ${restrictions.viewingStartsAt!.toUtc().toIso8601String()}',
            ),
            const SizedBox(height: 12),
          ],
          _PolicyLine(
            icon: Icons.schedule_outlined,
            label: '$expirationLabel: ${restrictions.accessDuration.label}',
            emphasized: true,
          ),
          const SizedBox(height: 12),
          _PolicyLine(
            icon: Icons.visibility_outlined,
            label: 'Maximum views: ${restrictions.viewLimit ?? 'Unlimited'}',
            emphasized: true,
          ),
          const SizedBox(height: 16),
          if (senderDraft) ...[
            if (restrictions.requireTrustedDevice) ...[
              const _PolicyLine(
                icon: Icons.devices_outlined,
                label: 'Service-approved device required in draft',
              ),
              const SizedBox(height: 12),
            ],
            _PolicyLine(
              icon: Icons.screenshot_monitor_outlined,
              label: restrictions.restrictScreenshots
                  ? 'Screenshot restriction: Requested in draft'
                  : 'Screenshot restriction: No preference selected',
            ),
          ] else
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
          Text(
            senderDraft
                ? 'Kept only while this draft is open. These choices are not enforced for recipients. Download and resharing permissions are unavailable.'
                : 'Local demo policy only. These selections are not enforced; capture protection operates independently.',
            style: const TextStyle(
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
  final String? details;
  final bool emphasized;

  const _PolicyLine({
    required this.icon,
    required this.label,
    this.details,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final details = this.details;
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (details != null)
                Text(
                  details,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
            ],
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
