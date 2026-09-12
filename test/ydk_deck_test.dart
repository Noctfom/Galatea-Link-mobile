// YDK 卡组解析测试，验证区域划分、数量限制和非法代码拒绝

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/game_protocol/byte_cursor.dart';
import 'package:galatea_link_mobile/src/deck/ydk_deck.dart';

void main() {
  // 验证主卡组、额外卡组和副卡组可以正确读取
  test('parses ydk sections', () {
    final content = [
      '#main',
      ...List<String>.filled(40, '100001'),
      '#extra',
      '100002',
      '!side',
      '100003',
    ].join('\n');

    final deck = YdkDeckParser.parse(content, name: '测试卡组');

    expect(deck.name, '测试卡组');
    expect(deck.main, hasLength(40));
    expect(deck.extra, [100002]);
    expect(deck.side, [100003]);
    expect(deck.isValid, isTrue);
  });

  // 验证主卡组数量不足时拒绝进入对局
  test('rejects an undersized main deck', () {
    final content = ['#main', ...List<String>.filled(39, '100001')].join('\n');

    expect(
      () => YdkDeckParser.parse(content),
      throwsA(isA<YgoProtocolException>()),
    );
  });

  // 验证未知区域和非法卡片代码不会被静默接受
  test('rejects invalid card codes', () {
    expect(
      () => YdkDeckParser.parse('#main\nnot-a-card'),
      throwsA(isA<YgoProtocolException>()),
    );
  });

  // 验证本地编辑可以暂存未达到对局数量的安全卡组
  test('parses safe draft deck without duel validation', () {
    final deck = YdkDeckParser.parse(
      '#main\n100001\n#extra\n100002\n!side\n',
      requireDuelValid: false,
    );

    expect(deck.isStorageSafe, isTrue);
    expect(deck.isValid, isFalse);
    expect(deck.toYdkText(), contains('#extra\n100002'));
  });
}
