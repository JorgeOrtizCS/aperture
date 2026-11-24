import 'dart:io';
import 'dart:typed_data';

/// Static, synthetic pixels. The tests can independently alter framing,
/// checksum, dimensions and compressed data.
Uint8List pngFixture({
  int width = 2,
  int height = 1,
  List<int>? scanlines,
  bool animated = false,
  List<int> Function(List<int>)? transformCompressed,
}) {
  List<int> uint32(int n) => [
    (n >>> 24) & 255,
    (n >>> 16) & 255,
    (n >>> 8) & 255,
    n & 255,
  ];

  List<int> chunk(String type, List<int> data) {
    final payload = [...type.codeUnits, ...data];
    var crc = 0xffffffff;
    for (final byte in payload) {
      crc ^= byte;
      for (var bit = 0; bit < 8; ++bit) {
        crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    return [...uint32(data.length), ...payload, ...uint32(crc ^ 0xffffffff)];
  }

  final compressed = ZLibEncoder().convert(
    scanlines ?? [0, 31, 78, 121, 230, 157, 43],
  );
  return Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ...chunk('IHDR', [...uint32(width), ...uint32(height), 8, 2, 0, 0, 0]),
    if (animated) ...chunk('acTL', [...uint32(1), ...uint32(0)]),
    ...chunk('IDAT', transformCompressed?.call(compressed) ?? compressed),
    ...chunk('IEND', []),
  ]);
}
