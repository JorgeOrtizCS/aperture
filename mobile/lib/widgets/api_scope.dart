import 'package:flutter/widgets.dart';

import '../services/api_session.dart';

class ApiScope extends InheritedNotifier<ApiSession> {
  const ApiScope({super.key, required ApiSession session, required super.child})
    : super(notifier: session);

  static ApiSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ApiScope>()?.notifier;
}
