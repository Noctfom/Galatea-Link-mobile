// Galatea Model Protocol V3 移动端特征编码器，将可见对局状态与合法响应构造成固定张量

import 'dart:typed_data';

import '../cards/card_database_service.dart';
import '../decision/decision_catalog.dart';
import '../game_state.dart';
import 'v3_semantic_store.dart';
import 'v3_tensor_spec.dart';

const int v3MaxCards = 120;
const int v3MaxDeckCards = 75;
const int v3MaxActions = 120;
const int v3ActionTargetSlots = 5;

class V3EncodedBatch {
  // 保存一次 V3 推理的全部张量数据和有效候选数量
  const V3EncodedBatch({required this.inputs, required this.candidateCount});

  final Map<String, Object> inputs;
  final int candidateCount;
}

class V3FeatureEncoder {
  // 将移动端已知状态和合法候选编码为完整 V3 输入
  V3EncodedBatch encode(
    MobileGameState state,
    List<DecisionCandidate> candidates, {
    V3SemanticStore? semanticStore,
    CardDatabaseService? cardDatabase,
  }) {
    final inputs = _createEmptyInputs();
    _encodeGlobal(inputs, state);
    _encodeCards(inputs, state, semanticStore, cardDatabase);
    _encodeDeck(inputs, state, semanticStore, cardDatabase);
    _encodeChain(inputs, state, semanticStore);
    _encodeHistory(inputs, state, semanticStore);
    _encodeActions(inputs, state, candidates, semanticStore);
    _validateInputs(inputs);
    return V3EncodedBatch(
      inputs: Map<String, Object>.unmodifiable(inputs),
      candidateCount: candidates.length.clamp(0, v3MaxActions),
    );
  }

  // 创建类型和填充值符合 V3 约定的空张量集合
  static Map<String, Object> _createEmptyInputs() {
    final result = <String, Object>{};
    for (final entry in modelProtocolV3TensorSpecs.entries) {
      final count = entry.value.elementCount;
      result[entry.key] = switch (entry.value.type) {
        V3TensorType.float32 || V3TensorType.float16 => Float32List(count),
        V3TensorType.int64 => Int64List(count),
        V3TensorType.int32 => Int32List(count),
        V3TensorType.int16 || V3TensorType.int8 => Int32List(count),
        V3TensorType.uint8 => Uint8List(count),
        V3TensorType.boolean => List<bool>.filled(count, false),
      };
      if (entry.key.endsWith('sem_req')) {
        (result[entry.key]! as Int32List).fillRange(0, count, -1);
      }
      if (entry.key == 'sem_mask' || entry.key.endsWith('_sem_mask')) {
        final mask = result[entry.key]! as List<bool>;
        for (var index = 0; index < mask.length; index += 8) {
          mask[index] = true;
        }
      }
    }
    (result['act_card_idx']! as Int64List).fillRange(
      0,
      v3MaxActions * v3ActionTargetSlots,
      v3MaxCards,
    );
    return result;
  }

  // 从当前行动玩家视角编码全局资源向量
  static void _encodeGlobal(Map<String, Object> inputs, MobileGameState state) {
    final player = state.playerId == 1 ? 1 : 0;
    final resources = <(double, double, double)>[
      (state.lp0.toDouble(), state.lp1.toDouble(), 8000),
      (state.hand0Count.toDouble(), state.hand1Count.toDouble(), 10),
      (state.deck0Count.toDouble(), state.deck1Count.toDouble(), 40),
      (state.grave0Count.toDouble(), state.grave1Count.toDouble(), 20),
      (state.removed0Count.toDouble(), state.removed1Count.toDouble(), 10),
      (state.extra0Count.toDouble(), state.extra1Count.toDouble(), 15),
    ];
    final output = inputs['global']! as Float32List;
    output[0] = (state.turn / 20).clamp(0, 5).toDouble();
    output[1] = state.phase / 10;
    output[2] = state.activePlayer == player ? 1 : 0;
    var offset = 3;
    for (final item in resources) {
      final mine = player == 0 ? item.$1 : item.$2;
      final opponent = player == 0 ? item.$2 : item.$1;
      output[offset++] = mine / item.$3;
      output[offset++] = opponent / item.$3;
    }
  }

