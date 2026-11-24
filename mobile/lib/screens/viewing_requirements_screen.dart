import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    // The immutable input stays unchanged until the caller accepts a saved draft.
    _draft = widget.initialRestrictions;
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
                setState(() => _draft = restrictions);
              },
            ),
            const SizedBox(height: 28),
            ApertureButton(
              label: 'Save',
              icon: Icons.check_outlined,
              onPressed: _draft.locationArea.valid
                  ? () => Navigator.pop(context, _draft)
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
