import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PNG metadata uses a single UTF-8 iTXt AIGC field (GB 45438-2025 Annex E).
class AiContent {
  static const provider = '河南省问灵科技有限公司';
  static String label(Map<String, dynamic> item) {
    final supplied = item['aiLabel']?.toString() ?? '';
    if (supplied == 'AI生成内容' || supplied == '疑似AI生成内容') return supplied;
    if (item['aiGenerated'] == true) return 'AI生成内容';
    return RegExp(
          r'(AI|人工智能)\s*(生成|合成)',
          caseSensitive: false,
        ).hasMatch(item['content']?.toString() ?? '')
        ? '疑似AI生成内容'
        : '';
  }

  static String markedText(String text, String label) =>
      label.isEmpty || text.startsWith('【$label】') ? text : '【$label】\n$text';

  static Map<String, String> metadata(
    List<int> content, {
    String label = '1',
    Map? source,
    bool propagated = false,
  }) {
    final id = sha256.convert(content).toString();
    return {
      'Label': label,
      'ContentProducer':
          source?['ContentProducer']?.toString() ??
          (propagated ? '' : provider),
      'ProduceID': source?['ProduceID']?.toString() ?? (propagated ? '' : id),
      'ReservedCode1': source?['ReservedCode1']?.toString() ?? '',
      'ContentPropagator': provider,
      'PropagateID': id,
      'ReservedCode2': '',
    };
  }

  static Uint8List pngMetadata(Uint8List png, Map<String, String> metadata) {
    if (png.length < 20 ||
        png[0] != 137 ||
        ascii.decode(png.sublist(1, 4)) != 'PNG') {
      throw const FormatException('Expected PNG');
    }
    final out = BytesBuilder()..add(png.sublist(0, 8));
    final payload = <int>[
      ...ascii.encode('AIGC'),
      0,
      0,
      0,
      0,
      0,
      ...utf8.encode(jsonEncode({'AIGC': metadata})),
    ];
    var offset = 8;
    while (offset + 12 <= png.length) {
      final size = ByteData.sublistView(png, offset, offset + 4).getUint32(0);
      final end = offset + size + 12;
      if (end > png.length) throw const FormatException('Truncated PNG');
      final type = ascii.decode(png.sublist(offset + 4, offset + 8));
      final oldText = type == 'iTXt' || type == 'tEXt' || type == 'zTXt';
      final isAigc =
          oldText &&
          utf8
              .decode(png.sublist(offset + 8, end - 4), allowMalformed: true)
              .contains('AIGC');
      if (type == 'IEND') out.add(_chunk('iTXt', payload));
      if (!isAigc) out.add(png.sublist(offset, end));
      offset = end;
      if (type == 'IEND') return out.toBytes();
    }
    throw const FormatException('Missing IEND');
  }

  static List<int> _chunk(String type, List<int> payload) {
    final body = [...ascii.encode(type), ...payload];
    var crc = 0xffffffff;
    for (final byte in body) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    final length = ByteData(4)..setUint32(0, payload.length);
    final checksum = ByteData(4)..setUint32(0, (crc ^ 0xffffffff) & 0xffffffff);
    return [
      ...length.buffer.asUint8List(),
      ...body,
      ...checksum.buffer.asUint8List(),
    ];
  }
}
