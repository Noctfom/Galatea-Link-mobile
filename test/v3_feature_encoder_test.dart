// V3 移动端特征编码测试，验证状态视角掩码和合法动作张量

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/cards/card_database_service.dart';
import 'package:galatea_link_mobile/src/decision/decision_catalog.dart';
import 'package:galatea_link_mobile/src/game_state.dart';
import 'package:galatea_link_mobile/src/models/v3_feature_encoder.dart';
import 'package:galatea_link_mobile/src/models/v3_tensor_spec.dart';

void main() {
  // 验证编码器生成完整且定长的 V3 输入集合
  test('builds every model protocol v3 tensor', () {
    final action = PendingAction(
      type: 12,
      player: 0,
      options: const <int>[0, 1],
      code: 12345,
      descriptionId: 77,
      rawPayload: const <int>[
        0,
        57,
        48,
        0,
        0,
        0,
        locationMonster,
        1,
        1,
        77,
        0,
        0,
        0,
      ],
    );
    final state = MobileGameState()
      ..playerId = 0
      ..turn = 2
      ..phase = 4
      ..activePlayer = 0
      ..hand0Count = 4
      ..hand1Count = 5
      ..pendingAction = action
      ..setOwnDeck(const <int>[12345, 67890], const <int>[24680])
      ..cards = const <VisibleCard>[
        VisibleCard(
          code: 12345,
          controller: 0,
          location: locationMonster,
          sequence: 1,
          position: 1,
          publiclyVisible: true,
          type: 0x21,
          level: 4,
          race: 2,
          attribute: 0x20,
          attack: 1800,
          defense: 1200,
          baseAttack: 1800,
          baseDefense: 1200,
        ),
        VisibleCard(
          code: 0,
          controller: 1,
          location: locationHand,
          sequence: 0,
          position: 0,
          publiclyVisible: false,
        ),
      ];
    final candidates = DecisionCatalog.build(action);

    final batch = V3FeatureEncoder().encode(
      state,
      candidates,
      cardDatabase: _FakeCardDatabase(),
    );

    expect(batch.inputs.keys.toSet(), modelProtocolV3TensorSpecs.keys.toSet());
    for (final entry in modelProtocolV3TensorSpecs.entries) {
      expect(dataLength(batch.inputs[entry.key]!), entry.value.elementCount);
    }
    expect(batch.candidateCount, 2);
    expect((batch.inputs['padding_mask']! as List<bool>).take(3), [
      true,
      true,
      false,
    ]);
    expect((batch.inputs['card_idx']! as Int64List)[0], (12345 % 19990) + 10);
    expect((batch.inputs['card_idx']! as Int64List)[1], 2);
    expect((batch.inputs['card_setcodes']! as Int64List).take(2), <int>[
      0x234,
      0,
    ]);
    expect((batch.inputs['deck_race']! as Int64List)[0], 0x2000 % 30);
    expect((batch.inputs['deck_attr']! as Int64List)[0], 0x20 % 10);
    expect((batch.inputs['act_mask']! as List<bool>).take(3), [
      true,
      true,
      false,
    ]);
    expect((batch.inputs['act_operation']! as Uint8List).take(2), [2, 1]);
  });

  // 验证第二玩家视角会交换双方资源位置
  test('normalizes global resources to acting player view', () {
    final state = MobileGameState()
      ..playerId = 1
      ..lp0 = 7000
      ..lp1 = 3000
      ..hand0Count = 6
      ..hand1Count = 2;

    final batch = V3FeatureEncoder().encode(state, const <DecisionCandidate>[]);
    final global = batch.inputs['global']! as Float32List;

    expect(global[3], closeTo(3000 / 8000, 0.0001));
    expect(global[4], closeTo(7000 / 8000, 0.0001));
    expect(global[5], closeTo(2 / 10, 0.0001));
    expect(global[6], closeTo(6 / 10, 0.0001));
  });

  // 验证复合选择使用 Core V3 约定的宏动作类型
  test('encodes macro operation identities', () {
    final state = MobileGameState()
      ..playerId = 0
      ..pendingAction = const PendingAction(
        type: 22,
        player: 0,
        options: <int>[],
      );
    final candidate = DecisionCandidate(
      choiceId: 0,
      label: '移除指示物',
      payload: Uint8List.fromList(const <int>[1, 0]),
    );

    final batch = V3FeatureEncoder().encode(state, <DecisionCandidate>[
      candidate,
    ]);

    expect((batch.inputs['act_operation']! as Uint8List).first, 22);
  });

  // 验证连锁的发动与触发位置不会被混写
  test('encodes separate handler and trigger chain context', () {
    final state = MobileGameState()
      ..playerId = 0
      ..chain = const <ChainLinkState>[
        ChainLinkState(
          code: 12345,
          handlerController: 0,
          handlerLocation: locationHand,
          handlerSequence: 3,
          handlerPosition: 2,
          controller: 1,
          location: locationMonster,
          sequence: 4,
          descriptionId: 77,
          chainIndex: 2,
          effectSlot: 3,
        ),
      ];

    final batch = V3FeatureEncoder().encode(state, const <DecisionCandidate>[]);
    final context = batch.inputs['c_context']! as Float32List;

    final expected = <double>[
      1,
      locationHand / 100,
      0.3,
      0.2,
      -1,
      locationMonster / 100,
      0.4,
      2 / 12,
      0.5,
    ];
    for (var index = 0; index < expected.length; index++) {
      expect(context[index], closeTo(expected[index], 0.000001));
    }
  });

  // 验证公开标记、首个超量素材和已发动效果位与 Core V3 一致
  test('encodes dynamic card flags without leaking known private cards', () {
    final state = MobileGameState()
      ..playerId = 0
      ..cards = const <VisibleCard>[
        VisibleCard(
          code: 12345,
          controller: 0,
          location: locationHand,
          sequence: 0,
          position: 0,
          publiclyVisible: true,
          overlayCodes: <int>[111, 222],
          isEquipped: true,
          usedEffectMask: 1 << 2,
        ),
      ];

    final batch = V3FeatureEncoder().encode(state, const <DecisionCandidate>[]);
    final features = batch.inputs['card_feats']! as Float32List;

    expect(features[13], 0);
    expect(features[16], 1);
    expect(features[17], 0);
    expect(features[19], 1);
    expect(
      (batch.inputs['card_overlay_idx']! as Int64List).first,
      (111 % 19990) + 10,
    );
  });

  // 验证战斗阶段候选的动作类型响应值和空阶段卡密与 Core V3 一致
  test('encodes battle command semantic responses', () {
    final raw = <int>[
      0,
      1,
      ..._littleEndian(100, 4),
      0,
      locationMonster,
      0,
      ..._littleEndian(77, 4),
      1,
      ..._littleEndian(200, 4),
      0,
      locationMonster,
      1,
      1,
      1,
      1,
    ];
    final action = PendingAction(
      type: 10,
      player: 0,
      options: const <int>[0, 1, 2, 3],
      rawPayload: raw,
    );
    final state = MobileGameState()
      ..playerId = 0
      ..pendingAction = action
      ..cards = const <VisibleCard>[
        VisibleCard(
          code: 100,
          controller: 0,
          location: locationMonster,
          sequence: 0,
          position: 1,
          publiclyVisible: true,
        ),
        VisibleCard(
          code: 200,
          controller: 0,
          location: locationMonster,
          sequence: 1,
          position: 1,
          publiclyVisible: true,
        ),
      ];

    final batch = V3FeatureEncoder().encode(
      state,
      DecisionCatalog.build(action),
    );

    expect((batch.inputs['act_type']! as Int64List).take(4), <int>[0, 1, 2, 3]);
    expect((batch.inputs['act_operation']! as Uint8List).take(4), <int>[
      15,
      13,
      17,
      17,
    ]);
    expect((batch.inputs['act_response']! as Int32List).take(4), <int>[
      0,
      2,
      0,
      0,
    ]);
    expect((batch.inputs['act_code']! as Int64List).take(4), <int>[
      110,
      210,
      0,
      0,
    ]);
    expect((batch.inputs['act_desc']! as Int64List).first, 77);
    expect(
      (batch.inputs['act_target_code']! as Int32List).take(5),
      everyElement(0),
    );
  });

  // 验证选项动作签名严格覆盖 Core V3 的固定语义字段
  test('matches core v3 option action signature', () {
    final action = const PendingAction(
      type: 14,
      player: 0,
      options: <int>[0, 1],
      optionDescriptions: <int>[101, 202],
      selectionCount: 2,
    );
    final state = MobileGameState()..pendingAction = action;
    final batch = V3FeatureEncoder().encode(
      state,
      DecisionCatalog.build(action),
    );
    final signature = batch.inputs['act_signature']! as Uint8List;
    final expected = _fnvSignature(<int>[
      14,
      3,
      1,
      202,
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
      -1,
    ]);

    expect(signature.sublist(4, 8), expected);
  });

  // 验证数字宣言按声明值而非协议索引提供给模型
  test('encodes announced number values', () {
    final raw = <int>[0, 2, ..._littleEndian(7, 4), ..._littleEndian(42, 4)];
    final action = PendingAction(
      type: 143,
      player: 0,
      options: const <int>[],
      rawPayload: raw,
    );
    final state = MobileGameState()..pendingAction = action;
    final batch = V3FeatureEncoder().encode(
      state,
      DecisionCatalog.build(action),
    );

    expect((batch.inputs['act_desc']! as Int64List).take(2), <int>[7, 42]);
    expect((batch.inputs['act_response']! as Int32List).take(2), <int>[8, 43]);
  });

  // 验证多位宣言保留数量上下文和每个被选位的紧凑目标值
  test('encodes announce mask macro context', () {
    final mask = (1 << 0) | (1 << 9);
    final raw = <int>[0, 2, ..._littleEndian(mask, 4)];
    final action = PendingAction(
      type: 140,
      player: 0,
      options: const <int>[],
      selectionMin: 2,
      selectionMax: 2,
      rawPayload: raw,
    );
    final state = MobileGameState()..pendingAction = action;
    final batch = V3FeatureEncoder().encode(
      state,
      DecisionCatalog.build(action),
    );
    final context = batch.inputs['act_context']! as Float32List;

    expect(context.take(6), <double>[0.125, 0.125, 0.125, 0, 0, 0.125]);
    expect((batch.inputs['act_target_value']! as Uint8List).take(4), <int>[
      1,
      0,
      10,
      0,
    ]);
    expect((batch.inputs['act_response']! as Int32List).first, 3);
  });
}

