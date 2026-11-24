import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api_session.dart';
import '../widgets/aperture_button.dart';

class RegisterAccountScreen extends StatefulWidget {
  final ApiSession account;
  const RegisterAccountScreen({super.key, required this.account});

  @override
  State<RegisterAccountScreen> createState() => _RegisterAccountScreenState();
}

class _RegisterAccountScreenState extends State<RegisterAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _notice;

  Future<void> _submit() async {
    final account = widget.account;
    final route = ModalRoute.of(context);
    if (account.registeringAccount ||
        route?.isCurrent != true ||
        !_form.currentState!.validate()) {
      return;
    }
    final username = _username.text.trim();
    FocusScope.of(context).unfocus();
    setState(() => _notice = null);
    try {
      await account.registerAccount(
        firstName: _firstName.text,
        lastName: _lastName.text,
        username: username,
        password: _password.text,
      );
      if (mounted && route?.isCurrent == true) Navigator.pop(context, username);
    } on ApiException catch (error) {
      if (!mounted || route?.isCurrent != true) return;
      setState(() {
        _notice = switch (error.kind) {
          ApiFailure.timeout ||
          ApiFailure.network ||
          ApiFailure.server ||
          ApiFailure.malformed => 'Account creation could not be confirmed. Try signing in with the username you entered before submitting again.',
          _ => error.message,
        };
      });
    } finally {
      if (mounted) _password.clear();
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create an account')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.account,
        builder: (context, _) {
          final pending = widget.account.registeringAccount;
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final (label, controller) in [
                  ('First name', _firstName),
                  ('Last name', _lastName),
                  ('Username', _username),
                ]) ...[
                  TextFormField(
                    controller: controller,
                    readOnly: pending,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: label),
                    validator: (value) {
                      final length = value?.trim().length ?? 0;
                      return length == 0 || length > 100
                          ? 'Enter 1 to 100 characters.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _password,
                  readOnly: pending,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty || value.length < 8
                      ? 'Enter a password with at least 8 characters.'
                      : null,
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(_notice!)),
                ],
                const SizedBox(height: 20),
                ApertureButton(
                  label: pending ? 'Creating account…' : 'Create account',
                  onPressed: pending ? null : _submit,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
