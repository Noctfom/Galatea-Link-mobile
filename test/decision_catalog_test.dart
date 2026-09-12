// 移动端合法动作目录测试，验证 LLM 只能选择可直接发送的协议响应

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/decision/decision_catalog.dart';
import 'package:galatea_link_mobile/src/game_state.dart';

// 构建小端三十二位测试字节
List<int> littleEndian(int value, int bytes) {
  final data = ByteData(bytes)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  // 验 YesNo 动作只生成拒绝和同意两个候选
  test('builds yes no candidates', () {
    final candidates = DecisionCatalog.build(
      const PendingAction(type: 13, player: 0, options: <int>[0, 1]),
    );

    expect(candidates, hasLength(2));
    expect(candidates[0].payload, [0, 0, 0, 0]);
    expect(candidates[1].payload, [1, 0, 0, 0]);
  });

  // 验证零数量区域交互同时保留空区域响应和实际区域候选
  test('builds compatible zero-count place candidates', () {
    final candidates = DecisionCatalog.build(
      const PendingAction(
        type: 18,
        player: 0,
        options: <int>[0, 1, 2, 3, 4],
        selectionMin: 0,
        selectionMax: 0,
        selectionCount: 1,
      ),
    );

    expect(candidates, hasLength(6));
    expect(candidates.first.payload, <int>[0, 0, 0]);
    expect(candidates[1].payload, <int>[0, 4, 0]);
  });

  // 验证选卡组合包含卡密详情且响应带有数量前缀
  test('builds card selection details', () {
    final candidates = DecisionCatalog.build(
      const PendingAction(
        type: 15,
        player: 0,
        options: <int>[0, 1],
        selectionMin: 1,
        selectionMax: 1,
        rawPayload: <int>[
          0,
          0,
          1,
          1,
          2,
          1,
          0,
          0,
          0,
          0,
          2,
          0,
          1,
          2,
          0,
          0,
          0,
          0,
          2,
          1,
          1,
        ],
      ),
    );

    expect(candidates, hasLength(2));
    expect(candidates.first.payload, [1, 0]);
    final cards = candidates.first.details['cards']! as List;
    expect((cards.first as Map)['code'], 1);
  });

  // 验证数字宣言候选使用索引响应并向 LLM 暴露实际数值
  test('builds announce number candidates', () {
    final candidates = DecisionCatalog.build(
      const PendingAction(
        type: 143,
        player: 0,
        options: <int>[],
        rawPayload: <int>[
          0,
          2,
          3,
          0,
          0,
          0,
          7,
          0,
          0,
          0,
        ],
      ),
    );

    expect(candidates, hasLength(2));
    expect(candidates[1].payload, [1, 0, 0, 0]);
    expect(candidates[1].details['value'], 7);
  });

  // 验证纯卡密白名单即使没有本地数据库也能生成卡名宣言响应
  test('builds direct announce card candidates', () {
    final action = PendingAction(
      type: 142,
      player: 0,
      options: const <int>[],
      rawPayload: <int>[
        0,
        2,
        ...littleEndian(12345, 4),
        ...littleEndian(54321, 4),
      ],
    );

    final candidates = DecisionCatalog.build(action);

    expect(candidates, hasLength(2));
    expect(candidates[0].payload, littleEndian(12345, 4));
    expect(candidates[1].details['code'], 54321);
  });

  // 验证候选数量具有硬上限以控制移动端提示长度
  test('limits candidate combinations', () {
    final candidates = DecisionCatalog.build(
      const PendingAction(
        type: 15,
        player: 0,
        options: <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        selectionMin: 1,
        selectionMax: 5,
        rawPayload: <int>[],
      ),
    );

    expect(candidates.length, lessThanOrEqualTo(120));
  });

  // 验证主要阶段候选向决策器提供卡密位置和效果描述
  test('describes idle command card details', () {
    final candidates = DecisionCatalog.build(
      const PendingAction(
        type: 11,
        player: 0,
        options: <int>[5],
        rawPayload: <int>[
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          57,
          48,
          0,
          0,
          0,
          2,
          1,
          99,
          0,
          0,
          0,
          0,
          0,
          0,
        ],
      ),
    );

    expect(candidates.single.details['code'], 12345);
    expect(candidates.single.details['location'], locationHand);
    expect(candidates.single.details['description_id'], 99);
  });

  // 验证连锁候选跳过完整十一字节头部后读取卡片上下文
  test('describes chain item after v3 header', () {
    final location = 1 | (locationSpellTrap << 8) | (3 << 16) | (8 << 24);
    final action = PendingAction(
      type: 16,
      player: 0,
      options: const <int>[0],
      rawPayload: <int>[
        0,
        1,
        1,
        ...littleEndian(0, 4),
        ...littleEndian(0, 4),
        4,
        ...littleEndian(12345, 4),
        ...littleEndian(location, 4),
        ...littleEndian(77, 4),
      ],
    );

    final candidates = DecisionCatalog.build(action);

    expect(candidates.single.details['code'], 12345);
    expect(candidates.single.details['controller'], 1);
    expect(candidates.single.details['location'], locationSpellTrap);
    expect(candidates.single.details['sequence'], 3);
    expect(candidates.single.details['description_id'], 77);
  });

  // 验证祭品候选按解放值总和而不是选中张数判定
  test('builds tribute combinations by release value', () {
    final action = PendingAction(
      type: 20,
      player: 0,
      options: const <int>[0, 1, 2],
      selectionMin: 3,
      selectionMax: 2,
      rawPayload: <int>[
        0,
        0,
        3,
        2,
        3,
        ...littleEndian(100, 4),
        0,
        locationMonster,
        0,
        2,
        ...littleEndian(200, 4),
        0,
        locationMonster,
        1,
        1,
        ...littleEndian(300, 4),
        0,
        locationMonster,
        2,
        1,
      ],
    );

    final candidates = DecisionCatalog.build(action);

    expect(candidates.map((item) => item.payload),
        anyElement(orderedEquals(<int>[2, 0, 1])));
    expect(candidates.map((item) => item.payload),
        anyElement(orderedEquals(<int>[2, 0, 2])));
    expect(
        candidates.every((item) => item.details['release_value'] == 3), isTrue);
  });

  // 验证指示物分配会枚举所有精确总量方案
  test('builds exact counter distributions', () {
    final action = PendingAction(
      type: 22,
      player: 0,
      options: const <int>[],
      rawPayload: <int>[
        0,
        1,
        0,
        2,
        0,
        2,
        ...littleEndian(100, 4),
        0,
        locationMonster,
        0,
        2,
        0,
        ...littleEndian(200, 4),
        0,
        locationMonster,
        1,
        2,
        0,
      ],
    );

    final candidates = DecisionCatalog.build(action);

    expect(candidates, hasLength(3));
    expect(candidates.map((item) => item.payload),
        anyElement(orderedEquals(<int>[2, 0, 0, 0])));
    expect(candidates.map((item) => item.payload),
        anyElement(orderedEquals(<int>[1, 0, 1, 0])));
    expect(candidates.map((item) => item.payload),
        anyElement(orderedEquals(<int>[0, 0, 2, 0])));
  });

  // 验证凑值交互只暴露通过双重数值规则的组合
  test('builds valid sum combinations', () {
    final action = PendingAction(
      type: 23,
      player: 0,
      options: const <int>[],
      rawPayload: <int>[
        0,
        0,
        ...littleEndian(4, 4),
        1,
        2,
        0,
        3,
        ...littleEndian(100, 4),
        0,
        locationMonster,
        0,
        ...littleEndian(3, 4),
        ...littleEndian(200, 4),
        0,
        locationMonster,
        1,
        ...littleEndian(1, 4),
        ...littleEndian(300, 4),
        0,
        locationMonster,
        2,
        ...littleEndian(2, 4),
      ],
    );

    final candidates = DecisionCatalog.build(action);

    expect(candidates.map((item) => item.payload),
        anyElement(orderedEquals(<int>[2, 0, 1])));
    expect(candidates.last.payload, <int>[255, 255, 255, 255]);
    expect(candidates.first.details['target_value'], 4);
  });

  // 验证排序交互向模型公开多种排列而非固定原顺序
  test('builds sort permutations', () {
    final action = PendingAction(
      type: 25,
      player: 0,
      options: const <int>[0, 1, 2],
      selectionCount: 3,
      rawPayload: <int>[
        0,
        3,
        ...littleEndian(100, 4),
        0,
        locationDeck,
        0,
        ...littleEndian(200, 4),
        0,
        locationDeck,
        1,
        ...littleEndian(300, 4),
        0,
        locationDeck,
        2,
      ],
    );

    final candidates = DecisionCatalog.build(action);

    expect(candidates, hasLength(6));
    expect(candidates.map((item) => item.payload),
        anyElement(orderedEquals(<int>[2, 1, 0])));
    expect((candidates.first.details['cards']! as List), hasLength(3));
  });

  // 验证多项种族属性宣言会生成全部指定大小的位掩码组合
  test('builds announce mask combinations', () {
    final action = PendingAction(
      type: 140,
      player: 0,
      options: const <int>[],
      rawPayload: <int>[0, 2, ...littleEndian(7, 4)],
    );

    final candidates = DecisionCatalog.build(action);

    expect(candidates, hasLength(3));
    expect(
        candidates.map((item) => item.details['mask']), containsAll([3, 5, 6]));
  });
}
