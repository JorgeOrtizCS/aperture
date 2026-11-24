import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../services/api_session.dart';
import '../widgets/api_scope.dart';
import '../theme/app_theme.dart';
import '../widgets/aperture_button.dart';
import '../widgets/aperture_text_field.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  String? _errorMessage;
  bool _pending = false;
  String? _probeResult;

  Future<void> _checkApi(ApiSession account) async {
    setState(() {
      _pending = true;
      _probeResult = null;
    });
    String result;
    try {
      await account.api.checkAnonymousAccess();
      result = 'The API returned the expected anonymous 401 response.';
    } on ApiException catch (e) {
      result = e.kind == ApiFailure.notFound
          ? 'The configured API route was not found.'
          : e.message;
    }
    if (!mounted) return;
    setState(() {
      _pending = false;
      _probeResult = result;
    });
  }

  Future<void> _handleLogin() async {
    if (_pending) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your username and password.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    final account = ApiScope.maybeOf(context);
    if (account != null) {
      setState(() => _pending = true);
      try {
        await account.login(username, password);
        // ApiApplication replaces the entire navigator after verified login.
      } on ApiException catch (e) {
        if (mounted && e.kind != ApiFailure.stale) {
          setState(() => _errorMessage = e.message);
        }
      } finally {
        if (mounted) {
          _passwordController.clear();
          setState(() => _pending = false);
        }
      }
      return;
    }
    // Explicit standalone debug preview only; never a fallback from an API
    // failure. The normal main() entry always supplies an account scope.
    if (!kDebugMode) {
      setState(
        () =>
            _errorMessage = const ApiException(ApiFailure.configuration)
                .message,
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ApiScope.maybeOf(context);
    if (account != null && account.api.anonymousOnly) {
      return Scaffold(
        appBar: AppBar(title: const Text('School demo API')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                const ApiException(ApiFailure.httpDemoAnonymousOnly).message,
              ),
              const SizedBox(height: 12),
              const Text(
                'The API may record this anonymous check in its audit log.',
              ),
              const SizedBox(height: 16),
              ApertureButton(
                label: _pending ? 'Checking…' : 'Check API anonymously',
                onPressed: _pending ? null : () => _checkApi(account),
              ),
              if (_probeResult != null)
                Semantics(liveRegion: true, child: Text(_probeResult!)),
            ],
          ),
        ),
      );
    }
    return PopScope<Object?>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _pending) account?.cancelLogin();
      },
      child: _buildForm(context, account),
    );
  }

  Widget _buildForm(BuildContext context, ApiSession? account) {
    final classroomHttp = account?.api.usesClassroomHttp == true;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              IconButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: AppTheme.textPrimary,
                ),
              ),

              const SizedBox(height: 40),

              // Aperture icon
              Center(
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F4E79),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              const Center(
                child: Text(
                  'Welcome Back',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              const Center(
                child: Text(
                  'Sign in to continue to Aperture',
                  style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                ),
              ),

              const SizedBox(height: 24),
              Text(
                account == null
                    ? 'Local prototype sign-in. Account authentication is not connected; nonempty values open the sample dashboard.'
                    : account.api.isFixture
                    ? 'Fixture mode. Use fixture-sender or fixture-recipient and any nonempty sample password. No server is contacted.'
                    : classroomHttp
                    ? 'Use only the approved disposable classroom accounts. HTTP sends credentials without encryption.'
                    : account.api.usesSchoolDemoHttp
                    ? 'Use only disposable school-demo accounts on this loopback connection.'
                    : account.api.configured
                    ? 'Sign in to the configured API. Device biometrics and viewing conditions are checked separately.'
                    : 'No approved API environment is configured. Account sign-in is unavailable.',
              ),
              if (account?.logoutWarning case final warning?) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    warning,
                    style: const TextStyle(color: AppTheme.warning),
                  ),
                ),
              ],
              const SizedBox(height: 18),

              ApertureTextField(
                key: const ValueKey('login-username'),
                controller: _usernameController,
                label: 'Username',
                hintText: 'Enter your username',
                icon: Icons.person_outline,
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 22),

              ApertureTextField(
                key: const ValueKey('login-password'),
                controller: _passwordController,
                label: 'Password',
                hintText: 'Enter your password',
                icon: Icons.lock_outline,
                obscureText: _obscurePassword,
                onSubmitted: (_) => _handleLogin(),
                suffixIcon: classroomHttp
                    ? null
                    : IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          semanticLabel: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ],

              const SizedBox(height: 30),

              ApertureButton(
                label: _pending ? 'Signing in…' : 'Sign In',
                onPressed: _pending ? null : _handleLogin,
              ),

              const SizedBox(height: 24),

              const Center(
                child: Text(
                  'Your content. Your conditions. Your control.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
