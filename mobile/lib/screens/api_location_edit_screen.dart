import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../models/location_radius_policy.dart';
import '../services/api_session.dart';
import '../widgets/aperture_button.dart';
import '../widgets/location_area_editor.dart';

/// Existing-content owner action. The unsent sharing preview has no API link.
class ApiLocationEditScreen extends StatefulWidget {
  final ApiSession account;
  final int contentId;
  const ApiLocationEditScreen({
    super.key,
    required this.account,
    required this.contentId,
  });
  @override
  State<ApiLocationEditScreen> createState() => _ApiLocationEditScreenState();
}

class _ApiLocationEditScreenState extends State<ApiLocationEditScreen> {
  late final int _identity;
  late SenderLocationDraft _draft;
  LocationZone? _baselineZone;
  late NetworkLocation _baselineNetworkLocation;
  ModalRoute<dynamic>? _route;
  int _generation = 0, _editorVersion = 0;
  bool _wasCurrent = true,
      _invalidated = false,
      _pending = false,
      _needsRefresh = false;
  String? _notice;
  ApiException? _error;

  List<ApiContent> get _owned => widget.account.items
      .where((item) => item.id == widget.contentId && item.mine)
      .toList();
  LocationZone? get _listedZone =>
      _owned.isEmpty ? null : _owned.first.locationZone;
  NetworkLocation get _listedNetworkLocation =>
      _owned.isEmpty ? const NetworkLocation() : _owned.first.networkLocation;
  bool get _eligible =>
      !_invalidated &&
      widget.account.authenticated &&
      widget.account.identityVersion == _identity &&
      _owned.any((item) => item.status != 'Revoked') &&
      _owned
              .map((item) => (item.locationZone, item.networkLocation))
              .toSet()
              .length ==
          1;
  bool get _busy => _pending || widget.account.pending(widget.contentId);
  bool get _ownerActionUnconfirmed =>
      widget.account.ownerControlUnconfirmed(widget.contentId);
  bool get _areaEditUnconfirmed =>
      widget.account.ownerControl(widget.contentId) ==
      (OwnerControlAction.editViewingArea, OwnerControlPhase.unconfirmed);
  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      _route?.isCurrent == true &&
      _eligible;

  @override
  void initState() {
    super.initState();
    _identity = widget.account.identityVersion;
    _baselineZone = _listedZone;
    _baselineNetworkLocation = _listedNetworkLocation;
    _draft = SenderLocationDraft.forExistingArea(_baselineZone);
    widget.account.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (!_eligible) {
      ++_generation;
      _invalidated = true;
      _pending = false;
      _notice = null;
      _error = null;
    } else if (!_pending &&
        (_listedZone != _baselineZone ||
            _listedNetworkLocation != _baselineNetworkLocation)) {
      _needsRefresh = true;
      _notice = 'The listed area changed. Refresh before editing again.';
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ApiLocationEditScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.account, widget.account) ||
        oldWidget.contentId != widget.contentId) {
      oldWidget.account.removeListener(_accountChanged);
      widget.account.addListener(_accountChanged);
      ++_generation;
      _invalidated = true; // A new account/content needs an independent route.
      _pending = false;
      _notice = null;
      _error = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final current = _route?.isCurrent == true;
    if (_wasCurrent && !current) {
      ++_generation;
      if (_pending) {
        _needsRefresh = true;
        _notice = 'A pending server change may still finish. Refresh to see the listed area.';
      }
      _pending = false;
      _error = null;
    }
    _wasCurrent = current;
  }

