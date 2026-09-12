// YDK 卡组解析模块，读取主卡组、额外卡组和副卡组卡片代码

import '../game_protocol/byte_cursor.dart';

class YdkDeck {
  const YdkDeck({
    required this.name,
    required this.main,
    required this.extra,
    required this.side,
  });

  final String name;
  final List<int> main;
  final List<int> extra;
  final List<int> side;

  // 返回卡组是否满足 YGOPro 基础数量限制
  bool get isValid =>
      main.length >= 40 &&
      main.length <= 60 &&
      extra.length <= 15 &&
      side.length <= 15;

  // 返回卡组是否满足本地编辑仓库的安全上限
  bool get isStorageSafe =>
      main.isNotEmpty &&
      main.length <= 100 &&
      extra.length <= 30 &&
      side.length <= 30 &&
      <int>[...main, ...extra, ...side]
          .every((code) => code > 0 && code <= 0xFFFFFFFF);

  // 创建替换指定名称或区域后的不可变卡组
  YdkDeck copyWith({
    String? name,
    List<int>? main,
    List<int>? extra,
    List<int>? side,
  }) {
    return YdkDeck(
      name: name ?? this.name,
      main: List<int>.unmodifiable(main ?? this.main),
      extra: List<int>.unmodifiable(extra ?? this.extra),
      side: List<int>.unmodifiable(side ?? this.side),
    );
  }

  // 将当前卡组编码为标准 YDK 文本
  String toYdkText() {
    return <String>[
      '#created by Galatea Link mobile',
      '#main',
      ...main.map((code) => code.toString()),
      '#extra',
      ...extra.map((code) => code.toString()),
      '!side',
      ...side.map((code) => code.toString()),
      '',
    ].join('\n');
  }
}

class YdkDeckParser {
  // 从 YDK 文本解析数字卡片代码
  static YdkDeck parse(
    String content, {
    String name = 'Mobile Deck',
    bool requireDuelValid = true,
  }) {
    var section = '';
    final main = <int>[];
    final extra = <int>[];
    final side = <int>[];
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line == '#main') {
        section = 'main';
        continue;
      }
      if (line == '#extra') {
        section = 'extra';
        continue;
      }
      if (line == '!side') {
        section = 'side';
        continue;
      }
      if (line.startsWith('#') || line.startsWith('!')) {
        section = '';
        continue;
      }
      final code = int.tryParse(line);
      if (code == null || code <= 0 || code > 0xFFFFFFFF) {
        throw YgoProtocolException('YDK 包含无效卡片代码: $line');
      }
      if (section == 'main') main.add(code);
      if (section == 'extra') extra.add(code);
      if (section == 'side') side.add(code);
    }
    final deck = YdkDeck(
      name: name,
      main: List.unmodifiable(main),
      extra: List.unmodifiable(extra),
      side: List.unmodifiable(side),
    );
    if (!deck.isStorageSafe) {
      throw YgoProtocolException(
          'YDK 卡组超过本地安全限制: main=${main.length} extra=${extra.length} side=${side.length}');
    }
    if (requireDuelValid && !deck.isValid) {
      throw YgoProtocolException(
          'YDK 卡组数量不符合要求: main=${main.length} extra=${extra.length} side=${side.length}');
    }
    return deck;
  }
}
