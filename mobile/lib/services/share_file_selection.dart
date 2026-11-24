import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../models/content_create_request.dart';
import 'static_png_decoder.dart';

export 'static_png_decoder.dart' show PngFileException, PngFileProblem;

/// Transient owned bytes from the selected document. Never retain the source
/// path or URI in Dart, and clear this buffer even when validation is abandoned.
class PickedShareFile {
  final String name;
  final String? mimeType;
  final Uint8List bytes;
  PickedShareFile(this.name, this.bytes, {this.mimeType});

  void clear() => bytes.fillRange(0, bytes.length, 0);
}

abstract interface class ShareFilePicker {
  /// Presents the system picker. The opaque selection stays native until read.
  Future<bool> pick(int requestId);
  Future<PickedShareFile> read(int requestId, int maxBytes);
  Future<void> discard(int requestId);
}

class NativeShareFilePicker implements ShareFilePicker {
  static const channel = MethodChannel('aperture/share_file_picker');
  const NativeShareFilePicker();

  Future<T?> _invoke<T>(String method, Map<String, Object> args) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      throw const PngFileException(PngFileProblem.unavailable);
    } on PlatformException catch (error) {
      // Never surface platform messages, which can contain provider paths.
      throw PngFileException(switch (error.code) {
        'unavailable' => PngFileProblem.unavailable,
        'busy' => PngFileProblem.busy,
        'unsupported' => PngFileProblem.unsupported,
        'empty' => PngFileProblem.empty,
        'too_large' => PngFileProblem.tooLarge,
        _ => PngFileProblem.unreadable,
      });
    }
  }

  @override
  Future<bool> pick(int requestId) async =>
      await _invoke<bool>('pick', {'id': requestId}) ?? false;

  @override
  Future<PickedShareFile> read(int requestId, int maxBytes) async {
    final result = await _invoke<Map<Object?, Object?>>('read', {
      'id': requestId,
      'maxBytes': maxBytes,
    });
    final name = result?['name'];
    final mimeType = result?['mimeType'];
    final bytes = result?['bytes'];
    if (name is! String ||
        bytes is! Uint8List ||
        (mimeType != null && mimeType is! String)) {
      throw const PngFileException(PngFileProblem.unreadable);
    }
    if (bytes.length > PngFileValidator.boundedLimit(maxBytes)) {
      throw const PngFileException(PngFileProblem.tooLarge);
    }
    // Engine platform messages are read-only. Take ownership of a writable
    // bounded copy so cleanup never attempts to change the engine envelope.
    return PickedShareFile(
      name,
      Uint8List.fromList(bytes),
      mimeType: mimeType as String?,
    );
  }

  @override
  Future<void> discard(int requestId) async {
    await _invoke<void>('discard', {'id': requestId});
  }
}

/// Owns the thumbnail and, when requested, a single bounded PNG source buffer.
/// The caller owns any full-resolution image returned by [decodeEnlarged].
class PngDraftPreview {
  final String name;
  final int byteCount, width, height;
  final ui.Image image;
  Uint8List? _source;
  final bool _stageForUpload;
  PngDraftPreview._(
    this.name,
    this.byteCount,
    this.width,
    this.height,
    this.image,
    this._source,
    this._stageForUpload,
  );

  bool get hasUploadBytes => _stageForUpload && _source != null;

  Future<ui.Image?> decodeEnlarged({required bool Function() isCurrent}) async {
    final source = _source;
    if (source == null) {
      throw const PngFileException(PngFileProblem.unreadable);
    }
    final decoded = await StaticPngDecoder.decode(
      source,
      maxBytes: PngFileValidator.boundedLimit(byteCount),
      clearEncodedBytes: false,
      isCurrent: () => identical(_source, source) && isCurrent(),
    );
    return decoded?.image;
  }

  /// Transfers ownership once. The submit path must wipe the returned buffer.
  Uint8List? takeUploadBytes() {
    if (!_stageForUpload) return null;
    final bytes = _source;
    _source = null;
    return bytes;
  }

  void dispose() {
    final bytes = _source;
    _source = null;
    bytes?.fillRange(0, bytes.length, 0);
    image.dispose();
  }
}

class PngFileValidator {
  static const backendMaxBytes = ContentCreateRequest.maxPngBytes;
  static const _previewSide = 512;

  static int boundedLimit([
    int bytes = const int.fromEnvironment(
      'APERTURE_PNG_MAX_BYTES',
      defaultValue: backendMaxBytes,
    ),
  ]) => bytes <= 0 || bytes > backendMaxBytes ? backendMaxBytes : bytes;

  static Future<PngDraftPreview> validate(
    PickedShareFile file, {
    required int maxBytes,
    bool stageForUpload = false,
    bool retainForEnlargement = false,
  }) async {
    final bytes = file.bytes;
    final keepSource = stageForUpload || retainForEnlargement;
    var retained = false;
    try {
      final name = file.name
          .split(RegExp(r'[/\\]'))
          .last
          .replaceAll(RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'), '')
          .trim();
      final mime = file.mimeType?.trim().toLowerCase();
      if (name.length < 5 ||
          name.length > 255 ||
          !name.toLowerCase().endsWith('.png') ||
          (mime != null &&
              mime.isNotEmpty &&
              !{
                'image/png',
                'image/x-png',
                'application/octet-stream',
              }.contains(mime))) {
        throw const PngFileException(PngFileProblem.unsupported);
      }
      final decoded = (await StaticPngDecoder.decode(
        bytes,
        maxBytes: boundedLimit(maxBytes),
        targetSide: _previewSide,
        clearEncodedBytes: !keepSource,
      ))!;
      final preview = PngDraftPreview._(
        name,
        bytes.length,
        decoded.width,
        decoded.height,
        decoded.image,
        keepSource ? bytes : null,
        stageForUpload,
      );
      retained = keepSource;
      return preview;
    } finally {
      if (!retained) file.clear();
    }
  }
}