  // 编码当前协议已经确认存在的公开或隐藏卡片实体
  static void _encodeCards(
    Map<String, Object> inputs,
    MobileGameState state,
    V3SemanticStore? semanticStore,
    CardDatabaseService? cardDatabase,
  ) {
    final indices = inputs['card_idx']! as Int64List;
    final overlayIndices = inputs['card_overlay_idx']! as Int64List;
    final races = inputs['card_race']! as Int64List;
    final attributes = inputs['card_attr']! as Int64List;
    final setcodes = inputs['card_setcodes']! as Int64List;
    final features = inputs['card_feats']! as Float32List;
    final masks = inputs['padding_mask']! as List<bool>;
    for (
      var index = 0;
      index < state.cards.length && index < v3MaxCards;
      index++
    ) {
      final card = state.cards[index];
      final visible = card.publiclyVisible && card.code != 0;
      indices[index] = visible ? _hashCode(card.code) : _hiddenCode(card);
      masks[index] = true;
      if (!visible) {
        final base = index * 66;
        features[base] = -1;
        features[base + 1] = card.location / 100;
        features[base + 2] = card.sequence / 10;
        features[base + 3] = -1;
        features[base + 4] = -1;
        continue;
      }
      final metadata = cardDatabase?.lookup(card.code);
      semanticStore?.writeCard(
        inputs: inputs,
        prefix: '',
        entityIndex: index,
        entityCapacity: v3MaxCards,
        code: card.code,
      );
      races[index] = (card.race != 0 ? card.race : metadata?.race ?? 0) % 30;
      attributes[index] =
          (card.attribute != 0 ? card.attribute : metadata?.attribute ?? 0) %
          10;
      if (metadata != null) {
        for (var slot = 0; slot < 4; slot++) {
          setcodes[index * 4 + slot] = metadata.setcodes[slot] % 4096;
        }
      }
      if (card.overlayCodes.isNotEmpty) {
        overlayIndices[index] = _hashCode(card.overlayCodes.first);
      }
      _writeCardFeatures(features, index, card, state.playerId, metadata);
    }
  }

  // 写入单张公开卡片的六十六维数值和位图特征
  static void _writeCardFeatures(
    Float32List output,
    int index,
    VisibleCard card,
    int playerId,
    CardMetadata? metadata,
  ) {
    final base = index * 66;
    final coords = _cardCoordinates(
      playerId,
      card.controller,
      card.location,
      card.sequence,
    );
    final useDatabaseStatic = card.type == 0 && metadata != null;
    final attack = useDatabaseStatic ? metadata.attack : card.attack;
    final defense = useDatabaseStatic ? metadata.defense : card.defense;
    final baseAttack = card.baseAttack != 0
        ? card.baseAttack
        : metadata?.attack ?? 0;
    final baseDefense = card.baseDefense != 0
        ? card.baseDefense
        : metadata?.defense ?? 0;
    final link = card.link != 0 ? card.link : metadata?.link ?? 0;
    final level = card.level != 0 ? card.level : metadata?.level ?? 0;
    final leftScale = card.leftScale != 0
        ? card.leftScale
        : metadata?.leftScale ?? 0;
    final rightScale = card.rightScale != 0
        ? card.rightScale
        : metadata?.rightScale ?? 0;
    final type = card.type != 0 ? card.type : metadata?.type ?? 0;
    final linkMarker = card.linkMarker != 0
        ? card.linkMarker
        : metadata?.linkMarker ?? 0;
    final numeric = <double>[
      card.controller == playerId ? 1 : -1,
      card.location / 100,
      card.sequence / 10,
      attack / 4000,
      defense / 4000,
      baseAttack / 4000,
      baseDefense / 4000,
      coords.$1,
      coords.$2,
      (link > 0 ? link : level) / 12,
      leftScale / 13,
      rightScale / 13,
      card.position / 10,
      card.isPublic || (card.position & 0x05) != 0 ? 1 : 0,
      (card.overlayCodes.length / 5).clamp(0, 1).toDouble(),
      (card.counters.values.fold<int>(0, (sum, value) => sum + value) / 10)
          .clamp(0, 1)
          .toDouble(),
      card.isEquipped ? 1 : 0,
      for (var slot = 0; slot < 8; slot++)
        (card.usedEffectMask & (1 << slot)) == 0 ? 0 : 1,
    ];
    output.setRange(base, base + numeric.length, numeric);
    for (var bit = 0; bit < 32; bit++) {
      output[base + 25 + bit] = (type & (1 << bit)) == 0 ? 0 : 1;
    }
    for (var bit = 0; bit < 9; bit++) {
      output[base + 57 + bit] = (linkMarker & (1 << bit)) == 0 ? 0 : 1;
    }
  }

