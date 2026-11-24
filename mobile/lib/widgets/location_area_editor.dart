import 'package:flutter/material.dart';

import '../models/location_radius_policy.dart';

class LocationAreaEditor extends StatelessWidget {
  final SenderLocationDraft draft;
  final ValueChanged<SenderLocationDraft> onChanged;
  final bool serverEdit;
  const LocationAreaEditor({
    super.key,
    required this.draft,
    required this.onChanged,
    this.serverEdit = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (serverEdit)
        const Text('Viewing area. Changes require server confirmation.')
      else
        SwitchListTile(
          key: const ValueKey('location-area-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Require a viewing area'),
          subtitle: const Text(
            'Local policy preview. No location is uploaded or access granted.',
          ),
          value: draft.enabled,
          onChanged: (value) => onChanged(draft.copyWith(enabled: value)),
        ),
      if (draft.enabled) ...[
        const Text(
          'Choose the center by entering its coordinates. Device location is not requested.',
        ),
        TextFormField(
          key: const ValueKey('location-center-latitude'),
          initialValue: draft.latitude,
          decoration: const InputDecoration(
            labelText: 'Center latitude (−90 to 90)',
          ),
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          onChanged: (value) => onChanged(draft.copyWith(latitude: value)),
        ),
        TextFormField(
          key: const ValueKey('location-center-longitude'),
          initialValue: draft.longitude,
          decoration: const InputDecoration(
            labelText: 'Center longitude (−180 to 180)',
          ),
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          onChanged: (value) => onChanged(draft.copyWith(longitude: value)),
        ),
        DropdownButtonFormField<LocationRadiusPreset>(
          key: const ValueKey('location-radius-preset'),
          initialValue: draft.preset,
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(labelText: 'Viewing radius'),
          items: [
            for (final preset in LocationRadiusPreset.values)
              DropdownMenuItem(
                value: preset,
                child: Text(
                  preset.meters == null
                      ? '${preset.label}: 10–10,000 m'
                      : '${preset.label}: ${preset.meters} m',
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(draft.copyWith(preset: value));
          },
        ),
        if (draft.preset == LocationRadiusPreset.custom)
          TextFormField(
            key: const ValueKey('location-custom-radius'),
            initialValue: draft.customRadius,
            decoration: const InputDecoration(
              labelText: 'Custom radius in meters (10–10,000)',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) =>
                onChanged(draft.copyWith(customRadius: value)),
          ),
        Text(
          'Selected radius: ${draft.radiusMeters?.toStringAsFixed(1) ?? 'invalid'} m',
        ),
        if (draft.radiusMeters != null && draft.radiusMeters! <= 100)
          const Text(
            'Small areas can be difficult to verify, especially indoors. Location uncertainty must fit entirely inside the area.',
          ),
        if (!draft.valid)
          const Text(
            'Enter a valid center and a radius from 10 to 10,000 meters before saving.',
          ),
      ],
    ],
  );
}
