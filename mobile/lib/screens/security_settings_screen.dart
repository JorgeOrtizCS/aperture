import 'package:flutter/material.dart';

import '../services/security_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/restriction_tile.dart';
import '../widgets/section_header.dart';

class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key, this.settings});
  final SecuritySettings? settings;

  @override
  Widget build(BuildContext context) {
    final preferences = settings ?? SecuritySettings.instance;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: const Text('Security Settings'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: preferences,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SectionHeader(
                title: 'Presentation preferences',
                icon: Icons.tune_outlined,
              ),
              const SizedBox(height: 12),
              const Text(
                'These preferences change alerts only. They cannot grant access or change the sender’s requirements. Changes apply immediately for this app run and reset when the app restarts.',
              ),
              const SizedBox(height: 16),
              RestrictionTile(
                title: 'Warning haptics',
                subtitle: 'Optional vibration when a new security warning appears. Device support varies.',
                icon: Icons.vibration,
                enabled: preferences.warningHaptics,
                onChanged: preferences.setWarningHaptics,
              ),
              const SizedBox(height: 12),
              RestrictionTile(
                title: 'Show warning details',
                subtitle: 'Show supplementary camera metrics and diagnostic details. Warning reasons and recovery instructions always remain visible.',
                icon: Icons.info_outline,
                enabled: preferences.showWarningDetails,
                onChanged: preferences.setShowWarningDetails,
              ),
              const SizedBox(height: 28),
              const SectionHeader(
                title: 'Mandatory protections',
                icon: Icons.shield_outlined,
              ),
              const SizedBox(height: 12),
              const _Protection(
                title: 'Sender requirements',
                description: 'Required authorization and viewing conditions must pass. Recipient preferences cannot relax them.',
              ),
              const _Protection(
                title: 'Capture protection',
                description: 'Native capture defenses remain required. On iOS, screenshot detection is reactive: the first screenshot may already be saved.',
              ),
              const _Protection(
                title: 'Phone-detection session lockout',
                description: 'A detected phone permanently ends the current viewing session. Removing it or rechecking cannot restore that session.',
              ),
              const _Protection(
                title: 'Biometric identity verification',
                description: 'Biometric-only verification is required for each viewing session and is revoked on backgrounding or session end. It cannot replace sender authorization or be disabled here.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Protection extends StatelessWidget {
  const _Protection({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Text(description, style: const TextStyle(height: 1.5)),
        ],
      ),
    ),
  );
}