class _FakeCardDatabase extends CardDatabaseService {
  // 返回测试卡的固定静态规则字段
  @override
  CardMetadata? lookup(int code) {
    if (code != 12345) return null;
    return const CardMetadata(
      code: 12345,
      alias: 0,
      setcodes: <int>[0x1234, 0, 0, 0],
      type: 0x21,
      attack: 1800,
      defense: 1200,
      level: 4,
      rank: 0,
      race: 0x2000,
      attribute: 0x20,
      leftScale: 0,
      rightScale: 0,
      link: 0,
      linkMarker: 0,
      name: '测试卡',
      description: '测试效果',
    );
  }
}

// 返回任意扁平张量容器的元素数量
int dataLength(Object data) {
  if (data is List<dynamic>) return data.length;
  if (data is TypedData) {
    return data.lengthInBytes ~/ data.elementSizeInBytes;
  }
  return -1;
}

// 构建指定宽度的小端整数测试字节
List<int> _littleEndian(int value, int bytes) {
  final data = ByteData(bytes);
  if (bytes == 2) data.setUint16(0, value, Endian.little);
  if (bytes == 4) data.setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

// 按 Core V3 规则计算动作语义的四字节 FNV1a 签名
List<int> _fnvSignature(List<int> values) {
  var signature = 2166136261;
  for (final value in values) {
    signature ^= value & 0xffffffff;
    signature = (signature * 16777619) & 0xffffffff;
  }
  return List<int>.generate(
    4,
    (index) => (signature >> (index * 8)) & 0xff,
    growable: false,
  );
}
