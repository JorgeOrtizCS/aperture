import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import 'api_session.dart';

/// Route-scoped registration status. Registration never authorizes viewing.
class DeviceRegistration extends ChangeNotifier {
  final ApiSession account;
  final bool Function() sessionEnded;
  late final int _identity;
  int _generation = 0;
  bool _disposed = false;
  bool pending = false;
  bool? trusted;
  String message = 'Device approval has not been checked.';

  DeviceRegistration(this.account, {required this.sessionEnded}) {
    _identity = account.identityVersion;
    account.addListener(_accountChanged);
  }

  bool get _eligible =>
      !_disposed &&
      !sessionEnded() &&
      account.authenticated &&
      account.identityVersion == _identity;

  bool get deviceKeyConfigured => account.deviceKey?.isNotEmpty == true;
  bool get canRegister => _eligible && deviceKeyConfigured;

  void _accountChanged() {
    if (!_eligible) cancel();
  }

  Future<void> register(String name) async {
    if (!canRegister || pending) return;
    final generation = ++_generation;
    pending = true;
    trusted = null;
    message = 'Registering device. Viewing access remains separately checked.';
    notifyListeners();
    try {
      final result = await account.registerDevice(name);
      if (!_eligible || generation != _generation) return;
      trusted = result;
      message = result
          ? 'The server confirms device approval. Viewing conditions still apply.'
          : 'Device registered, but not approved. Backend approval is required.';
    } on ApiException catch (error) {
      if (!_eligible || generation != _generation) return;
      message = error.message;
    } finally {
      if (!_disposed && generation == _generation) {
        pending = false;
        notifyListeners();
      }
    }
  }

  void cancel() {
    if (_disposed) return;
    ++_generation;
    pending = false;
    trusted = null;
    message = 'Device approval is unconfirmed. A pending server action may still finish.';
    notifyListeners();
  }

  @override
  void dispose() {
    ++_generation;
    _disposed = true;
    trusted = null;
    account.removeListener(_accountChanged);
    super.dispose();
  }
}