  // 计算与 Core V3 一致的己方视角场地区域坐标
  static (double, double) _cardCoordinates(
    int playerId,
    int controller,
    int location,
    int sequence,
  ) {
    if (location != locationMonster && location != locationSpellTrap) {
      return (-1, -1);
    }
    final mine = controller == playerId;
    if (location == locationMonster) {
      if (sequence <= 4) {
        return (
          mine ? 0.1 + 0.2 * sequence : 0.9 - 0.2 * sequence,
          mine ? 0.3 : 0.7,
        );
      }
      if (sequence == 5) return mine ? (0.3, 0.5) : (0.7, 0.5);
      if (sequence == 6) return mine ? (0.7, 0.5) : (0.3, 0.5);
    }
    if (location == locationSpellTrap) {
      if (sequence <= 4) {
        return (
          mine ? 0.1 + 0.2 * sequence : 0.9 - 0.2 * sequence,
          mine ? 0.1 : 0.9,
        );
      }
      if (sequence == 5) return mine ? (0, 0.2) : (1, 0.8);
    }
    return (-1, -1);
  }

  // 编码己方仍在主卡组和额外卡组中的已知卡片多重集合
  static void _encodeDeck(
    Map<String, Object> inputs,
    MobileGameState state,
    V3SemanticStore? semanticStore,
    CardDatabaseService? cardDatabase,
  ) {
    final codes = <int>[
      ...state.ownRemainingDeckCodes,
      ...state.ownRemainingExtraCodes,
    ];
    final indices = inputs['deck_idx']! as Int64List;
    final races = inputs['deck_race']! as Int64List;
    final attributes = inputs['deck_attr']! as Int64List;
    final setcodes = inputs['deck_setcodes']! as Int64List;
    final masks = inputs['deck_mask']! as List<bool>;
    final visibleByCode = <int, VisibleCard>{
      for (final card in state.cards)
        if (card.code != 0) card.code: card,
    };
    for (
      var index = 0;
      index < codes.length && index < v3MaxDeckCards;
      index++
    ) {
      final code = codes[index];
      indices[index] = _hashCode(code);
      final metadata = cardDatabase?.lookup(code);
      semanticStore?.writeCard(
        inputs: inputs,
        prefix: 'd_',
        entityIndex: index,
        entityCapacity: v3MaxDeckCards,
        code: code,
      );
      final known = visibleByCode[code];
      races[index] = (metadata?.race ?? known?.race ?? 0) % 30;
      attributes[index] = (metadata?.attribute ?? known?.attribute ?? 0) % 10;
      if (metadata != null) {
        for (var slot = 0; slot < 4; slot++) {
          setcodes[index * 4 + slot] = metadata.setcodes[slot] % 4096;
        }
      }
      masks[index] = true;
    }
  }

  // 编码当前连锁堆栈的卡片身份和公开位置上下文
  static void _encodeChain(
    Map<String, Object> inputs,
    MobileGameState state,
    V3SemanticStore? semanticStore,
  ) {
    final masks = inputs['c_mask']! as List<bool>;
    final indices = inputs['c_card_idx']! as Int64List;
    final descriptions = inputs['c_desc']! as Int64List;
    final contexts = inputs['c_context']! as Float32List;
    for (var index = 0; index < state.chain.length && index < 12; index++) {
      final link = state.chain[index];
      final effectSlot =
          link.effectSlot ??
          semanticStore?.resolveEffectSlot(link.code, link.descriptionId);
      masks[index] = true;
      indices[index] = _hashCode(link.code);
      semanticStore?.writeCard(
        inputs: inputs,
        prefix: 'c_',
        entityIndex: index,
        entityCapacity: 12,
        code: link.code,
        focusedEffectSlot: effectSlot,
      );
      descriptions[index] = link.descriptionId % 1024;
      final handlerRelative = link.handlerController == state.playerId
          ? 1.0
          : -1.0;
      final triggerRelative = link.controller == state.playerId ? 1.0 : -1.0;
      final base = index * 9;
      contexts.setRange(base, base + 9, <double>[
        handlerRelative,
        link.handlerLocation / 100,
        link.handlerSequence.clamp(0, 31) / 10,
        link.handlerPosition / 10,
        triggerRelative,
        link.location / 100,
        link.sequence.clamp(0, 31) / 10,
        link.chainIndex.clamp(0, 12) / 12,
        effectSlot == null ? 0 : (effectSlot + 1) / 8,
      ]);
    }
  }

