import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../models/content_create_request.dart';
import '../services/api_service.dart';
import '../services/api_session.dart';
import '../services/share_file_selection.dart';
import '../services/share_upload_draft.dart';
import '../theme/app_theme.dart';
import '../widgets/api_scope.dart';
import '../widgets/aperture_button.dart';
import '../widgets/aperture_text_field.dart';
import '../widgets/content_restrictions_section.dart';
import '../widgets/content_restrictions_summary.dart';
import '../widgets/png_document_view.dart';
import '../widgets/section_header.dart';
import 'viewing_requirements_screen.dart';

class ShareContentScreen extends StatefulWidget {
  final ShareFilePicker filePicker;
  final int? maxBytes;
  const ShareContentScreen({
    super.key,
    this.filePicker = const NativeShareFilePicker(),
    this.maxBytes,
  });

  @override
  State<ShareContentScreen> createState() => _ShareContentScreenState();
}

class _ShareContentScreenState extends State<ShareContentScreen>
    with WidgetsBindingObserver {
  static int _sequence = 0;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();

  ContentRestrictions _restrictions = ContentRestrictions.demoDefaults;
  PngDraftPreview? _preview;
  Object? _previewRequest;
  Future<void>? _previewWork;
  ui.Image? _enlargedImage;
  String? _previewError;
  ModalRoute<dynamic>? _route;
  int? _request;
  bool _reading = false;
  Completer<void>? _foregroundWait;
  late AppLifecycleState _lifecycle;
  late final int _maxBytes;
  String? _notice;
  PngFileProblem? _problem;
  ApiSession? _account;
  int? _identity;
  ApiRequestCancellation? _upload;
  String? _uploadNotice;

  bool get _draftLocked => _upload != null || _account?.uploadPending == true;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _lifecycle = binding.lifecycleState ?? AppLifecycleState.resumed;
    _maxBytes = widget.maxBytes == null
        ? PngFileValidator.boundedLimit()
        : PngFileValidator.boundedLimit(widget.maxBytes!);
    binding.addObserver(this);
  }

  bool _current(int id) => mounted && _request == id;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route?.isCurrent == false) _clearEnlargement();
    final account = ApiScope.maybeOf(context);
    if (account != _account || account?.identityVersion != _identity) {
      _leaveDraft();
      _account = account;
      _identity = account?.identityVersion;
    }
  }

  void _discard(int id) {
    unawaited(widget.filePicker.discard(id).catchError((Object _) {}));
  }

  void _clearSelection() {
    final request = _request;
    _request = null;
    _reading = false;
    _foregroundWait?.complete();
    _foregroundWait = null;
    _clearEnlargement();
    _preview?.dispose();
    _preview = null;
    _problem = null;
    _notice = null;
    if (request != null) _discard(request);
  }

  void _leaveDraft() {
    _upload?.cancel();
    _upload = null;
    _uploadNotice = null;
    _clearSelection();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      _foregroundWait?.complete();
      _foregroundWait = null;
      return;
    }
    // Android's document picker pauses Flutter. While the picker is open,
    // only an opaque native selection can exist; reading must wait for resume.
    if (_preview != null ||
        _reading ||
        _upload != null ||
        state == AppLifecycleState.detached) {
      setState(() {
        _leaveDraft();
        _notice = 'File selection cleared while the app was inactive.';
      });
    }
  }

  Future<void> _chooseFile() async {
    if (_request != null ||
        _draftLocked ||
        _lifecycle != AppLifecycleState.resumed) {
      return;
    }
    final id = ++_sequence;
    final account = _account;
    final stageForUpload =
        account != null &&
        account.authenticated &&
        account.api.canCreateContent &&
        !account.uploadNeedsReconciliation;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _clearSelection();
      _uploadNotice = null;
      _request = id;
    });
    try {
      final selected = await widget.filePicker.pick(id);
      if (!_current(id)) return;
      if (!selected) {
        setState(() => _notice = 'No file selected.');
        return;
      }
      if (_lifecycle != AppLifecycleState.resumed) {
        await (_foregroundWait ??= Completer<void>()).future;
        if (!_current(id) || _lifecycle != AppLifecycleState.resumed) return;
      }
      setState(() => _reading = true);
      final file = await widget.filePicker
          .read(id, _maxBytes)
          .then((file) {
            if (!_current(id) || _lifecycle != AppLifecycleState.resumed) {
              file.clear();
            }
            return file;
          })
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw const PngFileException(PngFileProblem.unreadable),
          );
      if (!_current(id) || _lifecycle != AppLifecycleState.resumed) {
        file.clear();
        return;
      }
      final preview = await PngFileValidator.validate(
        file,
        maxBytes: _maxBytes,
        stageForUpload: stageForUpload,
        retainForEnlargement: true,
      );
      if (!_current(id) || _lifecycle != AppLifecycleState.resumed) {
        preview.dispose();
        return;
      }
      setState(() => _preview = preview);
    } on PngFileException catch (error) {
      if (_current(id)) setState(() => _problem = error.problem);
    } catch (_) {
      if (_current(id)) setState(() => _problem = PngFileProblem.unreadable);
    } finally {
      if (_current(id)) {
        setState(() {
          _request = null;
          _reading = false;
        });
        _discard(id);
      }
    }
  }

  Future<void> _submitUpload(ApiSession account) async {
    final user = account.user;
    if (!identical(account, _account) ||
        !account.api.canCreateContent ||
        user == null ||
        account.uploadNeedsReconciliation ||
        _draftLocked ||
        _request != null ||
        _previewRequest != null ||
        _route?.isCurrent == false ||
        _lifecycle != AppLifecycleState.resumed) {
      return;
    }
    final ContentCreateRequest request;
    try {
      request = buildShareUploadDraft(
        title: _titleController.text,
        recipient: _recipientController.text,
        sender: user.username,
        restrictions: _restrictions,
        now: account.now(),
      );
    } on ContentDraftException catch (e) {
      setState(() => _uploadNotice = 'Submission was not sent. ${e.message}');
      return;
    }
    final png = _preview?.takeUploadBytes();
    if (png == null) {
      setState(() {
        _uploadNotice =
            'Submission was not sent. Select a PNG before submitting.';
      });
      return;
    }
    final cancellation = ApiRequestCancellation();
    final identity = account.identityVersion;
    bool current() =>
        mounted &&
        identical(_upload, cancellation) &&
        identical(_account, account) &&
        account.identityVersion == identity;
    setState(() {
      _upload = cancellation;
      _uploadNotice = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final id = await account.createContent(
        request,
        png,
        maxBytes: _maxBytes,
        cancellation: cancellation,
      );
      if (current() && !cancellation.isCancelled) {
        setState(
          () => _uploadNotice = 'Test fixture acknowledged content #$id.',
        );
      }
    } on ApiException catch (e) {
      // The account-level reconciliation state takes precedence over the
      // transport message, including when the user cancels after dispatch.
      if (current() && !account.uploadNeedsReconciliation) {
        setState(() {
          _uploadNotice = switch (e.kind) {
            ApiFailure.cancelled => 'Submission cancelled before dispatch.',
            ApiFailure.invalidRequest =>
              'Test fixture rejected the submission before writing.',
            ApiFailure.denied =>
              'Test fixture denied the submission before writing.',
            _ => e.message,
          };
        });
      }
    } on ContentDraftException catch (e) {
      if (current()) {
        setState(() => _uploadNotice = 'Submission was not sent. ${e.message}');
      }
    } finally {
      if (current()) {
        setState(() {
          _upload = null;
          _clearSelection();
        });
      }
    }
  }

  String get _sizeLimit => _maxBytes == PngFileValidator.backendMaxBytes
      ? '5 MiB'
      : '$_maxBytes bytes';

  String? get _status => switch (_problem) {
    PngFileProblem.unavailable => 'The system file picker is unavailable.',
    PngFileProblem.busy =>
      'The system file picker is still closing. Try again.',
    PngFileProblem.unreadable => 'Could not read this file. Try another PNG.',
    PngFileProblem.unsupported => 'Choose a static PNG file (.png).',
    PngFileProblem.empty => 'This file is empty. Choose another PNG.',
    PngFileProblem.tooLarge => 'This file exceeds the $_sizeLimit limit.',
    PngFileProblem.malformed => 'This file is not a complete, valid PNG.',
    PngFileProblem.dimensions =>
      'This image is too large to preview. Choose a smaller PNG.',
    null => _notice,
  };

  Future<void> _configureRequirements() async {
    if (_draftLocked) return;
    final account = _account;
    final identity = account?.identityVersion;
    final selected = await Navigator.push<ContentRestrictions>(
      context,
      MaterialPageRoute(
        builder: (context) => ViewingRequirementsScreen(
          initialRestrictions: _restrictions,
          senderDraft: true,
        ),
      ),
    );
    if (!mounted ||
        selected == null ||
        _draftLocked ||
        !identical(account, _account) ||
        account?.identityVersion != identity) {
      return;
    }
    setState(() => _restrictions = selected);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leaveDraft();
    _titleController.dispose();
    _descriptionController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showPreview = _previewRequest != null;
    return PopScope<Object?>(
      canPop: !showPreview,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          setState(_leaveDraft);
        } else if (showPreview) {
          setState(_clearEnlargement);
        }
      },
      child: showPreview ? _buildEnlargement() : _buildDraft(context),
    );
  }

  void _clearEnlargement() {
    _previewRequest = null;
    _enlargedImage?.dispose();
    _enlargedImage = null;
    _previewError = null;
  }

  void _openEnlargement() {
    final preview = _preview;
    if (preview == null || _previewRequest != null || _draftLocked) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final request = Object();
    setState(() => _previewRequest = request);
    _previewWork = _prepareEnlargement(preview, request, _previewWork);
  }

  Future<void> _prepareEnlargement(
    PngDraftPreview preview,
    Object request,
    Future<void>? previous,
  ) async {
    bool current() =>
        mounted &&
        identical(_previewRequest, request) &&
        _lifecycle == AppLifecycleState.resumed &&
        (_route?.isCurrent ?? true) &&
        _identity == _account?.identityVersion;

    // Paint the loading state. Wait for any cancelled decode to release its
    // native resources before starting another full-resolution decode.
    await WidgetsBinding.instance.endOfFrame;
    await previous;
    if (!current()) return;
    try {
      final image = await preview.decodeEnlarged(isCurrent: current);
      if (!current()) {
        image?.dispose();
        return;
      }
      setState(() => _enlargedImage = image);
    } catch (error) {
      if (!current()) return;
      setState(() {
        _previewError = switch (error) {
          PngFileException(
            problem: PngFileProblem.tooLarge || PngFileProblem.dimensions,
          ) =>
            'This PNG is too large to enlarge. Choose a smaller file.',
          _ => 'Could not enlarge this PNG. Close the preview and try again.',
        };
      });
    }
  }

  Widget _buildEnlargement() {
    final image = _enlargedImage;
    final error = _previewError;
    void close() => setState(_clearEnlargement);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: close),
        title: const Text('Local PNG preview'),
        actions: [
          IconButton(
            tooltip: 'Close preview',
            onPressed: close,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: image != null
            ? PngDocumentView(
                image: image,
                semanticLabel: 'Local preview of selected PNG',
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (error == null) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                      ],
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error ?? 'Preparing full-resolution preview…',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildDraft(BuildContext context) {
    final preview = _preview;
    final status = _status;
    final account = _account;
    final draftLocked = _draftLocked;
    final testUpload = account?.api.canCreateContent == true;
    final uploadMessage = account?.uploadNeedsReconciliation == true
        ? const ApiException(ApiFailure.uploadUnconfirmed).message
        : _uploadNotice;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: const Text('Share Content'),
      ),
      body: SafeArea(
        child: ListView(
          key: const PageStorageKey('share-draft'),
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Prepare a local draft',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a PNG and review its details, recipient username, and viewing policy on this device.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Content',
              icon: Icons.upload_file_outlined,
            ),
            const SizedBox(height: 14),
            ApertureTextField(
              key: const ValueKey('share-title'),
              controller: _titleController,
              label: 'Content Title',
              hintText: 'Example: Project Document',
              icon: Icons.description_outlined,
              readOnly: draftLocked,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            ApertureTextField(
              key: const ValueKey('share-description'),
              controller: _descriptionController,
              label: 'Description (local only)',
              hintText: 'Optional note',
              icon: Icons.notes_outlined,
              readOnly: draftLocked,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            _FileSelectionCard(
              preview: preview,
              sizeLimit: _sizeLimit,
              busyLabel: _request == null
                  ? null
                  : _reading
                  ? 'Validating PNG…'
                  : 'Waiting for file picker…',
              onTap: _request == null && !draftLocked ? _chooseFile : null,
            ),
            if (status != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  status,
                  key: const ValueKey('share-file-status'),
                  style: TextStyle(
                    color: _problem == null
                        ? AppTheme.textSecondary
                        : AppTheme.danger,
                  ),
                ),
              ),
            ],
            if (preview != null) ...[
              const SizedBox(height: 12),
              const Text('Local preview · Not shared'),
              const SizedBox(height: 8),
              Semantics(
                image: true,
                label: 'Local preview of selected PNG',
                child: RawImage(
                  key: const ValueKey('share-png-preview'),
                  image: preview.image,
                  height: 160,
                  fit: BoxFit.contain,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  children: [
                    TextButton(
                      onPressed: draftLocked ? null : _openEnlargement,
                      child: const Text('Enlarge preview'),
                    ),
                    TextButton(
                      onPressed: draftLocked
                          ? null
                          : () {
                              if (!_draftLocked) setState(_clearSelection);
                            },
                      child: const Text('Remove file'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            const SectionHeader(title: 'Recipient', icon: Icons.group_outlined),
            const SizedBox(height: 14),
            ApertureTextField(
              key: const ValueKey('share-recipient'),
              controller: _recipientController,
              label: 'Username',
              hintText: 'Enter one recipient username',
              icon: Icons.person_add_alt_outlined,
              readOnly: draftLocked,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 8),
            const Text(
              'Recipient accounts are not verified in this draft.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 28),
            const SectionHeader(
              title: 'Saved draft policy',
              icon: Icons.verified_user_outlined,
            ),
            const SizedBox(height: 14),
            ContentRestrictionsSummary(
              restrictions: _restrictions,
              senderDraft: true,
            ),
            const SizedBox(height: 14),
            ApertureButton(
              label: 'Edit Policy',
              icon: Icons.tune_outlined,
              isSecondary: true,
              onPressed: draftLocked ? null : _configureRequirements,
            ),
            const SizedBox(height: 16),
            Text(
              testUpload ? 'Upload test mode · No file is sent to a server.' : 'Encrypted upload is unavailable. Your draft has not been shared.',
            ),
            if (uploadMessage != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  uploadMessage,
                  key: const ValueKey('share-upload-status'),
                ),
              ),
            if (draftLocked) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(
                semanticsLabel: 'Waiting for fixture acknowledgement',
              ),
              if (_upload != null)
                TextButton(
                  onPressed: _upload!.cancel,
                  child: const Text('Cancel submission'),
                ),
            ],
            const SizedBox(height: 16),
            ApertureButton(
              label: draftLocked ? 'Submitting…' : 'Share Securely',
              icon: Icons.send_outlined,
              onPressed:
                  testUpload &&
                      account!.authenticated &&
                      !account.uploadNeedsReconciliation &&
                      _request == null &&
                      !draftLocked &&
                      preview?.hasUploadBytes == true
                  ? () => _submitUpload(account)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FileSelectionCard extends StatelessWidget {
  final PngDraftPreview? preview;
  final String sizeLimit;
  final String? busyLabel;
  final VoidCallback? onTap;

  const _FileSelectionCard({
    required this.preview,
    required this.sizeLimit,
    required this.busyLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final file = preview;
    final selected = file != null;
    return InkWell(
      key: const ValueKey('share-select-png'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? Icons.insert_drive_file : Icons.upload_file_outlined,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file?.name ?? 'Select PNG',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    busyLabel ??
                        (file == null
                            ? 'Static PNG · Up to $sizeLimit'
                            : 'Validated PNG · ${file.width} × ${file.height} · ${file.byteCount} bytes\nTap to replace'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (busyLabel != null)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                selected ? Icons.check_circle_outline : Icons.chevron_right,
                color: selected ? AppTheme.success : AppTheme.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
