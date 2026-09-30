import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/aperture_button.dart';
import '../widgets/section_header.dart';

class ContentStatusScreen extends StatefulWidget {
  final String contentTitle;
  final String recipientSummary;

  const ContentStatusScreen({
    super.key,
    this.contentTitle = 'Confidential File',
    this.recipientSummary = '1 recipient',
  });

  @override
  State<ContentStatusScreen> createState() => _ContentStatusScreenState();
}

class _ContentStatusScreenState extends State<ContentStatusScreen> {
  bool _accessRevoked = false;

  void _toggleAccess() {
    setState(() {
      _accessRevoked = !_accessRevoked;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _accessRevoked
              ? 'Access has been marked as revoked.'
              : 'Access has been restored.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = _accessRevoked ? 'Revoked' : 'Active';
    final statusColor = _accessRevoked ? AppTheme.danger : AppTheme.success;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: const Text('Content Status'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.folder_outlined,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.contentTitle,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Shared with ${widget.recipientSummary}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(
                        _accessRevoked
                            ? Icons.block_outlined
                            : Icons.check_circle_outline,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Viewing Policy',
              icon: Icons.rule_outlined,
            ),
            const SizedBox(height: 14),
            const _PolicyRow(
              label: 'Expiration',
              value: '48 hours after first open',
              icon: Icons.schedule_outlined,
            ),
            const _PolicyRow(
              label: 'Location',
              value: 'Approved area required',
              icon: Icons.location_on_outlined,
            ),
            const _PolicyRow(
              label: 'Capture',
              value: 'Screenshots blocked when supported',
              icon: Icons.screenshot_monitor_outlined,
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Access Activity',
              icon: Icons.history_outlined,
            ),
            const SizedBox(height: 14),
            const _ActivityItem(
              title: 'Policy created',
              subtitle: 'Content encrypted and ready to share',
            ),
            const _ActivityItem(
              title: 'Recipient pending',
              subtitle: 'Waiting for conditions acceptance',
            ),
            const SizedBox(height: 28),
            ApertureButton(
              label: _accessRevoked ? 'Restore Access' : 'Revoke Access',
              icon: _accessRevoked
                  ? Icons.lock_open_outlined
                  : Icons.block_outlined,
              onPressed: _toggleAccess,
              isSecondary: !_accessRevoked,
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _PolicyRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
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
            Icon(icon, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
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

class _ActivityItem extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ActivityItem({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
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
    );
  }
}