  // 编码最近八次公开发动效果的语义历史并保持最新记录在前
  static void _encodeHistory(
    Map<String, Object> inputs,
    MobileGameState state,
    V3SemanticStore? semanticStore,
  ) {
    final masks = inputs['h_mask']! as List<bool>;
    for (var index = 0; index < state.history.length && index < 8; index++) {
      final item = state.history[index];
      final effectSlot =
          item.effectSlot ??
          semanticStore?.resolveEffectSlot(item.code, item.descriptionId);
      masks[index] = true;
      semanticStore?.writeCard(
        inputs: inputs,
        prefix: 'h_',
        entityIndex: index,
        entityCapacity: 8,
        code: item.code,
        focusedEffectSlot: effectSlot,
      );
    }
  }

  // 编码最多一百二十个可以直接回传服务器的合法响应候选
  static void _encodeActions(
    Map<String, Object> inputs,
    MobileGameState state,
    List<DecisionCandidate> candidates,
    V3SemanticStore? semanticStore,
  ) {
    final action = state.pendingAction;
    if (action == null) return;
    final cardIndices = inputs['act_card_idx']! as Int64List;
    final types = inputs['act_type']! as Int64List;
    final descriptions = inputs['act_desc']! as Int64List;
    final effectSlots = inputs['act_effect_slot']! as Uint8List;
    final masks = inputs['act_mask']! as List<bool>;
    final races = inputs['act_race']! as Int64List;
    final attributes = inputs['act_attr']! as Int64List;
    final codes = inputs['act_code']! as Int64List;
    final places = inputs['act_place']! as Int64List;
    final operations = inputs['act_operation']! as Uint8List;
    final responses = inputs['act_response']! as Int32List;
    final signatures = inputs['act_signature']! as Uint8List;
    final contexts = inputs['act_context']! as Float32List;
    final targetCodes = inputs['act_target_code']! as Int32List;
    final targetValues = inputs['act_target_value']! as Uint8List;
    final controllers = inputs['act_controller']! as Uint8List;
    final locations = inputs['act_location']! as Uint8List;
    final sequences = inputs['act_sequence']! as Uint8List;

    for (
      var index = 0;
      index < candidates.length && index < v3MaxActions;
      index++
    ) {
      final candidate = candidates[index];
      final details = candidate.details;
      final response = _candidateResponseValue(action, candidate);
      final operation = _candidateOperation(action, candidate, response);
      final code = _detailInt(details, 'code') ?? action.code ?? 0;
      final description = _candidateDescription(action, details);
      final effectSlot = semanticStore?.resolveEffectSlot(code, description);
      final targets = _candidateTargets(details);
      final targetLocations = targets
          .map((target) => _findEntityIndex(state.cards, target))
          .take(v3ActionTargetSlots)
          .toList(growable: false);
      for (var slot = 0; slot < targetLocations.length; slot++) {
        cardIndices[index * v3ActionTargetSlots + slot] = targetLocations[slot];
      }
      types[index] = _candidateActionType(action, details);
      descriptions[index] = description % 1024;
      effectSlots[index] = effectSlot == null ? 0 : effectSlot + 1;
      masks[index] = true;
      if (action.type == 140 && description > 0) {
        races[index] = (description.bitLength - 1) % 30;
      }
      if (action.type == 141 && description > 0) {
        attributes[index] = (description.bitLength - 1) % 10;
      }
      codes[index] = code == 0 ? 0 : _hashCode(code);
      operations[index] = operation;
      responses[index] = _hashActionResponse(response);
      _writeActionSignature(
        signatures,
        index,
        state,
        action,
        candidate,
        operation,
        response,
        code,
        description,
      );
      final contextBase = index * 6;
      contexts.setRange(contextBase, contextBase + 6, <double>[
        _scaleContext(action.selectionMin),
        _scaleContext(action.selectionMax),
        _scaleContext(_selectionCount(candidate, action)),
        action.finishable ? 1 : 0,
        action.cancelable ? 1 : 0,
        _scaleContext(_actionContextValue(action)),
      ]);
      _writeTargetData(
        targetCodes,
        targetValues,
        index,
        action,
        targets,
        details,
      );
      _writeTargetLocation(
        controllers,
        locations,
        sequences,
        index,
        state.playerId,
        targets.firstOrNull,
      );
      _writePlaces(places, index, state.playerId, details);
    }
  }

