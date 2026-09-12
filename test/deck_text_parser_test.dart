// Galatea Link mobile 卡组文本解析测试，覆盖 YDK 文本和 YDKe 卡组码

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galatea_link_mobile/src/deck/deck_text_parser.dart';

// 编码一组卡片编号为 YDKe 使用的小端 Base64 数据
String encodeYdkeSection(List<int> codes) {
  final bytes = Uint8List(codes.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < codes.length; index += 1) {
    data.setUint32(index * 4, codes[index], Endian.little);
  }
  return base64.encode(bytes);
}

// 编码 Ourocg V1 位流用于验证分享链接兼容性
String encodeOurocg(List<int> main, List<int> extra, List<int> side) {
  final bits = StringBuffer()
    ..write(main.length.toRadixString(2).padLeft(8, '0'))
    ..write(extra.length.toRadixString(2).padLeft(4, '0'))
    ..write(side.length.toRadixString(2).padLeft(4, '0'));
  for (final code in <int>[...main, ...extra, ...side]) {
    final record = (1 << 27) | code;
    bits.write(record.toRadixString(2).padLeft(29, '0'));
  }
  final raw = bits.toString();
  final bytes = Uint8List((raw.length + 7) ~/ 8);
  for (var index = 0; index < bytes.length; index += 1) {
    final start = index * 8;
    final end = (start + 8).clamp(0, raw.length);
    bytes[index] =
        int.parse(raw.substring(start, end).padRight(8, '0'), radix: 2);
  }
  return base64Url.encode(bytes).replaceAll('=', '');
}

// 运行卡组文本自动识别和分段解析测试
void main() {
  test('parses standard YDK text', () {
    final main = List<int>.generate(40, (index) => 10000000 + index);
    final text = <String>[
      '#main',
      ...main.map((code) => code.toString()),
      '#extra',
      '20000001',
      '!side',
      '30000001',
    ].join('\n');

    final deck = DeckTextParser.parse(text, name: '测试卡组');

    expect(deck.name, '测试卡组.ydk');
    expect(deck.main, main);
    expect(deck.extra, <int>[20000001]);
    expect(deck.side, <int>[30000001]);
  });

  test('extracts and parses YDKe code from surrounding text', () {
    final main = List<int>.generate(40, (index) => 40000000 + index);
    final extra = <int>[50000001, 50000002];
    final side = <int>[60000001];
    final code = 'ydke://${encodeYdkeSection(main)}!'
        '${encodeYdkeSection(extra)}!${encodeYdkeSection(side)}!';

    final deck = DeckTextParser.parse('分享卡组 $code 请查收');

    expect(deck.main, main);
    expect(deck.extra, extra);
    expect(deck.side, side);
  });

  test('parses Ourocg V1 share link', () {
    final main = List<int>.generate(40, (index) => 70000000 + index);
    final extra = <int>[71000001, 71000002];
    final side = <int>[72000001];
    final encoded = encodeOurocg(main, extra, side);

    final deck = DeckTextParser.parse(
      'https://deck.ourygo.top/ydk/?d=$encoded',
      name: 'Ourocg 测试',
    );

    expect(deck.main, main);
    expect(deck.extra, extra);
    expect(deck.side, side);
  });

  test('clipboard recognition ignores ordinary chat text', () {
    expect(DeckTextParser.looksLikeDeckText('今晚打牌吗'), isFalse);
    expect(DeckTextParser.looksLikeDeckText('ydke://AAAA!!!!'), isTrue);
  });
}
