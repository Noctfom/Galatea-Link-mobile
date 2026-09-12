// V3 移动端语义缓存测试，验证 JSON 编译、字段映射和重复加载

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galatea_link_mobile/src/decision/decision_catalog.dart';
import 'package:galatea_link_mobile/src/game_state.dart';
import 'package:galatea_link_mobile/src/models/v3_feature_encoder.dart';
import 'package:galatea_link_mobile/src/models/v3_semantic_store.dart';

void main() {
  // 验证语义 JSON 会按 Core V3 词表顺序写入固定张量
  test('compiles and writes semantic tensors', () async {
    final directory = await Directory.systemTemp.createTemp('galatea_sem_');
    addTearDown(() => directory.delete(recursive: true));
    await _writeFixture(directory);
    final store = await V3SemanticStore.open(directory.path);
    expect(store, isNotNull);
    expect(store!.recordCount, 1);
    expect(store.bindingCount, 1);
    expect(store.resolveEffectSlot(100, 77), 2);
    expect(store.resolveEffectSlot(100, 78), isNull);

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
      ]
      ..setOwnDeck(const <int>[100], const <int>[]);
    final batch = V3FeatureEncoder().encode(
      state,
      const [],
      semanticStore: store,
    );
    final categories = batch.inputs['sem_category']! as Int32List;
    final requirements = batch.inputs['sem_req']! as Int32List;
    final setcodes = batch.inputs['sem_setcode']! as Int32List;
    final numbers = batch.inputs['sem_number']! as Float32List;
    final references = batch.inputs['sem_ref']! as Int32List;
    final races = batch.inputs['sem_race']! as Int32List;
    final attributes = batch.inputs['sem_attr']! as Int32List;
    final codeIndices = batch.inputs['sem_code_idx']! as Int64List;
    final masks = batch.inputs['sem_mask']! as List<bool>;

    expect(categories[0], 2);
    expect(categories[16], 3);
    expect(requirements[0], 0);
    expect(setcodes[0], 0x234);
    expect(numbers[0], closeTo(1, 0.0001));
    expect(references[0], 12355);
    expect(races[0], 0x2000 % 30);
    expect(attributes[0], 0x20 % 10);
    expect(codeIndices[0], 5);
    expect(codeIndices[2], 9);
    expect(masks.take(4), <bool>[true, false, true, false]);
    expect((batch.inputs['d_sem_category']! as Int32List)[0], 2);
  });

  // 验证第二次打开直接复用完整缓存并保留未知卡兜底掩码
  test('reuses cache and keeps unknown fallback mask', () async {
    final directory = await Directory.systemTemp.createTemp('galatea_sem_');
    addTearDown(() => directory.delete(recursive: true));
    await _writeFixture(directory);
    await V3SemanticStore.open(directory.path);
    final cache = File(
      '${directory.path}${Platform.pathSeparator}mobile_semantics_v1.bin',
    );
    final modified = cache.lastModifiedSync();
    final store = await V3SemanticStore.open(directory.path);
    expect(cache.lastModifiedSync(), modified);

    final state = MobileGameState()
      ..cards = const <VisibleCard>[
        VisibleCard(
          code: 999,
          controller: 0,
          location: locationMonster,
          sequence: 0,
          position: 1,
          publiclyVisible: true,
        ),
      ];
    final batch = V3FeatureEncoder().encode(
      state,
      const [],
      semanticStore: store,
    );
    expect((batch.inputs['sem_mask']! as List<bool>).take(8), <bool>[
      true,
      false,
      false,
      false,
      false,
      false,
      false,
      false,
    ]);
  });

  // 验证最近效果历史会写入 V3 历史语义张量
  test('writes recent effect history semantic tensors', () async {
    final directory = await Directory.systemTemp.createTemp('galatea_sem_');
    addTearDown(() => directory.delete(recursive: true));
    await _writeFixture(directory);
    final store = await V3SemanticStore.open(directory.path);
    final state = MobileGameState()
      ..history = const <RecentEffectState>[
        RecentEffectState(code: 100, descriptionId: 77),
      ]
      ..pendingAction = const PendingAction(
        type: 12,
        player: 0,
        options: <int>[0, 1],
        code: 100,
        descriptionId: 77,
      );

    final batch = V3FeatureEncoder().encode(
      state,
      DecisionCatalog.build(state.pendingAction!),
      semanticStore: store,
    );

    expect((batch.inputs['h_mask']! as List<bool>).take(2), [true, false]);
    final effectMasks = batch.inputs['h_sem_mask']! as List<bool>;
    expect(effectMasks.take(8), [
      false,
      false,
      true,
      false,
      false,
      false,
      false,
      false,
    ]);
    expect((batch.inputs['h_sem_category']! as Int32List)[16], 3);
    expect(
      (batch.inputs['act_effect_slot']! as Uint8List).take(2),
      orderedEquals(<int>[3, 3]),
    );
  });

  // 在显式提供目录时校验真实稳定版语义资产可以完整编译
  test('compiles real semantic assets when configured', () async {
    final realDirectory = Platform.environment['REAL_SEMANTIC_DIR'];
    if (realDirectory == null || realDirectory.isEmpty) return;
    final stopwatch = Stopwatch()..start();
    final store = await V3SemanticStore.open(realDirectory);
    stopwatch.stop();
    expect(store, isNotNull);
    expect(store!.recordCount, greaterThan(10000));
    expect(store.byteLength, greaterThan(7 * 1024 * 1024));
    expect(stopwatch.elapsed, lessThan(const Duration(minutes: 2)));
  });
}

// 写入覆盖常用 V3 语义字段的最小测试资产
Future<void> _writeFixture(Directory directory) async {
  final knowledge = <String, Object?>{
    '100': <String, Object?>{
      'effects': <Object?>[
        <String, Object?>{
          'slot': 1,
          'categories': <String>['DRAW'],
          'requirements': <String, Object?>{
            'locations': <String>['LOCATION_HAND'],
            'setcodes': <String>['0x1234'],
            'races': <String>['RACE_DRAGON'],
            'attributes': <String>['ATTRIBUTE_DARK'],
            'custom_numbers': <num>[4000, 12345],
          },
        },
        <String, Object?>{
          'slot': 3,
          'categories': <String>['DESTROY'],
          'requirements': <String, Object?>{},
          'runtime_desc_ids': <int>[77],
        },
      ],
    },
  };
  await File(
    '${directory.path}${Platform.pathSeparator}knowledge_base.json',
  ).writeAsString(jsonEncode(knowledge));
  await File(
    '${directory.path}${Platform.pathSeparator}code_embeddings_idx.json',
  ).writeAsString(jsonEncode(<String, int>{'100_0': 4, '100_2': 8}));
}
