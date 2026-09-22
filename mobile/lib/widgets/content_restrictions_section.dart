import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'restriction_tile.dart';

enum AccessDuration {
  twelveHours('12 hours'),
  oneDay('24 hours'),
  twoDays('48 hours'),
  oneWeek('7 days');

  final String label;

  const AccessDuration(this.label);
}

class ContentRestrictions {
  final bool allowDownload;
  final bool allowResharing;
  final bool restrictScreenshots;
  final AccessDuration accessDuration;
  final int? viewLimit;

  const ContentRestrictions({
    required this.allowDownload,
    required this.allowResharing,
    required this.restrictScreenshots,
    required this.accessDuration,
    this.viewLimit,
  });

  ContentRestrictions copyWith({
    bool? allowDownload,
    bool? allowResharing,
    bool? restrictScreenshots,
    AccessDuration? accessDuration,
    int? viewLimit,
    bool clearViewLimit = false,
  }) {
    return ContentRestrictions(
      allowDownload: allowDownload ?? this.allowDownload,
      allowResharing: allowResharing ?? this.allowResharing,
      restrictScreenshots: restrictScreenshots ?? this.restrictScreenshots,
      accessDuration: accessDuration ?? this.accessDuration,
      viewLimit: clearViewLimit ? null : viewLimit ?? this.viewLimit,
    );
  }
}

class ContentRestrictionsSection extends StatelessWidget {
  final ContentRestrictions restrictions;
  final ValueChanged<ContentRestrictions> onChanged;

  const ContentRestrictionsSection({
    super.key,
    required this.restrictions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RestrictionTile(
          title: 'Allow Download',
          subtitle: restrictions.allowDownload
              ? 'Recipient may save a local copy.'
              : 'Download is disabled for the recipient.',
          icon: Icons.file_download_outlined,
          enabled: restrictions.allowDownload,
          onChanged: (value) {
            onChanged(restrictions.copyWith(allowDownload: value));
          },
        ),
        const SizedBox(height: 12),
        RestrictionTile(
          title: 'Allow Resharing',
          subtitle: restrictions.allowResharing
              ? 'Recipient may share access with others.'
              : 'Recipient cannot reshare this content.',
          icon: Icons.ios_share_outlined,
          enabled: restrictions.allowResharing,
          onChanged: (value) {
            onChanged(restrictions.copyWith(allowResharing: value));
          },
        ),
        const SizedBox(height: 12),
        RestrictionTile(
          title: 'Screenshot Protection',
          subtitle: restrictions.restrictScreenshots
              ? 'Show screenshot restriction in the viewing policy.'
              : 'No screenshot restriction is selected.',
          icon: Icons.screenshot_monitor_outlined,
          enabled: restrictions.restrictScreenshots,
          onChanged: (value) {
            onChanged(restrictions.copyWith(restrictScreenshots: value));
          },
        ),
        const SizedBox(height: 12),
        _PickerCard(
          icon: Icons.schedule_outlined,
          label: 'Expiration',
          child: DropdownButtonFormField<AccessDuration>(
            initialValue: restrictions.accessDuration,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            items: AccessDuration.values
                .map(
                  (duration) => DropdownMenuItem(
                    value: duration,
                    child: Text(duration.label),
                  ),
                )
                .toList(),
            onChanged: (duration) {
              if (duration == null) return;
              onChanged(restrictions.copyWith(accessDuration: duration));
            },
          ),
        ),
        const SizedBox(height: 12),
        _PickerCard(
          icon: Icons.visibility_outlined,
          label: 'View Limit',
          child: DropdownButtonFormField<String>(
            initialValue: restrictions.viewLimit?.toString() ?? 'unlimited',
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            items: const [
              DropdownMenuItem(value: 'unlimited', child: Text('Unlimited')),
              DropdownMenuItem(value: '1', child: Text('1 view')),
              DropdownMenuItem(value: '3', child: Text('3 views')),
              DropdownMenuItem(value: '5', child: Text('5 views')),
            ],
            onChanged: (value) {
              final limit = value == null || value == 'unlimited'
                  ? null
                  : int.parse(value);

              onChanged(
                restrictions.copyWith(
                  viewLimit: limit,
                  clearViewLimit: limit == null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PickerCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _PickerCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
