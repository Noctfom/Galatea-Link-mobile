// 移动端 RuleBot 测试，验证简单交互只生成协议允许的响应

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/decision/rule_fallback.dart';
import 'package:galatea_link_mobile/src/game_state.dart';

void main() {
  // 验证连锁排序会按服务器原顺序返回完整索引
  test('keeps chain order', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(
        type: 21,
        player: 0,
        options: <int>[0, 1, 2],
        selectionCount: 3,
      ),
    );

    expect(response?.payload, [0, 1, 2]);
  });

  // 验证 YesNo 默认拒绝并使用四字节整数响应
  test('rejects yes no safely', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(type: 13, player: 0, options: <int>[0, 1]),
    );

    expect(response?.payload, [0, 0, 0, 0]);
  });

  // 验证选项响应使用合法索引而不是描述编号
  test('selects first option index', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(
        type: 14,
        player: 0,
        options: <int>[0, 1],
        optionDescriptions: <int>[100, 200],
      ),
    );

    expect(response?.payload, [0, 0, 0, 0]);
  });

  // 验证单格位置选择转换为三字节绝对位置
  test('packs one place selection', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(
          type: 18, player: 1, options: <int>[9], selectionCount: 1),
    );

    expect(response?.payload, [1, locationSpellTrap, 1]);
  });

  // 验证普通选卡返回带数量前缀的最低合法组合
  test('selects minimum card count', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(
        type: 15,
        player: 0,
        options: <int>[0, 1, 2],
        selectionMin: 2,
        selectionMax: 3,
      ),
    );

    expect(response?.payload, [2, 0, 1]);
  });

  // 验证非强制连锁优先跳过以保持响应合法
  test('skips optional chain', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(
        type: 16,
        player: 0,
        options: <int>[0, 1, -1],
        cancelable: true,
      ),
    );

    expect(response?.payload, [255, 255, 255, 255]);
  });

  // 验证指示物数量按每张卡容量编码为十六位整数
  test('distributes counters across cards', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(
        type: 22,
        player: 0,
        options: <int>[],
        rawPayload: <int>[
          0,
          1,
          0,
          3,
          0,
          2,
          0,
          0,
          0,
          0,
          0,
          4,
          0,
          2,
          0,
          0,
          0,
          0,
          0,
          0,
          4,
          1,
          3,
          0,
        ],
      ),
    );

    expect(response?.payload, [2, 0, 1, 0]);
  });

  // 验证属性宣言从可用掩码中选择要求数量
  test('packs announce mask', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(
        type: 141,
        player: 0,
        options: <int>[],
        rawPayload: <int>[0, 2, 10, 0, 0, 0],
      ),
    );

    expect(response?.payload, [10, 0, 0, 0]);
  });

  // 验证复杂凑数交互返回合法候选索引
  test('solves select sum', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(
        type: 23,
        player: 0,
        options: <int>[],
        rawPayload: <int>[
          0,
          0,
          5,
          0,
          0,
          0,
          1,
          2,
          0,
          2,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          2,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          3,
          0,
          0,
          0,
        ],
      ),
    );

    expect(response?.payload, [2, 0, 1]);
  });

  // 验证需要卡片数据库的宣言交互保持暂停
  test('pauses unsupported announce card', () {
    final response = MobileRuleFallback.decide(
      const PendingAction(type: 142, player: 0, options: <int>[]),
    );

    expect(response, isNull);
  });
}