  // 返回候选在 Core V3 中使用的动作类型
  static int _candidateActionType(
    PendingAction action,
    Map<String, Object?> details,
  ) {
    if (action.type == 10 || action.type == 11) {
      return _detailInt(details, 'category') ?? action.type;
    }
    return action.type;
  }

  // 从候选协议载荷提取模型使用的语义响应值
  static int? _candidateResponseValue(
    PendingAction action,
    DecisionCandidate candidate,
  ) {
    final detailed = _detailInt(candidate.details, 'response_value');
    if (detailed != null) return detailed;
    final payload = candidate.payload;
    if (action.type == 19 && payload.length == 1) return payload[0];
    if (action.type == 26 && payload.length == 2) return payload[1];
    if (action.type == 143) {
      return _detailInt(candidate.details, 'value');
    }
    if ((action.type == 12 ||
            action.type == 13 ||
            action.type >= 140 && action.type <= 142) &&
        payload.length == 4) {
      return ByteData.sublistView(payload).getInt32(0, Endian.little);
    }
    return null;
  }

  // 将候选语义映射到 Core V3 的操作枚举
  static int _candidateOperation(
    PendingAction action,
    DecisionCandidate candidate,
    int? response,
  ) {
    if (action.type == 12 || action.type == 13) return response == 1 ? 1 : 2;
    if (action.type == 14) return 3;
    if (action.type == 15 || action.type == 20 || action.type == 23) {
      return candidate.payload.length == 4 &&
              candidate.payload.every((value) => value == 0xff)
          ? 7
          : 20;
    }
    if (action.type == 21 || action.type == 25) return 21;
    if (action.type == 22) return 22;
    if (action.type == 16) {
      return candidate.details['cancel'] == true ? 7 : 16;
    }
    if (action.type == 18 || action.type == 24) return 18;
    if (action.type == 19) {
      return const <int, int>{1: 8, 2: 9, 4: 10, 8: 11}[response] ?? 0;
    }
    if (action.type == 26) {
      if (candidate.payload.length == 2) return 4;
      return action.finishable ? 6 : 7;
    }
    if (action.type >= 140 && action.type <= 143) return 19;
    if (action.type == 10 || action.type == 11) {
      final category = _detailInt(candidate.details, 'category') ?? -1;
      if (action.type == 10) {
        if (category == 0) return 15;
        if (category == 1) {
          return candidate.details['direct_attack'] == true ? 13 : 14;
        }
        return 17;
      }
      if (category <= 5) return 15;
      if (category == 8) return 12;
      return 17;
    }
    return 0;
  }

  // 收集候选携带的单卡或多卡目标信息
  static List<Map<String, Object?>> _candidateTargets(
    Map<String, Object?> details,
  ) {
    final rawCards = details['cards'];
    if (rawCards is List) {
      return rawCards
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList(growable: false);
    }
    if (details.containsKey('controller') &&
        details.containsKey('location') &&
        details.containsKey('sequence')) {
      return <Map<String, Object?>>[details];
    }
    return const <Map<String, Object?>>[];
  }

  // 查找候选目标在卡片实体表中的索引并使用哨兵表示缺失
  static int _findEntityIndex(
    List<VisibleCard> cards,
    Map<String, Object?> target,
  ) {
    final controller = _detailInt(target, 'controller');
    final location = _detailInt(target, 'location');
    final sequence = _detailInt(target, 'sequence');
    final index = cards.indexWhere(
      (card) =>
          card.controller == controller &&
          card.location == location &&
          card.sequence == sequence,
    );
    return index < 0 || index >= v3MaxCards ? v3MaxCards : index;
  }

