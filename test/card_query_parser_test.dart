// 卡片查询解析测试，验证单卡与区域更新不会越界或污染已有状态

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/game_protocol/byte_cursor.dart';
import 'package:galatea_link_mobile/src/game_protocol/card_query_parser.dart';
import 'package:galatea_link_mobile/src/game_protocol/ocg_parser.dart';
import 'package:galatea_link_mobile/src/game_state.dart';

// 编码小端无符号整数
List<int> uintLe(int value, int bytes) {
  final data = ByteData(bytes);
  if (bytes == 2) data.setUint16(0, value, Endian.little);
  if (bytes == 4) data.setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

// 编码小端有符号三十二位整数
List<int> int32Le(int value) {
  final data = ByteData(4)..setInt32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

// 编码带总长度头的卡片查询分块
List<int> queryBlock(int flags, List<int> fields) {
  final body = <int>[...uintLe(flags, 4), ...fields];
  return <int>[...uintLe(body.length + 4, 4), ...body];
}

// 编码查询中的卡片位置整数
int queryPositionValue(
  int controller,
  int location,
  int sequence,
  int position,
) {
  return controller | (location << 8) | (sequence << 16) | (position << 24);
}

void main() {
  // 验证完整查询字段按照标准顺序解析
  test('parses bounded legacy card query block', () {
    const flags = queryCode |
        queryPosition |
        queryType |
        queryLevel |
        queryAttack |
        queryDefense |
        queryOverlayCard |
        queryCounters |
        queryOwner |
        queryStatus |
        queryLeftScale |
        queryRightScale |
        queryLink;
    final bytes = queryBlock(flags, <int>[
      ...uintLe(12345678, 4),
      ...uintLe(queryPositionValue(0, locationMonster, 2, 1), 4),
      ...uintLe(0x21, 4),
      ...uintLe(4, 4),
      ...int32Le(1800),
      ...int32Le(-1),
      ...uintLe(2, 4),
      ...uintLe(11, 4),
      ...uintLe(22, 4),
      ...uintLe(1, 4),
      ...uintLe(0x10, 2),
      ...uintLe(3, 2),
      ...uintLe(1, 4),
      ...uintLe(0x40, 4),
      ...uintLe(2, 4),
      ...uintLe(7, 4),
      ...uintLe(3, 4),
      ...uintLe(0x81, 4),
    ]);

    final block = CardQueryParser.parseBlock(ByteCursor(bytes));
    final update = block.update!;

    expect(block.byteLength, bytes.length);
    expect(update.code, 12345678);
    expect(update.position, 1);
    expect(update.type, 0x21);
    expect(update.level, 4);
    expect(update.attack, 1800);
    expect(update.defense, -1);
    expect(update.overlayCodes, [11, 22]);
    expect(update.counters, {0x10: 3});
    expect(update.owner, 1);
    expect(update.status, 0x40);
    expect(update.leftScale, 2);
    expect(update.rightScale, 7);
    expect(update.link, 3);
    expect(update.linkMarker, 0x81);
  });

  // 验证在线旧式查询把公开与隐藏状态编码在位图而非额外整数中
  test('parses flag-only public and hidden query fields', () {
    final bytes = queryBlock(
      queryCode | queryIsPublic | queryIsHidden,
      uintLe(12345678, 4),
    );

    final update = CardQueryParser.parseBlock(ByteCursor(bytes)).update!;

    expect(update.code, 12345678);
    expect(update.isPublic, isTrue);
    expect(update.isHidden, isTrue);
  });

  // 验证服务器的零填充空查询会清空旧状态而不触发错位
  test('accepts zero-padded empty query block', () {
    final bytes = <int>[...uintLe(16, 4), ...List<int>.filled(12, 0)];

    final block = CardQueryParser.parseBlock(ByteCursor(bytes));

    expect(block.byteLength, 16);
    expect(block.update?.clearData, isTrue);
  });

  // 验证真实在线单卡更新帧可以完整消费并保留公开状态
  test('parses captured online update card payload', () {
    final payload = <int>[
      0x00,
      0x04,
      0x01,
      0x50,
      0x00,
      0x00,
      0x00,
      0xff,
      0x1f,
      0xf8,
      0x00,
      0x70,
      0x93,
      0xb2,
      0x03,
      0x00,
      0x04,
      0x01,
      0x01,
      0x70,
      0x93,
      0xb2,
      0x03,
      0x21,
      0x00,
      0x00,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x20,
      0x00,
      0x00,
      0x00,
      0x08,
      0x07,
      0x00,
      0x00,
      0xf4,
      0x01,
      0x00,
      0x00,
      0x08,
      0x07,
      0x00,
      0x00,
      0xf4,
      0x01,
      0x00,
      0x00,
      0x00,
      0x04,
      0x00,
      0x02,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    final state = MobileGameState()
      ..apply(OcgMessage(type: 7, payload: Uint8List.fromList(payload)));

    expect(state.cards, hasLength(1));
    expect(state.cards.single.publiclyVisible, isTrue);
    expect(state.cards.single.attack, 1800);
    expect(state.cards.single.defense, 500);
  });

  // 验证 MSG_UPDATE_CARD 会补全已知卡片动态属性
  test('merges a single card query into visible game state', () {
    const flags = queryCode | queryPosition | queryAttack | queryDefense;
    final payload = <int>[
      0,
      locationMonster,
      2,
      ...queryBlock(flags, <int>[
        ...uintLe(7654321, 4),
        ...uintLe(queryPositionValue(0, locationMonster, 2, 1), 4),
        ...int32Le(2500),
        ...int32Le(2000),
      ]),
    ];
    final state = MobileGameState()
      ..apply(OcgMessage(type: 7, payload: Uint8List.fromList(payload)));

    expect(state.cards, hasLength(1));
    expect(state.cards.single.sequence, 2);
    expect(state.cards.single.code, 7654321);
    expect(state.cards.single.attack, 2500);
    expect(state.cards.single.defense, 2000);
    expect(state.cards.single.publiclyVisible, isTrue);
  });

  // 验证区域查询中的空缓存块不会制造不存在的卡片
  test('applies only populated blocks from a field query', () {
    final populated = queryBlock(queryCode, uintLe(4567, 4));
    final payload = <int>[
      1,
      locationGrave,
      ...uintLe(4, 4),
      ...populated,
    ];
    final state = MobileGameState()
      ..apply(OcgMessage(type: 6, payload: Uint8List.fromList(payload)));

    expect(state.cards, hasLength(1));
    expect(state.cards.single.controller, 1);
    expect(state.cards.single.location, locationGrave);
    expect(state.cards.single.sequence, 1);
    expect(state.cards.single.code, 4567);
  });

  // 验证损坏区域查询在失败前不会修改已有卡片集合
  test('rejects malformed field query atomically', () {
    final state = MobileGameState()
      ..apply(
        OcgMessage(
          type: 7,
          payload: Uint8List.fromList(<int>[
            0,
            locationMonster,
            0,
            ...queryBlock(queryCode, uintLe(99, 4)),
          ]),
        ),
      );
    final before = state.cards.single;

    expect(
      () => state.apply(
        OcgMessage(
          type: 6,
          payload: Uint8List.fromList(<int>[
            0,
            locationMonster,
            ...uintLe(100, 4),
            1,
          ]),
        ),
      ),
      throwsA(isA<YgoProtocolException>()),
    );
    expect(state.cards, hasLength(1));
    expect(state.cards.single.code, before.code);
    expect(state.cards.single.attack, before.attack);
  });
}
