// 移动端 GameState 测试，验证开局、区域数量、生命值和交互时点

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/game_protocol/byte_cursor.dart';
import 'package:galatea_link_mobile/src/game_protocol/ocg_parser.dart';
import 'package:galatea_link_mobile/src/game_state.dart';

// 构建小端整数测试字节
List<int> littleEndian(int value, int bytes) {
  final data = ByteData(bytes);
  if (bytes == 2) data.setUint16(0, value, Endian.little);
  if (bytes == 4) data.setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

// 编码 OCG 卡片位置信息
int locationValue(int controller, int location, int sequence, int position) {
  return controller | (location << 8) | (sequence << 16) | (position << 24);
}

void main() {
  // 验证 MSG_START 占用整个外层载荷并初始化额外卡组数量
  test('parses start message as an envelope terminal message', () {
    final payload = <int>[
      4,
      1,
      4,
      ...littleEndian(8000, 4),
      ...littleEndian(7000, 4),
      ...littleEndian(42, 2),
      ...littleEndian(15, 2),
      ...littleEndian(38, 2),
      ...littleEndian(12, 2),
    ];

    final messages = OcgParser.parse(payload);
    final state = MobileGameState()..apply(messages.single);

    expect(messages, hasLength(1));
    expect(messages.single.payload, hasLength(18));
    expect(state.playerId, 1);
    expect(state.lp0, 8000);
    expect(state.lp1, 7000);
    expect(state.deck0Count, 42);
    expect(state.extra0Count, 15);
    expect(state.extra1Count, 12);
  });

  // 验证完整交互帧可以修正 Core 视角且拒绝观战座位编号
  test('synchronizes player perspective from interaction', () {
    final state = MobileGameState()..assignPlayerPerspective(1);

    expect(state.playerId, 1);
    expect(
      () => state.assignPlayerPerspective(2),
      throwsA(isA<YgoProtocolException>()),
    );
  });

  // 验证更新数据消息不会把内部查询字节误判成新 OCG 类型
  test('keeps update data payload intact', () {
    final messages = OcgParser.parse([6, 1, 2, 16, 0, 0, 0, 3, 0, 0, 0]);

    expect(messages, hasLength(1));
    expect(messages.single.type, 6);
    expect(messages.single.payload, [1, 2, 16, 0, 0, 0, 3, 0, 0, 0]);
  });

  // 验证 MSG_UPDATE_CARD 同样占用整个服务器外层载荷
  test('keeps update card payload intact', () {
    final messages = OcgParser.parse([7, 1, 4, 0, 9, 8, 7]);

    expect(messages, hasLength(1));
    expect(messages.single.type, 7);
    expect(messages.single.payload, [1, 4, 0, 9, 8, 7]);
  });

  // 验证卡片从额外卡组移动后只减少对应额外数量
  test('tracks extra deck moves without resetting initial count', () {
    final state = MobileGameState()
      ..playerId = 0
      ..extra0Count = 15
      ..deck0Count = 40;
    final movePayload = <int>[
      ...littleEndian(12345678, 4),
      ...littleEndian(locationValue(0, locationExtra, 0, 0x08), 4),
      ...littleEndian(locationValue(0, locationMonster, 0, 0x01), 4),
      ...littleEndian(0, 4),
    ];

    state.apply(OcgMessage(type: 50, payload: Uint8List.fromList(movePayload)));

    expect(state.extra0Count, 14);
    expect(state.deck0Count, 40);
    expect(state.cards.single.code, 12345678);
  });

  // 验证完整己方卡表只在本地按公开移动维护
  test('tracks own remaining deck locally', () {
    final state = MobileGameState()
      ..playerId = 0
      ..setOwnDeck([100, 200], [300]);
    final movePayload = <int>[
      ...littleEndian(100, 4),
      ...littleEndian(locationValue(0, locationDeck, 0, 0), 4),
      ...littleEndian(locationValue(0, locationHand, 0, 0), 4),
      ...littleEndian(0, 4),
    ];

    state.apply(OcgMessage(type: 50, payload: Uint8List.fromList(movePayload)));

    expect(state.ownRemainingDeckCodes, [200]);
    expect(state.ownRemainingExtraCodes, [300]);
  });

  // 验证回合、阶段、伤害和 YesNo 可以连续解析
  test('updates flow lp and pending action', () {
    final batch = <int>[
      40,
      1,
      41,
      ...littleEndian(4, 2),
      91,
      0,
      ...littleEndian(1500, 4),
      13,
      0,
      ...littleEndian(99, 4),
    ];
    final state = MobileGameState();

    state.applyBatch(batch);

    expect(state.turn, 1);
    expect(state.activePlayer, 1);
    expect(state.phase, 4);
    expect(state.lp0, 6500);
    expect(state.pendingAction?.type, 13);
    expect(state.pendingAction?.options, [0, 1]);
  });

  // 验证效果确认读取完整四字节位置后再读取描述编号
  test('parses effect yes no position and description', () {
    final payload = <int>[
      12,
      0,
      ...littleEndian(12345, 4),
      0,
      locationMonster,
      2,
      1,
      ...littleEndian(77, 4),
    ];
    final state = MobileGameState()..applyBatch(payload);

    expect(state.pendingAction?.type, 12);
    expect(state.pendingAction?.code, 12345);
    expect(state.pendingAction?.descriptionId, 77);
    expect(state.pendingAction?.rawPayload, hasLength(13));
  });

  // 验证主要阶段命令会完整解析所有服务端合法响应
  test('parses idle command actions', () {
    final item = <int>[1, 0, 0, 0, 0, 4, 0];
    final payload = <int>[11, 0, 1, ...item, 0, 0, 0, 0, 0, 0, 1, 0];
    final state = MobileGameState()..applyBatch(payload);

    expect(state.pendingAction?.type, 11);
    expect(state.pendingAction?.options, [0, 7]);
  });

  // 验证可选连锁包含协议允许的取消响应
  test('parses optional chain action', () {
    final payload = <int>[
      16,
      0,
      1,
      0,
      ...List<int>.filled(8, 0),
      ...List<int>.filled(13, 0),
    ];
    final state = MobileGameState()..applyBatch(payload);

    expect(state.pendingAction?.cancelable, isTrue);
    expect(state.pendingAction?.options, [0, -1]);
    expect(state.pendingAction?.selectionCount, 1);
  });

  // 验证在线协议的空连锁消息不会吞入下一条消息
  test('parses zero-count online chain action', () {
    final state = MobileGameState()
      ..applyBatch(<int>[16, 0, 0, 0, ...List<int>.filled(8, 0)]);

    expect(state.pendingAction?.type, 16);
    expect(state.pendingAction?.cancelable, isTrue);
    expect(state.pendingAction?.options, [-1]);
  });

  // 验证选项数量会作为 V3 动作上下文保留
  test('preserves option count for model context', () {
    final payload = <int>[
      14,
      0,
      2,
      ...littleEndian(101, 4),
      ...littleEndian(202, 4),
    ];
    final state = MobileGameState()..applyBatch(payload);

    expect(state.pendingAction?.selectionCount, 2);
    expect(state.pendingAction?.optionDescriptions, <int>[101, 202]);
  });

  // 验证区域数量字节为零时仍按一个区域生成兼容响应
  test('normalizes zero place count to one response place', () {
    final state = MobileGameState()
      ..applyBatch(<int>[18, 0, 0, 0xff, 0xe0, 0xff, 0xff]);

    expect(state.pendingAction?.type, 18);
    expect(state.pendingAction?.selectionMin, 0);
    expect(state.pendingAction?.selectionCount, 1);
    expect(state.pendingAction?.options, hasLength(5));
  });

  // 验证宣言位数会同步到数量约束和上下文字段来源
  test('preserves announce mask count constraints', () {
    final payload = <int>[140, 0, 2, ...littleEndian(0x201, 4)];
    final state = MobileGameState()..applyBatch(payload);

    expect(state.pendingAction?.selectionMin, 2);
    expect(state.pendingAction?.selectionMax, 2);
  });

  // 验证在线协议的强制连锁标记按正确偏移读取
  test('parses forced online chain', () {
    final payload = <int>[
      16,
      0,
      1,
      1,
      ...List<int>.filled(8, 0),
      3,
      ...littleEndian(12345, 4),
      ...littleEndian(locationValue(0, locationMonster, 2, 1), 4),
      ...littleEndian(77, 4),
    ];
    final state = MobileGameState()..applyBatch(payload);

    expect(state.pendingAction?.cancelable, isFalse);
    expect(state.pendingAction?.options, [0]);
    expect(state.pendingAction?.rawPayload.length, 24);
  });

  // 验证连锁排序被保留为必须响应的交互消息
  test('parses sort chain as an interaction', () {
    final payload = <int>[21, 0, 2, ...List<int>.filled(14, 0)];
    final state = MobileGameState()..applyBatch(payload);

    expect(state.pendingAction?.type, 21);
    expect(state.pendingAction?.selectionCount, 2);
    expect(state.pendingAction?.options, [0, 1]);
  });

  // 验证连锁会保留发动位置、触发位置并写入最新优先的历史
  test('tracks chaining context and recent effect history', () {
    final state = MobileGameState()..playerId = 0;
    for (var index = 0; index < 10; index++) {
      final payload = <int>[
        ...littleEndian(1000 + index, 4),
        ...littleEndian(locationValue(0, locationHand, index, 2), 4),
        1,
        locationMonster,
        index,
        ...littleEndian(2000 + index, 4),
        index + 1,
      ];
      state.apply(OcgMessage(type: 70, payload: Uint8List.fromList(payload)));
    }

    expect(state.chain, hasLength(10));
    expect(state.chain.last.handlerController, 0);
    expect(state.chain.last.handlerLocation, locationHand);
    expect(state.chain.last.handlerSequence, 9);
    expect(state.chain.last.handlerPosition, 2);
    expect(state.chain.last.controller, 1);
    expect(state.chain.last.location, locationMonster);
    expect(state.history, hasLength(8));
    expect(state.history.first.code, 1009);
    expect(state.history.last.code, 1002);

    state.apply(OcgMessage(type: 74, payload: Uint8List(0)));
    expect(state.chain, isEmpty);
    expect(state.history, hasLength(8));
  });

  // 验证已绑定的发动效果会标记对应实体并在换回合时清除
  test('tracks resolved used effect slots until next turn', () {
    final state = MobileGameState()
      ..playerId = 0
      ..cards = const <VisibleCard>[
        VisibleCard(
          code: 100,
          controller: 0,
          location: locationMonster,
          sequence: 0,
          position: 1,
          publiclyVisible: true,
        ),
      ];
    final payload = <int>[
      ...littleEndian(100, 4),
      ...littleEndian(locationValue(0, locationMonster, 0, 1), 4),
      0,
      locationMonster,
      0,
      ...littleEndian(77, 4),
      1,
    ];

    state.apply(
      OcgMessage(type: 70, payload: Uint8List.fromList(payload)),
      effectSlotResolver: (code, description) => 2,
    );

    expect(state.chain.single.effectSlot, 2);
    expect(state.history.single.effectSlot, 2);
    expect(state.cards.single.usedEffectMask, 1 << 2);

    state.apply(OcgMessage(type: 40, payload: Uint8List.fromList([1])));
    expect(state.cards.single.usedEffectMask, 0);
  });

  // 验证生命值成本、装备关系和指示物增减会更新动态状态
  test('tracks lp cost equipment and counter messages', () {
    final state = MobileGameState()
      ..lp0 = 8000
      ..cards = const <VisibleCard>[
        VisibleCard(
          code: 100,
          controller: 0,
          location: locationMonster,
          sequence: 0,
          position: 1,
          publiclyVisible: true,
        ),
      ];
    final target = locationValue(0, locationMonster, 0, 1);

    state.applyBatch(<int>[
      100,
      0,
      ...littleEndian(1000, 4),
      93,
      ...littleEndian(locationValue(0, locationSpellTrap, 0, 1), 4),
      ...littleEndian(target, 4),
      101,
      ...littleEndian(0x10, 2),
      0,
      locationMonster,
      0,
      ...littleEndian(3, 2),
      102,
      ...littleEndian(0x10, 2),
      0,
      locationMonster,
      0,
      ...littleEndian(1, 2),
    ]);

    expect(state.lp0, 7000);
    expect(state.cards.single.isEquipped, isTrue);
    expect(state.cards.single.counters, <int, int>{0x10: 2});
  });

  // 验证双列表选卡交互的结束和取消标记
  test('parses select unselect action', () {
    final payload = <int>[26, 0, 1, 1, 0, 2, 1, ...List<int>.filled(8, 0), 0];
    final state = MobileGameState()..applyBatch(payload);

    expect(state.pendingAction?.finishable, isTrue);
    expect(state.pendingAction?.cancelable, isTrue);
    expect(state.pendingAction?.options, [0]);
  });

  // 验证重试保留原交互而后续正常消息会清理过期交互
  test('preserves pending action only for retry', () {
    final state = MobileGameState()
      ..apply(
        OcgMessage(type: 13, payload: Uint8List.fromList([0, 1, 0, 0, 0])),
      );

    state.applyBatch([1]);
    expect(state.retryRequested, isTrue);
    expect(state.pendingAction?.type, 13);

    state.applyBatch([41, 4, 0]);
    expect(state.retryRequested, isFalse);
    expect(state.pendingAction, isNull);
  });

  // 验证未知消息没有长度定义时直接拒绝
  test('rejects unknown message lengths', () {
    expect(
      () => OcgParser.parse([255, 1, 2, 3]),
      throwsA(isA<YgoProtocolException>()),
    );
  });
}
