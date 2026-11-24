import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../models/location_radius_policy.dart';
import 'location_area_editor.dart';
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
  /// Initial policy for local demo content; this does not enable enforcement.
  static const demoDefaults = ContentRestrictions(
    allowDownload: false,
    allowResharing: false,
    restrictScreenshots: true,
    accessDuration: AccessDuration.twoDays,
    viewLimit: 3,
  );

  final bool allowDownload;
  final bool allowResharing;
  final bool restrictScreenshots;
  final bool requireTrustedDevice;
  final AccessDuration accessDuration;
  final int? viewLimit;
  final DateTime? viewingStartsAt;
  final SenderLocationDraft locationArea;
  final NetworkLocation networkLocation;

  const ContentRestrictions({
    required this.allowDownload,
    required this.allowResharing,
    required this.restrictScreenshots,
    this.requireTrustedDevice = false,
    required this.accessDuration,
    this.viewLimit,
    this.viewingStartsAt,
    this.locationArea = const SenderLocationDraft(),
    this.networkLocation = const NetworkLocation(),
  });

  ContentRestrictions copyWith({
    bool? allowDownload,
    bool? allowResharing,
    bool? restrictScreenshots,
    bool? requireTrustedDevice,
    AccessDuration? accessDuration,
    int? viewLimit,
    bool clearViewLimit = false,
    DateTime? viewingStartsAt,
    bool clearViewingStart = false,
    SenderLocationDraft? locationArea,
    NetworkLocation? networkLocation,
  }) {
    return ContentRestrictions(
      allowDownload: allowDownload ?? this.allowDownload,
      allowResharing: allowResharing ?? this.allowResharing,
      restrictScreenshots: restrictScreenshots ?? this.restrictScreenshots,
      requireTrustedDevice: requireTrustedDevice ?? this.requireTrustedDevice,
      accessDuration: accessDuration ?? this.accessDuration,
      viewLimit: clearViewLimit ? null : viewLimit ?? this.viewLimit,
      viewingStartsAt: clearViewingStart
          ? null
          : viewingStartsAt ?? this.viewingStartsAt,
      locationArea: locationArea ?? this.locationArea,
      networkLocation: networkLocation ?? this.networkLocation,
    );
  }
}

class ContentRestrictionsSection extends StatelessWidget {
  final ContentRestrictions restrictions;
  final ValueChanged<ContentRestrictions> onChanged;
  final bool senderDraft;

  const ContentRestrictionsSection({
    super.key,
    required this.restrictions,
    required this.onChanged,
    this.senderDraft = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LocationAreaEditor(
          draft: restrictions.locationArea,
          onChanged: (value) => onChanged(
            restrictions.copyWith(
              locationArea: value,
              networkLocation: value.enabled ? const NetworkLocation() : null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (senderDraft)
          const Text(
            'Download and resharing permissions are unavailable.',
            style: TextStyle(color: AppTheme.textSecondary),
          )
        else ...[
          RestrictionTile(
            title: 'Allow Download',
            subtitle: restrictions.allowDownload
                ? 'Policy permits saving a local copy.'
                : 'Policy does not permit downloading.',
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
                ? 'Policy permits sharing access with others.'
                : 'Policy does not permit resharing.',
            icon: Icons.ios_share_outlined,
            enabled: restrictions.allowResharing,
            onChanged: (value) {
              onChanged(restrictions.copyWith(allowResharing: value));
            },
          ),
        ],
        const SizedBox(height: 12),
        RestrictionTile(
          title: senderDraft
              ? 'Screenshot restriction preference'
              : 'Screenshot Protection',
          subtitle: senderDraft
              ? 'A draft preference. App capture protection operates independently.'
              : restrictions.restrictScreenshots
              ? 'Show screenshot restriction in the viewing policy.'
              : 'No screenshot restriction is selected.',
          icon: Icons.screenshot_monitor_outlined,
          enabled: restrictions.restrictScreenshots,
          onChanged: (value) {
            onChanged(restrictions.copyWith(restrictScreenshots: value));
          },
        ),
        if (senderDraft) ...[
          const SizedBox(height: 12),
          RestrictionTile(
            title: 'Require a service-approved device',
            subtitle: 'Recipients must use a device approved by the service.',
            icon: Icons.devices_outlined,
            enabled: restrictions.requireTrustedDevice,
            onChanged: (value) =>
                onChanged(restrictions.copyWith(requireTrustedDevice: value)),
          ),
        ],
        const SizedBox(height: 12),
        _PickerCard(
          icon: Icons.schedule_outlined,
          label: senderDraft ? 'Expiration duration' : 'Expiration',
          child: DropdownButtonFormField<AccessDuration>(
            isExpanded: true,
            isDense: false,
            itemHeight: null,
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
          label: senderDraft ? 'Maximum views' : 'View Limit',
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            isDense: false,
            itemHeight: null,
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