  Future<void> _refresh() async {
    if (_busy || !_eligible) return;
    final generation = ++_generation;
    setState(() {
      _pending = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.account.refresh(isCurrent: () => _current(generation));
      if (!_current(generation)) return;
      _baselineZone = _listedZone;
      _baselineNetworkLocation = _listedNetworkLocation;
      _draft = SenderLocationDraft.forExistingArea(_baselineZone);
      ++_editorVersion;
      _needsRefresh = false;
      _notice = 'Listed viewing area refreshed.';
    } on ApiException catch (error) {
      if (_current(generation)) _error = error;
    } finally {
      if (_current(generation)) setState(() => _pending = false);
    }
  }

  Future<void> _save() async {
    final zone = _draft.zone;
    if (_busy ||
        !_eligible ||
        _needsRefresh ||
        _ownerActionUnconfirmed ||
        zone == null) {
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _pending = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.account.setLocation(
        widget.contentId,
        zone,
        isCurrent: () => _current(generation),
      );
      if (!_current(generation)) return;
      _baselineZone = zone;
      _baselineNetworkLocation = const NetworkLocation();
      _notice = 'Viewing area update acknowledged by the server.';
      try {
        await widget.account.refresh(isCurrent: () => _current(generation));
        if (!_current(generation)) return;
        if (_listedZone != zone || _listedNetworkLocation.enabled) {
          _needsRefresh = true;
          _notice = 'The server acknowledged the update, but its listed area differs. Refresh before editing again.';
        } else {
          _notice = 'Viewing area update confirmed in the server listing.';
        }
      } on ApiException catch (_) {
        if (_current(generation)) {
          _needsRefresh = true;
          _notice = 'Viewing area update acknowledged. Status refresh failed; refresh to confirm the current area.';
        }
      }
    } on ApiException catch (error) {
      if (_current(generation)) _error = error;
    } finally {
      if (_current(generation)) setState(() => _pending = false);
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.account.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) ++_generation;
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Edit shared viewing area')),
      body: !_eligible
          ? const Center(
              child: Text(
                'Content unavailable or no longer editable by this account.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  _owned.first.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (_listedNetworkLocation.enabled)
                  Text(
                    'Current network location: ${_listedNetworkLocation.parts.join(', ')}. Saving a precise area replaces it.',
                  ),
                const Text(
                  'Saving replaces the location restriction for every recipient of this shared content. It does not restore revoked access or ended viewing sessions.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'The server currently checks distance only. Location uncertainty and freshness are checked by this mobile app; server enforcement remains outstanding.',
                ),
                const SizedBox(height: 12),
                if (_busy)
                  const LinearProgressIndicator(
                    key: ValueKey('location-edit-pending'),
                  ),
                ExcludeFocus(
                  excluding: _busy || _ownerActionUnconfirmed,
                  child: IgnorePointer(
                    ignoring: _busy || _ownerActionUnconfirmed,
                    child: LocationAreaEditor(
                      key: ValueKey(_editorVersion),
                      draft: _draft,
                      serverEdit: true,
                      onChanged: (value) {
                        if (!_busy && !_ownerActionUnconfirmed) {
                          setState(() {
                            _draft = value;
                            _notice = null;
                            _error = null;
                          });
                        }
                      },
                    ),
                  ),
                ),
                if (_notice != null)
                  Text(
                    _notice!,
                    key: const ValueKey('location-edit-confirmation'),
                  ),
                if (_error != null)
                  Text(
                    _error!.message,
                    key: const ValueKey('location-edit-error'),
                  ),
                if (_needsRefresh && !_ownerActionUnconfirmed)
                  const Text(
                    'The server outcome may differ from this draft. Refresh before another save.',
                  ),
                if (_ownerActionUnconfirmed)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _areaEditUnconfirmed
                          ? 'The viewing-area update’s server outcome is unknown. Refresh shows the listed area. Authoritative reconciliation is required before saving again.'
                          : 'An owner action is unconfirmed. Reconcile it before saving a viewing area.',
                    ),
                  ),
                const SizedBox(height: 16),
                ApertureButton(
                  label: 'Save viewing area',
                  onPressed:
                      _busy ||
                          _needsRefresh ||
                          _ownerActionUnconfirmed ||
                          _draft.zone == null
                      ? null
                      : _save,
                ),
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Refresh listed area'),
                ),
                const Text(
                  'Leaving during a request cannot undo a server change. Refresh to see the listed area. A listing cannot settle an unconfirmed update.',
                ),
              ],
            ),
    ),
  );
}
