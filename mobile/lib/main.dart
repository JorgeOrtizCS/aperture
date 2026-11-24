import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/debug_camera_trials_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/api_configuration.dart';
import 'services/api_session.dart';
import 'widgets/api_scope.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ApiApplication());
}

/// The normal application always has an API account boundary. Standalone
/// legacy UI previews remain separate from this authenticated entry point.
class ApiApplication extends StatefulWidget {
  final ApiSession? session;
  const ApiApplication({super.key, this.session});

  @override
  State<ApiApplication> createState() => _ApiApplicationState();
}

class _ApiApplicationState extends State<ApiApplication>
    with WidgetsBindingObserver {
  late final ApiSession _session;

  @override
  void initState() {
    super.initState();
    const key = String.fromEnvironment('APERTURE_DEVICE_KEY');
    _session =
        widget.session ??
        ApiSession(configuredApi(), deviceKey: key.isEmpty ? null : key);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _session.expireCredentialsIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ApiScope(
    session: _session,
    child: ListenableBuilder(
      listenable: _session,
      builder: (context, _) => KeyedSubtree(
        key: ValueKey(_session.identityVersion),
        child: const ApertureApp(),
      ),
    ),
  );
}

class ApertureApp extends StatelessWidget {
  const ApertureApp({super.key});

  @override
  Widget build(BuildContext context) {
    final account = ApiScope.maybeOf(context);
    final httpWarning = account?.api.usesClassroomHttp == true
        ? 'Insecure HTTP — Classroom Test'
        : account?.api.usesSchoolDemoHttp == true
        ? 'School demo · Insecure HTTP'
        : null;
    return MaterialApp(
      title: 'Aperture',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      builder: httpWarning != null
          ? (context, child) => Column(
              // Paint above the navigator so its route semantics do not hide
              // the warning from assistive technology.
              verticalDirection: VerticalDirection.up,
              children: [
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: child!,
                  ),
                ),
                Material(
                  color: const Color(0xFFFFE8B3),
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          httpWarning,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: const Color(0xFF4F3200)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      home:
          kDebugMode &&
              const bool.fromEnvironment('APERTURE_CAMERA_DIAGNOSTICS')
          ? const DebugCameraTrialsScreen()
          : account?.authenticated == true
          ? const DashboardScreen()
          : const WelcomeScreen(),
    );
  }
}