  // 写入候选目标卡号和紧凑数值字段
  static void _writeTargetData(
    Int32List targetCodes,
    Uint8List targetValues,
    int actionIndex,
    PendingAction action,
    List<Map<String, Object?>> targets,
    Map<String, Object?> details,
  ) {
    if (!_isMacroAction(action.type)) return;
    for (
      var slot = 0;
      slot < targets.length && slot < v3ActionTargetSlots;
      slot++
    ) {
      final target = targets[slot];
      final code = _detailInt(target, 'code') ?? 0;
      targetCodes[actionIndex * v3ActionTargetSlots + slot] = code == 0
          ? 0
          : _hashCode(code);
      final rawValue =
          _detailInt(target, 'position_or_value') ??
          _detailInt(target, 'position') ??
          0;
      final valueBase = (actionIndex * v3ActionTargetSlots + slot) * 2;
      targetValues[valueBase] = (rawValue & 0xffff).clamp(0, 255).toInt();
      targetValues[valueBase + 1] = ((rawValue >> 16) & 0xffff)
          .clamp(0, 255)
          .toInt();
    }
    final rawTargetValues = details['target_values'];
    if (rawTargetValues is List) {
      for (
        var slot = 0;
        slot < rawTargetValues.length && slot < v3ActionTargetSlots;
        slot++
      ) {
        final rawValue = rawTargetValues[slot];
        if (rawValue is! num) continue;
        final value = rawValue.toInt() & 0xffffffff;
        final valueBase = (actionIndex * v3ActionTargetSlots + slot) * 2;
        targetValues[valueBase] = (value & 0xffff).clamp(0, 255).toInt();
        targetValues[valueBase + 1] = ((value >> 16) & 0xffff)
            .clamp(0, 255)
            .toInt();
      }
    }
  }

  // 写入第一个候选目标的相对控制者区域和序号
  static void _writeTargetLocation(
    Uint8List controllers,
    Uint8List locations,
    Uint8List sequences,
    int actionIndex,
    int playerId,
    Map<String, Object?>? target,
  ) {
    if (target == null) return;
    final controller = _detailInt(target, 'controller');
    final location = _detailInt(target, 'location');
    final sequence = _detailInt(target, 'sequence');
    if (controller == null || location == null || sequence == null) return;
    controllers[actionIndex] = controller == playerId ? 1 : 2;
    locations[actionIndex] = location == 0 ? 0 : location.bitLength.clamp(0, 8);
    sequences[actionIndex] = sequence.clamp(0, 31) + 1;
  }

  // 写入区域选择候选的原始场地索引
  static void _writePlaces(
    Int64List places,
    int actionIndex,
    int playerId,
    Map<String, Object?> details,
  ) {
    final rawPlaces = details['places'];
    if (rawPlaces is! List) return;
    var slot = 0;
    for (final raw in rawPlaces.whereType<Map>()) {
      if (slot >= v3ActionTargetSlots) break;
      final place = raw.cast<String, Object?>();
      final controller = _detailInt(place, 'player') ?? playerId;
      final location = _detailInt(place, 'location') ?? 0;
      final sequence = _detailInt(place, 'sequence') ?? 0;
      final opponentOffset = controller == playerId ? 0 : 16;
      final zoneOffset = location == locationSpellTrap ? 8 : 0;
      places[actionIndex * v3ActionTargetSlots + slot] =
          opponentOffset + zoneOffset + sequence;
      slot++;
    }
  }

  // 计算候选完成后的选择数量
  static int _selectionCount(
    DecisionCandidate candidate,
    PendingAction action,
  ) {
    final cards = candidate.details['cards'];
    if (cards is List) return cards.length;
    final places = candidate.details['places'];
    if (places is List) return places.length;
    final bits = candidate.details['bits'];
    if (bits is List) return bits.length;
    return action.selectionCount;
  }

