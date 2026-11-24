import 'package:flutter/material.dart';

import '../services/security_settings.dart';
import '../theme/app_theme.dart';

/// The reason and recovery instructions are always visible. Only supplementary
/// diagnostic details obey the preference. This widget cannot authorize access.
class SecurityNotice extends StatefulWidget {
  const SecurityNotice({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.lock_outline,
    this.details,
    this.urgent = false,
    this.settings,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? details;
  final bool urgent;
  final SecuritySettings? settings;

  @override
  State<SecurityNotice> createState() => _SecurityNoticeState();
}

class _SecurityNoticeState extends State<SecurityNotice> {
  @override
  void initState() {
    super.initState();
    _feedback();
  }

  @override
  void didUpdateWidget(SecurityNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.message != widget.message) {
      _feedback();
    }
  }

  void _feedback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        (widget.settings ?? SecuritySettings.instance).warningFeedback();
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings ?? SecuritySettings.instance,
    builder: (context, _) => Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.urgent
              ? const Color(0xFFFEF2F2)
              : const Color(0xFFFFFBEB),
          border: Border.all(
            color: (widget.urgent ? AppTheme.danger : AppTheme.warning)
                .withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    widget.icon,
                    color: widget.urgent ? AppTheme.danger : AppTheme.warning,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.message,
              style: const TextStyle(height: 1.5, color: AppTheme.textPrimary),
            ),
            if ((widget.settings ?? SecuritySettings.instance)
                    .showWarningDetails &&
                widget.details != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.details!,
                style: const TextStyle(
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
