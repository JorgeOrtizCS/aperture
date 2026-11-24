import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Presentation preferences only. Never consulted by any access-control gate.
/// Kept in memory for this app run; no new storage dependency is required.
class SecuritySettings extends ChangeNotifier {
  static final instance = SecuritySettings();

  bool _warningHaptics = false;
  bool _showWarningDetails = true;

  bool get warningHaptics => _warningHaptics;
  bool get showWarningDetails => _showWarningDetails;

  void setWarningHaptics(bool value) {
    if (_warningHaptics == value) return;
    _warningHaptics = value;
    notifyListeners();
  }

  void setShowWarningDetails(bool value) {
    if (_showWarningDetails == value) return;
    _showWarningDetails = value;
    notifyListeners();
  }

  Future<void> warningFeedback() async {
    if (!_warningHaptics) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Optional feedback failure must never affect warning text or enforcement.
    }
  }
}
