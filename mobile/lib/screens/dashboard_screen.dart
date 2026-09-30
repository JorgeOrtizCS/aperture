import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/aperture_button.dart';
import '../widgets/app_header.dart';
import '../widgets/content_card.dart';
import '../widgets/section_header.dart';
import 'content_status_screen.dart';
import 'notifications_screen.dart';
import 'secure_viewer_screen.dart';
import 'share_content_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          children: [
            AppHeader(
              title: 'Aperture',
              subtitle: 'Secure Content Dashboard',
              actionIcon: Icons.notifications_outlined,
              onActionPressed: () {
                _openScreen(context, const NotificationsScreen());
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'Welcome back!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage the content you share and the content others have securely shared with you.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            ApertureButton(
              label: 'Share New Content',
              icon: Icons.add,
              onPressed: () {
                _openScreen(context, const ShareContentScreen());
              },
            ),
            const SizedBox(height: 34),
            const SectionHeader(
              title: 'Shared With Me',
              icon: Icons.inbox_outlined,
            ),
            const SizedBox(height: 14),
            ContentCard(
              title: 'Project Document',
              subtitle: 'Shared securely with you',
              icon: Icons.description_outlined,
              status: 'Available',
              onTap: () {
                _openScreen(
                  context,
                  const SecureViewerScreen(contentTitle: 'Project Document'),
                );
              },
            ),
            const SizedBox(height: 12),
            ContentCard(
              title: 'Private Image',
              subtitle: 'Viewing conditions required',
              icon: Icons.image_outlined,
              status: 'Restricted',
              onTap: () {
                _openScreen(
                  context,
                  const SecureViewerScreen(contentTitle: 'Private Image'),
                );
              },
            ),
            const SizedBox(height: 34),
            const SectionHeader(
              title: 'My Shared Content',
              icon: Icons.send_outlined,
            ),
            const SizedBox(height: 14),
            ContentCard(
              title: 'Confidential File',
              subtitle: 'Shared with 1 recipient',
              icon: Icons.folder_outlined,
              status: 'Active',
              onTap: () {
                _openScreen(
                  context,
                  const ContentStatusScreen(
                    contentTitle: 'Confidential File',
                    recipientSummary: '1 recipient',
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            ContentCard(
              title: 'Secure Photo',
              subtitle: 'Shared with 2 recipients',
              icon: Icons.photo_outlined,
              status: 'Active',
              onTap: () {
                _openScreen(
                  context,
                  const ContentStatusScreen(
                    contentTitle: 'Secure Photo',
                    recipientSummary: '2 recipients',
                  ),
                );
              },
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
