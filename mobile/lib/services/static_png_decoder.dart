import 'dart:typed_data';
import 'dart:ui' as ui;

enum PngFileProblem {
  unavailable,
  busy,
  unreadable,
  unsupported,
  empty,
  tooLarge,
  malformed,
  dimensions,
}

class PngFileException implements Exception {
  final PngFileProblem problem;
  const PngFileException(this.problem);
}

/// Bounded single-frame PNG decoding shared by the sender and recipient.
abstract final class StaticPngDecoder {
  static const _maxSide = 4096;
  static const _maxPixels = 8 * 1024 * 1024;
  static const _signature = [137, 80, 78, 71, 13, 10, 26, 10];
  static const _ihdr = 0x49484452, _idat = 0x49444154, _iend = 0x49454e44;
  static const _animationChunks = {0x6163544c, 0x6663544c, 0x66644154};
  static final _crcTable = List<int>.generate(256, (value) {
    var crc = value;
    for (var bit = 0; bit < 8; ++bit) {
      crc = (crc & 1) == 0 ? crc >>> 1 : (crc >>> 1) ^ 0xedb88320;
    }
    return crc;
  }, growable: false);

  /// Returns an owned image handle, or null if the caller withdrew the request.
  /// [width] and [height] in the result describe the original PNG.
  /// Encoded bytes are wiped by default. A caller that retains them owns cleanup.
  static Future<({ui.Image image, int width, int height})?> decode(
    Uint8List bytes, {
    required int maxBytes,
    int? targetSide,
    bool clearEncodedBytes = true,
    bool Function()? isCurrent,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    bool current() => isCurrent?.call() ?? true;
    void clear() => bytes.fillRange(0, bytes.length, 0);
    try {
      if (!current()) return null;
      if (bytes.isEmpty) throw const PngFileException(PngFileProblem.empty);
      if (bytes.length > maxBytes) {
        throw const PngFileException(PngFileProblem.tooLarge);
      }
      final (width, height) = _verifyChunks(bytes);
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      if (clearEncodedBytes) clear();
      if (!current()) return null;
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!current()) return null;
      if (descriptor.width != width || descriptor.height != height) {
        _malformed();
      }
      final longest = width > height ? width : height;
      final scale = targetSide == null || longest <= targetSide
          ? 1.0
          : targetSide / longest;
      codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).round().clamp(1, width),
        targetHeight: (height * scale).round().clamp(1, height),
      );
      if (!current()) return null;
      if (codec.frameCount != 1) {
        throw const PngFileException(PngFileProblem.unsupported);
      }
      final frame = await codec.getNextFrame();
      if (!current()) {
        frame.image.dispose();
        return null;
      }
      return (image: frame.image, width: width, height: height);
    } on PngFileException {
      rethrow;
    } catch (_) {
      _malformed();
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      if (clearEncodedBytes) clear();
    }
  }

  static Never _malformed() =>
      throw const PngFileException(PngFileProblem.malformed);

  /// Check PNG boundaries and integrity before invoking the engine decoder.
  /// Signature alone (or an image decoder tolerant of truncated data) is not
  /// proof that the selected file is a complete PNG.
  static (int, int) _verifyChunks(Uint8List bytes) {
    if (bytes.length < 45) _malformed();
    for (var i = 0; i < _signature.length; ++i) {
      if (bytes[i] != _signature[i]) _malformed();
    }
    final data = ByteData.sublistView(bytes);
    var cursor = 8;
    var width = 0, height = 0;
    var hasData = false;
    while (cursor + 12 <= bytes.length) {
      final length = data.getUint32(cursor);
      final type = data.getUint32(cursor + 4);
      final end = cursor + 8 + length;
      if (end + 4 > bytes.length) _malformed();
      if (cursor == 8) {
        if (type != _ihdr || length != 13) _malformed();
        width = data.getUint32(cursor + 8);
        height = data.getUint32(cursor + 12);
        if (width == 0 || height == 0) _malformed();
        if (width > _maxSide ||
            height > _maxSide ||
            width * height > _maxPixels) {
          throw const PngFileException(PngFileProblem.dimensions);
        }
      } else if (type == _ihdr) {
        _malformed();
      }
      var crc = 0xffffffff;
      for (var i = cursor + 4; i < end; ++i) {
        crc = _crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
      }
      if ((crc ^ 0xffffffff) != data.getUint32(end)) _malformed();
      if (_animationChunks.contains(type)) {
        throw const PngFileException(PngFileProblem.unsupported);
      }
      if (type == _idat && length != 0) hasData = true;
      if (type == _iend) {
        if (length != 0 || !hasData || end + 4 != bytes.length) _malformed();
        return (width, height);
      }
      cursor = end + 4;
    }
    _malformed();
  }
}
