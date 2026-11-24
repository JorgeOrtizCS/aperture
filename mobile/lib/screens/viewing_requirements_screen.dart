import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../models/location_radius_policy.dart';
import '../theme/app_theme.dart';
import '../widgets/aperture_button.dart';
import '../widgets/content_restrictions_section.dart';

class ViewingRequirementsScreen extends StatefulWidget {
  final ContentRestrictions initialRestrictions;
  final bool senderDraft;

  const ViewingRequirementsScreen({
    super.key,
    required this.initialRestrictions,
    this.senderDraft = false,
  });

  @override
  State<ViewingRequirementsScreen> createState() =>
      _ViewingRequirementsScreenState();
}

class _ViewingRequirementsScreenState extends State<ViewingRequirementsScreen> {
  late ContentRestrictions _draft;
  final _country = TextEditingController();
  final _region = TextEditingController();
  final _city = TextEditingController();
  DateTime? _viewingStartsAt;
  bool _invalidStart = false;
  NetworkLocation get _networkLocation => _draft.locationArea.enabled
      ? const NetworkLocation()
      : NetworkLocation(
          country: _country.text,
          region: _region.text,
          city: _city.text,
        );

  void _updateStart(String value) {
    final text = value.trim();
    try {
      final start = text.isEmpty ? null : apiUtc(text);
      setState(() {
        _viewingStartsAt = start;
        _invalidStart = false;
      });
    } on ApiException {
      setState(() => _invalidStart = true);
    }
  }

  @override
  void initState() {
    super.initState();
    // The immutable input stays unchanged until the caller accepts a saved draft.
    _draft = widget.initialRestrictions;
    _viewingStartsAt = _draft.viewingStartsAt;
    _country.text = _draft.networkLocation.country;
    _region.text = _draft.networkLocation.region;
    _city.text = _draft.networkLocation.city;
  }

  @override
  void dispose() {
    _country.dispose();
    _region.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: const Text('Viewing Requirements'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.senderDraft
                  ? 'Save keeps these settings in this draft. The service does not enforce draft settings for recipients.'
                  : 'Configure the viewing policy for this local demo. These settings '
                        'do not enforce permissions, expiration, or view counts, and do '
                        'not change capture protection.',
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ContentRestrictionsSection(
              restrictions: _draft,
              senderDraft: widget.senderDraft,
              onChanged: (restrictions) {
                if (restrictions.locationArea.enabled &&
                    !_draft.locationArea.enabled) {
                  _country.clear();
                  _region.clear();
                  _city.clear();
                }
                setState(() => _draft = restrictions);
              },
            ),
            if (widget.senderDraft) ...[
              if (!_draft.locationArea.enabled)
                ExpansionTile(
                  title: const Text('Network location (optional)'),
                  initiallyExpanded: _networkLocation.enabled,
                  children: [
                    const Text(
                      'The service checks these restrictions using the recipient’s IP address. Select a precise viewing area to use GPS instead.',
                    ),
                    for (final (label, controller) in [
                      ('Allowed country', _country),
                      ('Allowed region or state', _region),
                      ('Allowed city', _city),
                    ])
                      TextField(
                        controller: controller,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(labelText: label),
                      ),
                    if (!_networkLocation.valid)
                      const Text(
                        'Remove control characters from the location fields.',
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              TextFormField(
                initialValue: _draft.viewingStartsAt?.toUtc().toIso8601String(),
                autocorrect: false,
                onChanged: _updateStart,
                decoration: InputDecoration(
                  labelText: 'Viewing start (optional)',
                  hintText: '2026-12-09T16:00:00Z',
                  helperText:
                      'Include the time zone. Leave blank for no start limit.',
                  helperMaxLines: 2,
                  errorText: _invalidStart
                      ? 'Enter a date and time with a time zone.'
                      : null,
                ),
              ),
            ],
            const SizedBox(height: 28),
            ApertureButton(
              label: 'Save',
              icon: Icons.check_outlined,
              onPressed:
                  _draft.locationArea.valid &&
                      _networkLocation.valid &&
                      !_invalidStart
                  ? () => Navigator.pop(
                      context,
                      _draft.copyWith(
                        viewingStartsAt: _viewingStartsAt,
                        clearViewingStart: _viewingStartsAt == null,
                        networkLocation: _networkLocation,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            ApertureButton(
              label: 'Cancel',
              isSecondary: true,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