  // 生成与 Core 相同的 FNV1a 四字节动作签名
  static void _writeActionSignature(
    Uint8List output,
    int actionIndex,
    MobileGameState state,
    PendingAction action,
    DecisionCandidate candidate,
    int operation,
    int? response,
    int code,
    int description,
  ) {
    final contextValue = _actionContextValue(action);
    final promptFlags = _actionPromptFlags(action, candidate.details);
    final promptValue = _actionPromptValue(action, 4);
    final promptValue2 = _actionPromptValue(action, 8);
    final decisionValue = action.type == 140 || action.type == 141
        ? response
        : null;
    final values = <int>[
      _candidateActionType(action, candidate.details),
      operation,
      response ?? -1,
      description,
      code,
      action.selectionMin,
      action.selectionMax,
      _selectionCount(candidate, action),
      action.finishable ? 1 : 0,
      action.cancelable ? 1 : 0,
      contextValue,
      promptFlags,
      promptValue,
      promptValue2,
      decisionValue ?? -1,
    ];
    if (_isMacroAction(action.type)) {
      values.addAll(candidate.payload);
    }
    final macroLocations = _macroTargetLocations(action, candidate.details);
    values.addAll(_macroTargetEntityIndices(state, action, candidate.details));
    values.addAll(_macroTargetCodes(action, candidate.details));
    values.addAll(_macroTargetValues(action, candidate.details));
    values.addAll(macroLocations);
    values.addAll(_macroPlaces(candidate.details, action.player));
    var signature = 2166136261;
    for (final value in values) {
      signature ^= value & 0xffffffff;
      signature = (signature * 16777619) & 0xffffffff;
    }
    final base = actionIndex * 4;
    for (var byte = 0; byte < 4; byte++) {
      output[base + byte] = (signature >> (byte * 8)) & 0xff;
    }
  }

  // 返回候选在 V3 动作描述字段中使用的语义编号
  static int _candidateDescription(
    PendingAction action,
    Map<String, Object?> details,
  ) {
    if (action.type == 142) return _detailInt(details, 'code') ?? 0;
    if (action.type == 143) return _detailInt(details, 'value') ?? 0;
    return _detailInt(details, 'description_id') ?? action.descriptionId ?? 0;
  }

  // 从交互头读取 Core V3 使用的动作上下文值
  static int _actionContextValue(PendingAction action) {
    final raw = Uint8List.fromList(action.rawPayload);
    if (action.type == 16 && raw.length >= 3) return raw[2];
    if (action.type == 22 && raw.length >= 5) {
      return ByteData.sublistView(raw).getUint16(3, Endian.little);
    }
    if ((action.type == 140 || action.type == 141) && raw.length >= 2) {
      return raw[1];
    }
    return 0;
  }

  // 从连锁候选读取效果标记与强制响应位
  static int _actionPromptFlags(
    PendingAction action,
    Map<String, Object?> details,
  ) {
    if (action.type != 16 || details['cancel'] == true) return 0;
    final raw = Uint8List.fromList(action.rawPayload);
    if (raw.length < 4) return 0;
    return (_detailInt(details, 'effect_flag') ?? 0) | (raw[3] << 8);
  }

  // 从连锁交互头读取时点提示值
  static int _actionPromptValue(PendingAction action, int offset) {
    if (action.type != 16 || action.rawPayload.length < offset + 4) return 0;
    final raw = Uint8List.fromList(action.rawPayload);
    return ByteData.sublistView(raw).getUint32(offset, Endian.little);
  }

  // 生成宏动作中与实体对应的原始位置值
  static List<int> _macroTargetLocations(
    PendingAction action,
    Map<String, Object?> details,
  ) {
    if (!const <int>{15, 20, 22, 23, 25}.contains(action.type)) {
      return const <int>[];
    }
    return _candidateTargets(details)
        .map((target) {
          final controller = _detailInt(target, 'controller') ?? 0;
          final location = _detailInt(target, 'location') ?? 0;
          final sequence = _detailInt(target, 'sequence') ?? 0;
          final position = action.type == 15
              ? _detailInt(target, 'position_or_value') ?? 0
              : 0;
          return controller |
              (location << 8) |
              (sequence << 16) |
              (position << 24);
        })
        .toList(growable: false);
  }

