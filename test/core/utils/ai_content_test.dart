import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/core/utils/ai_content.dart';

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a9sAAAAASUVORK5CYII=',
  );
  test(
    'PNG metadata roundtrip replaces existing marker and keeps image chunks',
    () {
      final meta = AiContent.metadata(utf8.encode('AI answer'));
      final first = AiContent.pngMetadata(png, meta);
      final second = AiContent.pngMetadata(first, meta);
      expect(second, first);
      var offset = 8;
      var markers = 0;
      final types = <String>[];
      while (offset + 12 <= second.length) {
        final size = ByteData.sublistView(
          second,
          offset,
          offset + 4,
        ).getUint32(0);
        final type = ascii.decode(second.sublist(offset + 4, offset + 8));
        types.add(type);
        if (type == 'iTXt') {
          markers++;
          final payload = second.sublist(offset + 8, offset + 8 + size);
          expect(utf8.decode(payload.sublist(0, 4)), 'AIGC');
          final decoded = jsonDecode(utf8.decode(payload.sublist(9))) as Map;
          expect(decoded['AIGC'], meta);
        }
        offset += size + 12;
      }
      expect(markers, 1);
      expect(types, ['IHDR', 'IDAT', 'iTXt', 'IEND']);
    },
  );
  test('Propagation preserves producer identity and suspected label', () {
    final meta = AiContent.metadata(
      [1, 2],
      source: {'ContentProducer': 'upstream', 'ProduceID': 'original'},
      propagated: true,
      label: '3',
    );
    expect(meta['ContentProducer'], 'upstream');
    expect(meta['ProduceID'], 'original');
    expect(meta['ContentPropagator'], AiContent.provider);
    expect(meta['Label'], '3');
    expect(
      AiContent.label({'aiStatus': 'suspected', 'aiLabel': '疑似AI生成内容'}),
      '疑似AI生成内容',
    );
    expect(AiContent.label({'content': '【本内容由AI生成】'}), '疑似AI生成内容');
    expect(AiContent.label({'content': '普通作品'}), '');
  });
}
