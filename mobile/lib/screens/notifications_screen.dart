import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: const Text('Notifications'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            SectionHeader(
              title: 'Recent Alerts',
              icon: Icons.notifications_outlined,
            ),
            SizedBox(height: 14),
            _NotificationItem(
              title: 'Access granted',
              subtitle: 'Project Document is available to view.',
              icon: Icons.check_circle_outline,
              color: AppTheme.success,
            ),
            _NotificationItem(
              title: 'Condition required',
              subtitle:
                  'Private Image requires approved location before viewing.',
              icon: Icons.location_on_outlined,
              color: AppTheme.warning,
            ),
            _NotificationItem(
              title: 'Policy update',
              subtitle: 'Confidential File viewing window expires in 48 hours.',
              icon: Icons.schedule_outlined,
              color: AppTheme.primary,
            ),
            _NotificationItem(
              title: 'Capture protection',
              subtitle: 'Screenshot monitoring is enabled for Secure Photo.',
              icon: Icons.screenshot_monitor_outlined,
              color: AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _NotificationItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
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
