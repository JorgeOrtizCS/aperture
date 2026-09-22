import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/aperture_button.dart';
import '../widgets/aperture_text_field.dart';
import '../widgets/content_restrictions_section.dart';
import '../widgets/section_header.dart';
import 'content_status_screen.dart';

class ShareContentScreen extends StatefulWidget {
  const ShareContentScreen({super.key});

  @override
  State<ShareContentScreen> createState() => _ShareContentScreenState();
}

class _ShareContentScreenState extends State<ShareContentScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();

  bool _contentSelected = false;
  ContentRestrictions _restrictions = const ContentRestrictions(
    allowDownload: false,
    allowResharing: false,
    restrictScreenshots: true,
    accessDuration: AccessDuration.twoDays,
    viewLimit: 3,
  );

  void _shareContent() {
    final title = _titleController.text.trim();
    final recipient = _recipientController.text.trim();

    if (!_contentSelected || title.isEmpty || recipient.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select content, enter a title, and add a recipient.'),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ContentStatusScreen(
          contentTitle: title,
          recipientSummary: recipient,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _recipientController.dispose();
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
        title: const Text('Share Content'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Upload and configure',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Set up the content details, recipients, and viewing restrictions before sharing.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Content',
              icon: Icons.upload_file_outlined,
            ),
            const SizedBox(height: 14),
            ApertureTextField(
              controller: _titleController,
              label: 'Content Title',
              hintText: 'Example: Project Document',
              icon: Icons.description_outlined,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            ApertureTextField(
              controller: _descriptionController,
              label: 'Description',
              hintText: 'Optional note for the recipient',
              icon: Icons.notes_outlined,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            _FileSelectionCard(
              selected: _contentSelected,
              onTap: () {
                setState(() {
                  _contentSelected = true;
                  if (_titleController.text.trim().isEmpty) {
                    _titleController.text = 'Project Document.pdf';
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'The file picker and encrypted upload service are not connected yet; this selection uses sample UI state.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Recipients',
              icon: Icons.group_outlined,
            ),
            const SizedBox(height: 14),
            ApertureTextField(
              controller: _recipientController,
              label: 'Recipient',
              hintText: 'Enter username or email',
              icon: Icons.person_add_alt_outlined,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Viewing Restrictions',
              icon: Icons.verified_user_outlined,
            ),
            const SizedBox(height: 14),
            ContentRestrictionsSection(
              restrictions: _restrictions,
              onChanged: (restrictions) {
                setState(() => _restrictions = restrictions);
              },
            ),
            const SizedBox(height: 28),
            ApertureButton(
              label: 'Share Securely',
              icon: Icons.send_outlined,
              onPressed: _shareContent,
            ),
          ],
        ),
      ),
    );
  }
}

class _FileSelectionCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _FileSelectionCard({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? Icons.insert_drive_file : Icons.upload_file_outlined,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected ? 'Project Document.pdf' : 'Select content',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selected
                        ? 'PDF selected for secure sharing'
                        : 'Tap to choose a file or media item',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_outline : Icons.chevron_right,
              color: selected ? AppTheme.success : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
