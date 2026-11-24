import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/api_session.dart';
import '../widgets/aperture_button.dart';

class ApiTimeEditScreen extends StatefulWidget {
  final ApiSession account;
  final int contentId;

  const ApiTimeEditScreen({
    super.key,
    required this.account,
    required this.contentId,
  });

  @override
  State<ApiTimeEditScreen> createState() => _ApiTimeEditScreenState();
}

class _ApiTimeEditScreenState extends State<ApiTimeEditScreen> {
  late final ApiSession _account = widget.account;
  late final int _id = widget.contentId;
  late final int _identity;
  final _start = TextEditingController();
  final _expiry = TextEditingController();
  ModalRoute<dynamic>? _route;
  int _generation = 0;
  bool _busy = false;
  ApiTimeWindow? _observed;
  String? _notice;

  bool get _eligible =>
      identical(_account, widget.account) &&
      _id == widget.contentId &&
      _account.authenticated &&
      _account.identityVersion == _identity &&
      _account.items.any(
        (item) => item.id == _id && item.mine && item.status != 'Revoked',
      );
  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      _route?.isCurrent == true &&
      _eligible;

  @override
  void initState() {
    super.initState();
    final generation = _generation;
    _identity = widget.account.identityVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(generation)) {
        _refresh();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route?.isCurrent != true) {
      ++_generation;
      _busy = false;
      _observed = null;
      _notice = null;
    }
  }

  DateTime? _parse(String value) =>
      value.trim().isEmpty ? null : apiUtc(value.trim());

  (ApiTimeWindow?, String?) _draft() {
    try {
      final start = _parse(_start.text);
      final expiry = _parse(_expiry.text);
      if (expiry != null &&
          (!expiry.isAfter(_account.now().toUtc()) ||
              (start != null && !expiry.isAfter(start)))) {
        return (null, 'Expiration must be in the future and after the start.');
      }
      return ((startTime: start, expiresAt: expiry), null);
    } on ApiException {
      return (null, 'Enter each date and time with a time zone.');
    }
  }

  void _populate(ApiTimeWindow window) {
    _observed = window;
    _start.text = window.startTime?.toIso8601String() ?? '';
    _expiry.text = window.expiresAt?.toIso8601String() ?? '';
  }

  Future<void> _refresh() async {
    if (_busy || !_current(_generation)) return;
    final generation = ++_generation;
    bool current() => _current(generation);
    setState(() {
      _busy = true;
      _observed = null;
      _notice = null;
    });
    try {
      final window = await _account.timeWindow(_id, isCurrent: current);
      if (current()) _populate(window);
    } on ApiException catch (error) {
      if (current()) {
        _notice = 'Viewing time could not be read. ${error.message}';
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  Future<void> _save(ApiTimeWindow window) async {
    final (draft, _) = _draft();
    if (_busy ||
        !_current(_generation) ||
        _observed == null ||
        window == _observed ||
        draft != window ||
        _account.pending(_id) ||
        _account.ownerControlUnconfirmed(_id)) {
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    bool current() => _current(generation);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await _account.setTimeWindow(_id, window, isCurrent: current);
      if (!current()) return;
      _observed = null;
      try {
        final saved = await _account.timeWindow(_id, isCurrent: current);
        if (!current()) return;
        if (saved == window) {
          _populate(saved);
          _notice = 'Viewing time confirmed by the server.';
        } else {
          _notice = 'The server acknowledged the update, but returned a different window. Refresh before saving again.';
        }
      } on ApiException {
        if (!current()) return;
        _notice = 'Viewing time update acknowledged. Refresh to check the current window.';
      }
      try {
        await _account.refresh(isCurrent: current);
      } on ApiException {
        // The dedicated time endpoint has its own read-back result.
      }
    } on ApiException catch (error) {
      if (current()) _notice = error.message;
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _expiry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) ++_generation;
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Edit shared viewing time')),
      body: ListenableBuilder(
        listenable: widget.account,
        builder: (context, _) {
          if (!_eligible) {
            return const Center(
              child: Text(
                'Content unavailable or no longer editable by this account.',
              ),
            );
          }
          final pending = _account.pending(_id);
          final unconfirmed = _account.ownerControlUnconfirmed(_id);
          final editable =
              _observed != null && !_busy && !pending && !unconfirmed;
          final (draft, validation) = editable ? _draft() : (null, null);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Both limits apply to every recipient. Leave a field blank to remove that limit. Changes do not restore revoked access or ended sessions.',
              ),
              const SizedBox(height: 12),
              const Text('Use a time zone, for example 2026-12-09T16:00:00Z.'),
              if (_busy || pending) const LinearProgressIndicator(),
              TextField(
                controller: _start,
                enabled: editable,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Viewing start'),
                onChanged: (_) => setState(() => _notice = null),
              ),
              TextField(
                controller: _expiry,
                enabled: editable,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Viewing expiration',
                ),
                onChanged: (_) => setState(() => _notice = null),
              ),
              if (validation != null) Text(validation),
              if (_notice != null)
                Semantics(liveRegion: true, child: Text(_notice!)),
              if (unconfirmed)
                Semantics(
                  liveRegion: true,
                  child: const Text(
                    'An owner change remains unconfirmed. Refresh shows the current window. Authoritative reconciliation is required before another change.',
                  ),
                ),
              const SizedBox(height: 16),
              ApertureButton(
                label: 'Save viewing time',
                onPressed: draft != null && draft != _observed
                    ? () => _save(draft)
                    : null,
              ),
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Refresh viewing time'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
