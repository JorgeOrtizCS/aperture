import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ApertureButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isSecondary;

  const ApertureButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isSecondary ? Colors.white : AppTheme.primary;
    final foregroundColor = isSecondary ? AppTheme.primary : Colors.white;

    final style = ElevatedButton.styleFrom(
      minimumSize: const Size(0, 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      elevation: 0,
      side: isSecondary ? const BorderSide(color: AppTheme.inputBorder) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    final child = Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );

    return SizedBox(
      width: double.infinity,
      child: icon == null
          ? ElevatedButton(onPressed: onPressed, style: style, child: child)
          : ElevatedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon),
              label: child,
            ),
    );
  }
}
