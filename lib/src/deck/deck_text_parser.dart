// 移动端卡组文本解析器，支持 YDK 文本 YDKe 卡组码和 Ourocg 分享链接

import 'dart:convert';
import 'dart:typed_data';

import 'ydk_deck.dart';

class DeckTextParser {
  // 判断剪贴板文本是否很可能包含可导入的卡组
  static bool looksLikeDeckText(String value) {
    final text = value.trim();
    if (text.isEmpty || text.length > 1024 * 1024) return false;
    final lower = text.toLowerCase();
    return lower.contains('ydke://') ||
        (lower.contains('#main') && lower.contains('#extra')) ||
        (lower.contains('deck.ourygo.top') && lower.contains('d='));
  }

  // 自动识别并解析卡组文本
  static YdkDeck parse(String value, {String name = '文本导入卡组'}) {
    final text = value.trim();
    if (text.isEmpty) throw const FormatException('卡组文本不能为空');
    final lower = text.toLowerCase();
    if (lower.contains('ydke://')) {
      return _parseYdke(text, name: name);
    }
    if (lower.contains('deck.ourygo.top') && lower.contains('d=')) {
      return _parseOurocg(text, name: name);
    }
    return YdkDeckParser.parse(text, name: _normalizeName(name));
  }

  // 从一段文本中提取并解析 YDKe 链接
  static YdkDeck _parseYdke(String text, {required String name}) {
    final match = RegExp(
      r'ydke://[^\s<>]+',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) throw const FormatException('未找到有效的 YDKe 卡组码');
    var encoded = match.group(0)!.substring(7);
    encoded = encoded.replaceFirst(RegExp(r'[，。,.;；]+$'), '');
    final parts = encoded.split('!');
    if (parts.length < 3) throw const FormatException('YDKe 卡组码分段不完整');
    final deck = YdkDeck(
      name: _normalizeName(name),
      main: List<int>.unmodifiable(_decodeYdkeSection(parts[0])),
      extra: List<int>.unmodifiable(_decodeYdkeSection(parts[1])),
      side: List<int>.unmodifiable(_decodeYdkeSection(parts[2])),
    );
    return _validate(deck);
  }

  // 解码 YDKe 单个卡组区域的小端卡片编号
  static List<int> _decodeYdkeSection(String value) {
    if (value.isEmpty) return const <int>[];
    Uint8List bytes;
    try {
      bytes = base64.decode(base64.normalize(value));
    } catch (_) {
      throw const FormatException('YDKe 卡组码包含无效 Base64 数据');
    }
    if (bytes.length % 4 != 0) {
      throw const FormatException('YDKe 卡组码字节长度无效');
    }
    final data = ByteData.sublistView(bytes);
    return <int>[
      for (var offset = 0; offset < bytes.length; offset += 4)
        data.getUint32(offset, Endian.little),
    ];
  }

  // 从一段文本中提取并解析 Ourocg V1 分享链接
  static YdkDeck _parseOurocg(String text, {required String name}) {
    final match = RegExp(
      r'https?://[^\s<>]+',
      caseSensitive: false,
    ).allMatches(text).where((item) {
      final value = item.group(0)!.toLowerCase();
      return value.contains('deck.ourygo.top') && value.contains('d=');
    }).firstOrNull;
    if (match == null) throw const FormatException('未找到有效的 Ourocg 分享链接');
    final rawUrl = match.group(0)!.replaceFirst(RegExp(r'[，。,.;；]+$'), '');
    final uri = Uri.tryParse(rawUrl);
    final encoded = uri?.queryParameters['d'];
    if (encoded == null || encoded.isEmpty) {
      throw const FormatException('Ourocg 分享链接缺少卡组数据');
    }
    Uint8List bytes;
    try {
      bytes = base64.decode(base64.normalize(encoded));
    } catch (_) {
      throw const FormatException('Ourocg 卡组数据无法解码');
    }
    final bits = StringBuffer();
    for (final byte in bytes) {
      bits.write(byte.toRadixString(2).padLeft(8, '0'));
    }
    final source = bits.toString();
    if (source.length < 16) throw const FormatException('Ourocg 卡组数据过短');
    final uniqueCounts = <int>[
      int.parse(source.substring(0, 8), radix: 2),
      int.parse(source.substring(8, 12), radix: 2),
      int.parse(source.substring(12, 16), radix: 2),
    ];
    var offset = 16;

    // 解码 Ourocg 中一个由 29 位记录组成的卡组区域
    List<int> readSection(int count) {
      final cards = <int>[];
      for (var index = 0; index < count; index += 1) {
        if (offset + 29 > source.length) {
          throw const FormatException('Ourocg 卡组数据分段不完整');
        }
        final value =
            int.parse(source.substring(offset, offset + 29), radix: 2);
        offset += 29;
        final copies = value >> 27;
        final code = value & 0x7ffffff;
        if (copies < 1 || code < 1) {
          throw const FormatException('Ourocg 卡组数据包含无效卡片');
        }
        cards.addAll(List<int>.filled(copies, code));
      }
      return cards;
    }

    final deck = YdkDeck(
      name: _normalizeName(name),
      main: List<int>.unmodifiable(readSection(uniqueCounts[0])),
      extra: List<int>.unmodifiable(readSection(uniqueCounts[1])),
      side: List<int>.unmodifiable(readSection(uniqueCounts[2])),
    );
    return _validate(deck);
  }

  // 校验文本解析结果是否满足连接所需的卡组数量
  static YdkDeck _validate(YdkDeck deck) {
    if (!deck.isStorageSafe || !deck.isValid) {
      throw FormatException(
        '卡组数量不符合要求: main=${deck.main.length} '
        'extra=${deck.extra.length} side=${deck.side.length}',
      );
    }
    return deck;
  }

  // 规范化文本导入时使用的卡组文件名
  static String _normalizeName(String value) {
    final trimmed = value.trim().isEmpty ? '文本导入卡组' : value.trim();
    return trimmed.toLowerCase().endsWith('.ydk') ? trimmed : '$trimmed.ydk';
  }
}
