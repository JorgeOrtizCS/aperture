import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/static_png_decoder.dart';
import 'png_document_view.dart';

/// The delivery owner transfers exclusive ownership of a writable, dedicated
/// buffer to the renderer. Do not pass a view of a shared or read-only buffer.
final class RecipientPngPayload {
  const RecipientPngPayload({required this.contentType, required this.bytes});

  final String contentType;
  final Uint8List bytes;
}

/// One display attempt. The owner must keep bytes out of the closure and only
/// offer the request after it has confirmed delivery and every viewing gate.
/// This object conveys no proof of authorization. A consumed request is inert.
final class RecipientPngRequest {
  RecipientPngRequest(Future<RecipientPngPayload> Function() load)
    : _load = load;

  Future<RecipientPngPayload> Function()? _load;

  Future<RecipientPngPayload> Function()? _take() {
    final load = _load;
    _load = null;
    return load;
  }
}

/// Renders only transient PNG pixels. There is deliberately no production
/// route, API client, account state or authorization logic in this widget.
///
/// The caller owns the session: set [input] to null on any failed requirement,
/// expiry, logout or route exit, outside build. Cancel delivery/decryption at
/// the source too; an uncancellable late result is wiped when it arrives.
/// Supply a fresh request after rechecking access. Foregrounding or returning
/// to a covered route never replays the previous request.
class RecipientPngRenderer extends StatefulWidget {
  const RecipientPngRenderer({super.key, required this.input});

  final ValueListenable<RecipientPngRequest?> input;

  @override
  State<RecipientPngRenderer> createState() => _RecipientPngRendererState();
}

class _RecipientPngRendererState extends State<RecipientPngRenderer>
    with WidgetsBindingObserver {
  static const _maxBytes = 5 * 1024 * 1024;
  int _generation = 0;
  RecipientPngRequest? _offered;
  ui.Image? _image;
  String? _error;
  bool _loading = false;
  bool _foreground = false;
  ModalRoute<dynamic>? _route;
  bool _leaving = false;

  // Read the route's current state directly: Navigator changes it before
  // the inherited status rebuild reaches this widget.
  bool get _canDisplay =>
      _foreground && !_leaving && (_route?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _foreground = binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    widget.input.addListener(_inputChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (!_canDisplay) _clear();
    _syncInput();
  }

  @override
  void didUpdateWidget(RecipientPngRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.input, widget.input)) {
      oldWidget.input.removeListener(_inputChanged);
      _clear();
      widget.input.addListener(_inputChanged);
      _syncInput();
    }
  }

  void _inputChanged() => setState(_syncInput);

  void _syncInput() {
    final request = widget.input.value;
    if (identical(request, _offered)) return;
    _offered = request;
    _clear();
    if (!_canDisplay) return;
    final load = request?._take();
    if (load == null) return;
    _loading = true;
    unawaited(_render(load, _generation));
  }

  void _clear() {
    ++_generation;
    _image?.dispose();
    _image = null;
    _error = null;
    _loading = false;
  }

  Future<void> _render(
    Future<RecipientPngPayload> Function() load,
    int generation,
  ) async {
    bool current() => mounted && generation == _generation && _canDisplay;
    RecipientPngPayload? payload;
    try {
      // Start delivery outside build, and skip it if already invalidated.
      await Future<void>.value();
      if (!current()) return;
      payload = await load();
      if (!current()) return;
      if (payload.contentType.trim().toLowerCase() != 'image/png') {
        throw const PngFileException(PngFileProblem.unsupported);
      }
      final bytes = payload.bytes;
      payload = null; // The decoder now owns cleanup for this buffer.
      final decoded = await StaticPngDecoder.decode(
        bytes,
        maxBytes: _maxBytes,
        isCurrent: current,
      );
      if (decoded == null) return;
      if (!current()) {
        decoded.image.dispose();
        return;
      }
      setState(() {
        _image = decoded.image;
        _loading = false;
      });
    } catch (error) {
      if (!current()) return;
      // No filenames, transport errors or payload details enter UI or logs.
      setState(() {
        _loading = false;
        _error = switch (error) {
          PngFileException(problem: PngFileProblem.unsupported) =>
            'Only still PNG images are supported.',
          PngFileException(
            problem: PngFileProblem.tooLarge || PngFileProblem.dimensions,
          ) =>
            'This PNG exceeds the supported size.',
          PngFileException() => 'This PNG is invalid or incomplete.',
          _ => 'Unable to load the image.',
        };
      });
    } finally {
      final bytes = payload?.bytes;
      try {
        bytes?.fillRange(0, bytes.length, 0);
      } on UnsupportedError {
        // A caller violated the writable-buffer contract. Do not display or
        // retain the bytes, even when their source made them unwritable.
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) setState(_clear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.input.removeListener(_inputChanged);
    _offered = null;
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) return;
      _leaving = true;
      setState(_clear);
    },
    child: _body(),
  );

  Widget _body() {
    final image = _image;
    if (image != null) {
      return PngDocumentView(image: image, semanticLabel: 'Shared PNG image');
    }
    final message = _loading ? 'Loading image…' : _error;
    if (message == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