  // 返回宏动作映射到当前快照后的实体索引
  static List<int> _macroTargetEntityIndices(
    MobileGameState state,
    PendingAction action,
    Map<String, Object?> details,
  ) {
    if (!const <int>{15, 20, 22, 23, 25}.contains(action.type)) {
      return const <int>[];
    }
    return _candidateTargets(details)
        .map((target) {
          final controller = _detailInt(target, 'controller');
          final location = _detailInt(target, 'location');
          final sequence = _detailInt(target, 'sequence');
          return state.cards.indexWhere(
            (card) =>
                card.controller == controller &&
                card.location == location &&
                card.sequence == sequence,
          );
        })
        .toList(growable: false);
  }

  // 返回宏动作完整目标卡密序列
  static List<int> _macroTargetCodes(
    PendingAction action,
    Map<String, Object?> details,
  ) {
    if (!const <int>{15, 20, 22, 23, 25}.contains(action.type)) {
      return const <int>[];
    }
    return _candidateTargets(
      details,
    ).map((target) => _detailInt(target, 'code') ?? 0).toList(growable: false);
  }

  // 返回宏动作显式携带的卡片数值序列
  static List<int> _macroTargetValues(
    PendingAction action,
    Map<String, Object?> details,
  ) {
    final explicit = details['target_values'];
    if (explicit is List) {
      return explicit.whereType<num>().map((value) => value.toInt()).toList();
    }
    final targets = _candidateTargets(details);
    if (action.type == 15) return List<int>.filled(targets.length, 0);
    if (const <int>{20, 22, 23}.contains(action.type)) {
      return targets
          .map((target) => _detailInt(target, 'position_or_value') ?? 0)
          .toList(growable: false);
    }
    return const <int>[];
  }

  // 把宏动作区域详情还原为 Core 使用的零到三十一索引
  static List<int> _macroPlaces(Map<String, Object?> details, int player) {
    final rawPlaces = details['places'];
    if (rawPlaces is! List) return const <int>[];
    return rawPlaces
        .whereType<Map>()
        .map((raw) {
          final place = raw.cast<String, Object?>();
          final controller = _detailInt(place, 'player') ?? player;
          final location = _detailInt(place, 'location') ?? 0;
          final sequence = _detailInt(place, 'sequence') ?? 0;
          return (controller == player ? 0 : 16) |
              (location == locationSpellTrap ? 8 : 0) |
              sequence;
        })
        .toList(growable: false);
  }

  // 判断交互是否由最终组合候选直接交给模型选择
  static bool _isMacroAction(int type) {
    return const <int>{15, 18, 20, 22, 23, 24, 25, 140, 141}.contains(type);
  }

  // 将任意响应稳定映射到模型响应词表并保留零作为空值
  static int _hashActionResponse(int? value) {
    if (value == null) return 0;
    return 1 + ((value & 0xffffffff) % 511);
  }

  // 压缩动作数量约束到模型训练使用的安全范围
  static double _scaleContext(int value) {
    return (value / 16).clamp(-4, 4).toDouble();
  }

  // 将卡号映射到模型卡片词表
  static int _hashCode(int code) {
    if (code == 0) return 1;
    return (code % 19990) + 10;
  }

  // 返回不同隐藏区域使用的匿名卡片标识
  static int _hiddenCode(VisibleCard card) {
    if (card.location == locationHand) return 2;
    if (card.location == locationSpellTrap) return 3;
    return 1;
  }

  // 安全读取候选详情中的整数
  static int? _detailInt(Map<String, Object?> details, String key) {
    final value = details[key];
    return value is num ? value.toInt() : null;
  }

  // 校验每个输入张量都存在且元素数量准确
  static void _validateInputs(Map<String, Object> inputs) {
    if (inputs.keys
            .toSet()
            .difference(modelProtocolV3TensorSpecs.keys.toSet())
            .isNotEmpty ||
        modelProtocolV3TensorSpecs.keys
            .toSet()
            .difference(inputs.keys.toSet())
            .isNotEmpty) {
      throw const FormatException('V3 编码器输入签名不完整');
    }
    for (final entry in modelProtocolV3TensorSpecs.entries) {
      final data = inputs[entry.key]!;
      final length = switch (data) {
        List<dynamic> value => value.length,
        TypedData value => value.lengthInBytes ~/ value.elementSizeInBytes,
        _ => -1,
      };
      if (length != entry.value.elementCount) {
        throw FormatException(
          'V3 张量 ${entry.key} 元素数错误 actual=$length expected=${entry.value.elementCount}',
        );
      }
    }
  }
}
