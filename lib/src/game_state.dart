// 移动端可见决斗状态，维护回合、生命值、场地区域、连锁和交互时点

import 'dart:math';
import 'dart:typed_data';

import 'game_protocol/byte_cursor.dart';
import 'game_protocol/card_query_parser.dart';
import 'game_protocol/ocg_parser.dart';

const int locationDeck = 0x01;
const int locationHand = 0x02;
const int locationMonster = 0x04;
const int locationSpellTrap = 0x08;
const int locationGrave = 0x10;
const int locationRemoved = 0x20;
const int locationExtra = 0x40;
const int locationOverlay = 0x80;

class VisibleCard {
  const VisibleCard({
    required this.code,
    required this.controller,
    required this.location,
    required this.sequence,
    required this.position,
    required this.publiclyVisible,
    this.alias = 0,
    this.type = 0,
    this.level = 0,
    this.rank = 0,
    this.attribute = 0,
    this.race = 0,
    this.attack = 0,
    this.defense = 0,
    this.baseAttack = 0,
    this.baseDefense = 0,
    this.reason = 0,
    this.owner,
    this.status = 0,
    this.isPublic = false,
    this.leftScale = 0,
    this.rightScale = 0,
    this.link = 0,
    this.linkMarker = 0,
    this.isHidden = false,
    this.cover = 0,
    this.reasonCard,
    this.equipCard,
    this.targetCards = const <CardLocationReference>[],
    this.overlayCodes = const <int>[],
    this.counters = const <int, int>{},
    this.isEquipped = false,
    this.usedEffectMask = 0,
  });

  final int code;
  final int controller;
  final int location;
  final int sequence;
  final int position;
  final bool publiclyVisible;
  final int alias;
  final int type;
  final int level;
  final int rank;
  final int attribute;
  final int race;
  final int attack;
  final int defense;
  final int baseAttack;
  final int baseDefense;
  final int reason;
  final int? owner;
  final int status;
  final bool isPublic;
  final int leftScale;
  final int rightScale;
  final int link;
  final int linkMarker;
  final bool isHidden;
  final int cover;
  final CardLocationReference? reasonCard;
  final CardLocationReference? equipCard;
  final List<CardLocationReference> targetCards;
  final List<int> overlayCodes;
  final Map<int, int> counters;
  final bool isEquipped;
  final int usedEffectMask;

  // 复制卡片状态并替换位置或可见性字段
  VisibleCard copyWith({
    int? code,
    int? controller,
    int? location,
    int? sequence,
    int? position,
    bool? publiclyVisible,
    bool? isEquipped,
    int? usedEffectMask,
    Map<int, int>? counters,
  }) {
    return VisibleCard(
      code: code ?? this.code,
      controller: controller ?? this.controller,
      location: location ?? this.location,
      sequence: sequence ?? this.sequence,
      position: position ?? this.position,
      publiclyVisible: publiclyVisible ?? this.publiclyVisible,
      alias: alias,
      type: type,
      level: level,
      rank: rank,
      attribute: attribute,
      race: race,
      attack: attack,
      defense: defense,
      baseAttack: baseAttack,
      baseDefense: baseDefense,
      reason: reason,
      owner: owner,
      status: status,
      isPublic: isPublic,
      leftScale: leftScale,
      rightScale: rightScale,
      link: link,
      linkMarker: linkMarker,
      isHidden: isHidden,
      cover: cover,
      reasonCard: reasonCard,
      equipCard: equipCard,
      targetCards: targetCards,
      overlayCodes: overlayCodes,
      counters: counters ?? this.counters,
      isEquipped: isEquipped ?? this.isEquipped,
      usedEffectMask: usedEffectMask ?? this.usedEffectMask,
    );
  }
}

class ChainLinkState {
  const ChainLinkState({
    required this.code,
    required this.handlerController,
    required this.handlerLocation,
    required this.handlerSequence,
    required this.handlerPosition,
    required this.controller,
    required this.location,
    required this.sequence,
    required this.descriptionId,
    required this.chainIndex,
    this.effectSlot,
  });

  final int code;
  final int handlerController;
  final int handlerLocation;
  final int handlerSequence;
  final int handlerPosition;
  final int controller;
  final int location;
  final int sequence;
  final int descriptionId;
  final int chainIndex;
  final int? effectSlot;
}

// 保存最近一次公开发动的卡片和效果描述以构造 V3 历史张量
class RecentEffectState {
  const RecentEffectState({
    required this.code,
    required this.descriptionId,
    this.effectSlot,
  });

  final int code;
  final int descriptionId;
  final int? effectSlot;
}

class PendingAction {
  const PendingAction({
    required this.type,
    required this.player,
    required this.options,
    this.descriptionId,
    this.code,
    this.selectionCount = 0,
    this.optionDescriptions = const <int>[],
    this.selectionMin = 0,
    this.selectionMax = 0,
    this.cancelable = false,
    this.finishable = false,
    this.rawPayload = const <int>[],
  });

  final int type;
  final int player;
  final List<int> options;
  final int? descriptionId;
  final int? code;
  final int selectionCount;
  final List<int> optionDescriptions;
  final int selectionMin;
  final int selectionMax;
  final bool cancelable;
  final bool finishable;
  final List<int> rawPayload;
}

class MobileGameState {
  int turn = 0;
  int phase = 0;
  int activePlayer = 0;
  int playerId = 0;
  int lp0 = 8000;
  int lp1 = 8000;
  bool duelStarted = false;
  int deck0Count = 0;
  int deck1Count = 0;
  int hand0Count = 0;
  int hand1Count = 0;
  int grave0Count = 0;
  int grave1Count = 0;
  int removed0Count = 0;
  int removed1Count = 0;
  int extra0Count = 0;
  int extra1Count = 0;
  List<int> ownInitialDeckCodes = const <int>[];
  List<int> ownInitialExtraCodes = const <int>[];
  List<int> ownRemainingDeckCodes = const <int>[];
  List<int> ownRemainingExtraCodes = const <int>[];
  List<VisibleCard> cards = const <VisibleCard>[];
  List<ChainLinkState> chain = const <ChainLinkState>[];
  List<RecentEffectState> history = const <RecentEffectState>[];
  PendingAction? pendingAction;
  bool retryRequested = false;
  List<int> lastBatchTypes = const <int>[];
  int lastBatchNormalizedCoreGhostCount = 0;
  String? lastError;

  // 重置单局状态并清除旧对局残留的动作和可见信息
  void reset() {
    turn = 0;
    phase = 0;
    activePlayer = 0;
    playerId = 0;
    lp0 = 8000;
    lp1 = 8000;
    duelStarted = false;
    deck0Count = 0;
    deck1Count = 0;
    hand0Count = 0;
    hand1Count = 0;
    grave0Count = 0;
    grave1Count = 0;
    removed0Count = 0;
    removed1Count = 0;
    extra0Count = 0;
    extra1Count = 0;
    ownInitialDeckCodes = const <int>[];
    ownInitialExtraCodes = const <int>[];
    ownRemainingDeckCodes = const <int>[];
    ownRemainingExtraCodes = const <int>[];
    cards = const <VisibleCard>[];
    chain = const <ChainLinkState>[];
    history = const <RecentEffectState>[];
    pendingAction = null;
    retryRequested = false;
    lastBatchTypes = const <int>[];
    lastBatchNormalizedCoreGhostCount = 0;
    lastError = null;
  }

  // 设置仅供本地推理使用的己方初始主卡组和额外卡组
  void setOwnDeck(List<int> mainDeck, List<int> extraDeck) {
    ownInitialDeckCodes = List<int>.unmodifiable(mainDeck);
    ownInitialExtraCodes = List<int>.unmodifiable(extraDeck);
    ownRemainingDeckCodes = List<int>.unmodifiable(mainDeck);
    ownRemainingExtraCodes = List<int>.unmodifiable(extraDeck);
  }

  // 同步当前完整交互帧对应的 Core 玩家视角
  void assignPlayerPerspective(int value) {
    if (value != 0 && value != 1) {
      throw const YgoProtocolException('Core 玩家编号必须为 0 或 1');
    }
    playerId = value;
  }

  // 应用一条已经严格切分的 OCG 消息
  void apply(
    OcgMessage message, {
    int? Function(int code, int runtimeDescription)? effectSlotResolver,
  }) {
    try {
      if (!ocgInteractionTypes.contains(message.type) && message.type != 1) {
        pendingAction = null;
      }
      final cursor = ByteCursor(message.payload);
      switch (message.type) {
        case 1:
          retryRequested = true;
          break;
        case 4:
          _applyStart(cursor);
          break;
        case 6:
          _applyUpdateData(cursor);
          break;
        case 7:
          _applyUpdateCard(cursor);
          break;
        case 40:
          activePlayer = cursor.readUint8();
          turn += 1;
          cards = List<VisibleCard>.unmodifiable(
            cards.map((card) => card.copyWith(usedEffectMask: 0)),
          );
          pendingAction = null;
          break;
        case 41:
          phase = cursor.readUint16Le();
          break;
        case 50:
          _applyMove(cursor);
          break;
        case 53:
          _applyPositionChange(cursor);
          break;
        case 70:
          _applyChaining(cursor, effectSlotResolver);
          break;
        case 74:
          chain = const <ChainLinkState>[];
          break;
        case 90:
          _applyDraw(cursor);
          break;
        case 91:
          _applyLpDelta(cursor, damage: true);
          break;
        case 92:
          _applyLpDelta(cursor, damage: false);
          break;
        case 100:
          _applyLpDelta(cursor, damage: true);
          break;
        case 93:
          _applyEquip(cursor);
          break;
        case 94:
          _applyLpUpdate(cursor);
          break;
        case 101:
          _applyCounter(cursor, add: true);
          break;
        case 102:
          _applyCounter(cursor, add: false);
          break;
        case 13:
          _applyYesNo(cursor, message.type, message.payload);
          break;
        case 14:
          _applyOption(cursor);
          break;
        case 18:
        case 24:
          _applyPlace(cursor, message.type);
          break;
        case 19:
          _applyPositionPrompt(cursor);
          break;
        case 12:
          _applyEffectYesNo(cursor, message.type, message.payload);
          break;
        case 10:
          _applyBattleCommand(cursor, message.payload);
          break;
        case 11:
          _applyIdleCommand(cursor, message.payload);
          break;
        case 15:
        case 20:
          _applySelectCards(cursor, message.type, message.payload);
          break;
        case 21:
          _applySortCards(cursor, message.type, message.payload);
          break;
        case 16:
          _applySelectChain(cursor, message.payload);
          break;
        case 25:
          _applySortCards(cursor, message.type, message.payload);
          break;
        case 26:
          _applyUnselect(cursor, message.payload);
          break;
        case 22:
          _applyRawInteraction(cursor, message, playerOffset: 0);
          break;
        case 23:
          _applyRawInteraction(cursor, message, playerOffset: 1);
          break;
        case 140:
        case 141:
        case 142:
        case 143:
          _applyRawInteraction(cursor, message, playerOffset: 0);
          break;
        default:
          cursor.readBytes(cursor.remaining);
          break;
      }
      cursor.requireEnd();
      lastError = null;
    } catch (error) {
      lastError = 'OCG Type ${message.type} 解析失败: $error';
      pendingAction = null;
      rethrow;
    }
  }

  // 应用连续 OCG 消息并在错位时拒绝整批数据
  void applyBatch(
    List<int> payload, {
    int? Function(int code, int runtimeDescription)? effectSlotResolver,
  }) {
    final parsed = OcgParser.parse(payload);
    retryRequested = false;
    lastBatchTypes =
        parsed.map((message) => message.type).toList(growable: false);
    lastBatchNormalizedCoreGhostCount =
        parsed.where((message) => message.normalizedCoreGhost).length;
    for (final message in parsed) {
      apply(message, effectSlotResolver: effectSlotResolver);
    }
  }

  // 返回玩家可见的基础状态摘要
  Map<String, dynamic> toVisibleSummary() {
    return <String, dynamic>{
      'turn': turn,
      'phase': phase,
      'active_player': activePlayer,
      'player_id': playerId,
      'lp': <String, int>{
        'self': playerId == 0 ? lp0 : lp1,
        'opponent': playerId == 0 ? lp1 : lp0,
      },
      'zones': <String, int>{
        'self_hand': playerId == 0 ? hand0Count : hand1Count,
        'opponent_hand': playerId == 0 ? hand1Count : hand0Count,
        'self_grave': playerId == 0 ? grave0Count : grave1Count,
        'opponent_grave': playerId == 0 ? grave1Count : grave0Count,
        'self_extra': playerId == 0 ? extra0Count : extra1Count,
        'opponent_extra': playerId == 0 ? extra1Count : extra0Count,
      },
      'duel_started': duelStarted,
      'pending_action_type': pendingAction?.type,
      'chain_length': chain.length,
      'history_length': history.length,
    };
  }

  // 处理 MSG_START 并建立玩家视角和双方初始区域数量
  void _applyStart(ByteCursor cursor) {
    final playerType = cursor.readUint8();
    cursor.readUint8();
    if ((playerType & 0xF0) == 0) {
      assignPlayerPerspective((playerType & 0x0F) == 0 ? 0 : 1);
    }
    lp0 = cursor.readUint32Le();
    lp1 = cursor.readUint32Le();
    deck0Count = cursor.readUint16Le();
    extra0Count = cursor.readUint16Le();
    deck1Count = cursor.readUint16Le();
    extra1Count = cursor.readUint16Le();
    hand0Count = 0;
    hand1Count = 0;
    grave0Count = 0;
    grave1Count = 0;
    removed0Count = 0;
    removed1Count = 0;
    cards = const <VisibleCard>[];
    chain = const <ChainLinkState>[];
    history = const <RecentEffectState>[];
    pendingAction = null;
    duelStarted = true;
  }

  // 处理 MSG_UPDATE_DATA 并原子合并一个区域内的卡片查询结果
  void _applyUpdateData(ByteCursor cursor) {
    final controller = cursor.readUint8();
    final location = cursor.readUint8();
    final blocks = <CardQueryBlock>[];
    while (cursor.remaining > 0) {
      blocks.add(CardQueryParser.parseBlock(cursor));
    }

    var updatedCards = List<VisibleCard>.from(cards);
    for (var sequence = 0; sequence < blocks.length; sequence++) {
      final update = blocks[sequence].update;
      if (update == null) continue;
      updatedCards = _mergeQueryIntoCards(
        updatedCards,
        controller: controller,
        location: location,
        sequence: sequence,
        update: update,
      );
    }
    cards = List<VisibleCard>.unmodifiable(updatedCards);
  }

  // 处理 MSG_UPDATE_CARD 并合并指定卡片的查询结果
  void _applyUpdateCard(ByteCursor cursor) {
    final controller = cursor.readUint8();
    final location = cursor.readUint8();
    final sequence = cursor.readUint8();
    final block = CardQueryParser.parseBlock(cursor);
    final update = block.update;
    if (update == null) return;
    cards = List<VisibleCard>.unmodifiable(
      _mergeQueryIntoCards(
        List<VisibleCard>.from(cards),
        controller: controller,
        location: location,
        sequence: sequence,
        update: update,
      ),
    );
  }

  // 处理 MSG_MOVE 并仅保存可见场上卡片
  void _applyMove(ByteCursor cursor) {
    final code = cursor.readUint32Le() & 0x7FFFFFFF;
    final oldLocation = _decodeLocation(cursor.readUint32Le());
    final newLocation = _decodeLocation(cursor.readUint32Le());
    cursor.readUint32Le();
    _removeCard(oldLocation);
    _adjustZoneCount(oldLocation.controller, oldLocation.location, -1);
    _adjustZoneCount(newLocation.controller, newLocation.location, 1);
    if (code != 0) {
      _trackOwnDeckMove(code, oldLocation, newLocation);
    }
    if (<int>{
      locationHand,
      locationMonster,
      locationSpellTrap,
      locationGrave,
      locationRemoved,
      locationExtra,
    }.contains(newLocation.location)) {
      final faceUp = (newLocation.position & 0x05) != 0;
      final visible = code != 0 &&
          (newLocation.controller == playerId ||
              newLocation.location == locationGrave ||
              newLocation.location == locationRemoved ||
              faceUp);
      cards = <VisibleCard>[
        ...cards,
        VisibleCard(
          code: visible ? code : 0,
          controller: newLocation.controller,
          location: newLocation.location,
          sequence: newLocation.sequence,
          position: newLocation.position,
          publiclyVisible: visible,
        ),
      ];
    }
  }

  // 处理 MSG_POS_CHANGE 的位置变更
  void _applyPositionChange(ByteCursor cursor) {
    final code = cursor.readUint32Le() & 0x7FFFFFFF;
    final controller = cursor.readUint8();
    final location = cursor.readUint8();
    final sequence = cursor.readUint8();
    cursor.readUint8();
    final position = cursor.readUint8();
    final index = cards.indexWhere(
      (card) =>
          card.controller == controller &&
          card.location == location &&
          card.sequence == sequence,
    );
    if (index >= 0) {
      final old = cards[index];
      final updatedCards = List<VisibleCard>.from(cards);
      updatedCards[index] = old.copyWith(
        code: old.publiclyVisible ? code : old.code,
        controller: controller,
        location: location,
        sequence: sequence,
        position: position,
      );
      cards = List.unmodifiable(updatedCards);
    }
  }

  // 处理 MSG_CHAINING 并保存连锁公开信息
  void _applyChaining(
    ByteCursor cursor,
    int? Function(int code, int runtimeDescription)? effectSlotResolver,
  ) {
    final code = cursor.readUint32Le() & 0x7FFFFFFF;
    final handler = _decodeLocation(cursor.readUint32Le());
    final triggerController = cursor.readUint8();
    final triggerLocation = cursor.readUint8();
    final triggerSequence = cursor.readUint8();
    final description = cursor.readUint32Le();
    final chainIndex = cursor.readUint8();
    final effectSlot = effectSlotResolver?.call(code, description);
    chain = <ChainLinkState>[
      ...chain,
      ChainLinkState(
        code: code,
        handlerController: handler.controller,
        handlerLocation: handler.location,
        handlerSequence: handler.sequence,
        handlerPosition: handler.position,
        controller: triggerController,
        location: triggerLocation,
        sequence: triggerSequence,
        descriptionId: description,
        chainIndex: chainIndex,
        effectSlot: effectSlot,
      ),
    ];
    history = List<RecentEffectState>.unmodifiable(<RecentEffectState>[
      RecentEffectState(
        code: code,
        descriptionId: description,
        effectSlot: effectSlot,
      ),
      ...history.take(7),
    ]);
    if (effectSlot != null && effectSlot >= 0 && effectSlot < 8) {
      final index = cards.indexWhere(
        (card) =>
            card.controller == handler.controller &&
            card.location == handler.location &&
            card.sequence == handler.sequence,
      );
      if (index >= 0) {
        final updatedCards = List<VisibleCard>.from(cards);
        final card = updatedCards[index];
        updatedCards[index] = card.copyWith(
          usedEffectMask: card.usedEffectMask | (1 << effectSlot),
        );
        cards = List<VisibleCard>.unmodifiable(updatedCards);
      }
    }
    if (handler.controller == playerId && handler.location == locationHand) {
      cards = cards
          .where(
            (card) =>
                card.controller != playerId ||
                card.location != locationHand ||
                card.sequence != handler.sequence,
          )
          .toList(growable: false);
    }
  }

  // 处理装备消息并标记被装备卡片的动态状态
  void _applyEquip(ByteCursor cursor) {
    cursor.readUint32Le();
    final target = _decodeLocation(cursor.readUint32Le());
    final index = cards.indexWhere(
      (card) =>
          card.controller == target.controller &&
          card.location == target.location &&
          card.sequence == target.sequence,
    );
    if (index < 0) return;
    final updatedCards = List<VisibleCard>.from(cards);
    updatedCards[index] = updatedCards[index].copyWith(isEquipped: true);
    cards = List<VisibleCard>.unmodifiable(updatedCards);
  }

  // 处理指示物增减消息并按种类维护公开计数
  void _applyCounter(ByteCursor cursor, {required bool add}) {
    final counterType = cursor.readUint16Le();
    final controller = cursor.readUint8();
    final location = cursor.readUint8();
    final sequence = cursor.readUint8();
    final count = cursor.readUint16Le();
    final index = cards.indexWhere(
      (card) =>
          card.controller == controller &&
          card.location == location &&
          card.sequence == sequence,
    );
    if (index < 0) return;
    final updatedCards = List<VisibleCard>.from(cards);
    final card = updatedCards[index];
    final counters = Map<int, int>.from(card.counters);
    final current = counters[counterType] ?? 0;
    final next =
        add ? current + count : (current - count).clamp(0, 65535).toInt();
    if (next == 0) {
      counters.remove(counterType);
    } else {
      counters[counterType] = next;
    }
    updatedCards[index] = card.copyWith(
      counters: Map<int, int>.unmodifiable(counters),
    );
    cards = List<VisibleCard>.unmodifiable(updatedCards);
  }

  // 处理抽卡消息并更新手牌和卡组数量
  void _applyDraw(ByteCursor cursor) {
    final player = cursor.readUint8();
    final count = cursor.readUint8();
    if (player == 0) {
      hand0Count += count;
      deck0Count = (deck0Count - count).clamp(0, 999).toInt();
    } else {
      hand1Count += count;
      deck1Count = (deck1Count - count).clamp(0, 999).toInt();
    }
    for (var index = 0; index < count; index++) {
      final code = cursor.readUint32Le() & 0x7FFFFFFF;
      if (player == playerId && code != 0) {
        ownRemainingDeckCodes = _removeOne(ownRemainingDeckCodes, code);
      }
      if (player == playerId && code != 0) {
        cards = <VisibleCard>[
          ...cards,
          VisibleCard(
            code: code,
            controller: player,
            location: locationHand,
            sequence: hand0Count + hand1Count + index,
            position: 0,
            publiclyVisible: true,
          ),
        ];
      }
    }
  }

  // 处理伤害或回复消息
  void _applyLpDelta(ByteCursor cursor, {required bool damage}) {
    final player = cursor.readUint8();
    final value = cursor.readUint32Le();
    if (player == 0) {
      lp0 = damage ? (lp0 - value).clamp(0, 0x7FFFFFFF).toInt() : lp0 + value;
    } else {
      lp1 = damage ? (lp1 - value).clamp(0, 0x7FFFFFFF).toInt() : lp1 + value;
    }
  }

  // 处理绝对 LP 更新消息
  void _applyLpUpdate(ByteCursor cursor) {
    final player = cursor.readUint8();
    final value = cursor.readUint32Le();
    if (player == 0) lp0 = value;
    if (player == 1) lp1 = value;
  }

  // 处理通用 Yes/No 交互
  void _applyYesNo(ByteCursor cursor, int type, Uint8List rawPayload) {
    final player = cursor.readUint8();
    final description = cursor.readUint32Le();
    pendingAction = PendingAction(
      type: type,
      player: player,
      options: const <int>[0, 1],
      descriptionId: description,
      rawPayload: List<int>.unmodifiable(rawPayload),
    );
  }

  // 处理带卡片上下文的效果 Yes/No 交互
  void _applyEffectYesNo(ByteCursor cursor, int type, Uint8List rawPayload) {
    final player = cursor.readUint8();
    final code = cursor.readUint32Le() & 0x7FFFFFFF;
    cursor.readUint8();
    cursor.readUint8();
    cursor.readUint8();
    cursor.readUint8();
    final description = cursor.readUint32Le();
    pendingAction = PendingAction(
      type: type,
      player: player,
      options: const <int>[0, 1],
      descriptionId: description,
      code: code,
      rawPayload: List<int>.unmodifiable(rawPayload),
    );
  }

  // 处理选项交互
  void _applyOption(ByteCursor cursor) {
    final player = cursor.readUint8();
    final count = cursor.readUint8();
    final descriptions = <int>[];
    for (var index = 0; index < count; index++) {
      descriptions.add(cursor.readUint32Le());
    }
    pendingAction = PendingAction(
      type: 14,
      player: player,
      options: List<int>.generate(count, (index) => index, growable: false),
      optionDescriptions: List.unmodifiable(descriptions),
      selectionCount: count,
    );
  }

  // 处理位置选择交互
  void _applyPlace(ByteCursor cursor, int type) {
    final player = cursor.readUint8();
    final count = cursor.readUint8();
    final responseCount = max(1, count);
    final mask = cursor.readUint32Le();
    final options = <int>[];
    for (var index = 0; index < 32; index++) {
      if ((mask & (1 << index)) == 0) options.add(index);
    }
    pendingAction = PendingAction(
      type: type,
      player: player,
      options: List.unmodifiable(options),
      selectionMin: count,
      selectionMax: count,
      selectionCount: responseCount,
    );
  }

  // 处理表示形式选择交互
  void _applyPositionPrompt(ByteCursor cursor) {
    final player = cursor.readUint8();
    final code = cursor.readUint32Le() & 0x7FFFFFFF;
    final mask = cursor.readUint8();
    final options = <int>[];
    for (final position in const <int>[1, 2, 4, 8]) {
      if ((mask & position) != 0) options.add(position);
    }
    pendingAction = PendingAction(
      type: 19,
      player: player,
      options: List.unmodifiable(options),
      code: code,
    );
  }

  // 解析主要阶段服务器提供的全部合法命令
  void _applyIdleCommand(ByteCursor cursor, Uint8List rawPayload) {
    final player = cursor.readUint8();
    final responses = <int>[];
    for (var category = 0; category < 6; category++) {
      final count = cursor.readUint8();
      for (var index = 0; index < count; index++) {
        cursor.readBytes(category == 5 ? 11 : 7);
        responses.add((index << 16) | category);
      }
    }
    if (cursor.readUint8() != 0) responses.add(6);
    if (cursor.readUint8() != 0) responses.add(7);
    if (cursor.readUint8() != 0) responses.add(8);
    pendingAction = PendingAction(
      type: 11,
      player: player,
      options: List.unmodifiable(responses),
      rawPayload: List.unmodifiable(rawPayload),
    );
  }

  // 解析战斗阶段服务器提供的发动、攻击和阶段命令
  void _applyBattleCommand(ByteCursor cursor, Uint8List rawPayload) {
    final player = cursor.readUint8();
    final responses = <int>[];
    final activateCount = cursor.readUint8();
    for (var index = 0; index < activateCount; index++) {
      cursor.readBytes(11);
      responses.add(index << 16);
    }
    final attackCount = cursor.readUint8();
    for (var index = 0; index < attackCount; index++) {
      cursor.readBytes(8);
      responses.add((index << 16) | 1);
    }
    if (cursor.readUint8() != 0) responses.add(2);
    if (cursor.readUint8() != 0) responses.add(3);
    pendingAction = PendingAction(
      type: 10,
      player: player,
      options: List.unmodifiable(responses),
      rawPayload: List.unmodifiable(rawPayload),
    );
  }

  // 解析选卡或祭品交互的数量范围和候选索引
  void _applySelectCards(ByteCursor cursor, int type, Uint8List rawPayload) {
    final player = cursor.readUint8();
    final cancelable = cursor.readUint8() != 0;
    final minimum = cursor.readUint8();
    final maximum = cursor.readUint8();
    final count = cursor.readUint8();
    final options = <int>[];
    for (var index = 0; index < count; index++) {
      cursor.readBytes(8);
      options.add(index);
    }
    pendingAction = PendingAction(
      type: type,
      player: player,
      options: List.unmodifiable(options),
      selectionMin: minimum,
      selectionMax: maximum,
      cancelable: cancelable,
      rawPayload: List.unmodifiable(rawPayload),
    );
  }

  // 解析连锁交互并加入合法取消选项
  void _applySelectChain(ByteCursor cursor, Uint8List rawPayload) {
    final player = cursor.readUint8();
    final count = cursor.readUint8();
    final forced = cursor.readUint8() != 0;
    cursor.readBytes(8);
    final options = <int>[];
    for (var index = 0; index < count; index++) {
      cursor.readBytes(13);
      options.add(index);
    }
    if (!forced) options.add(-1);
    pendingAction = PendingAction(
      type: 16,
      player: player,
      options: List.unmodifiable(options),
      selectionCount: count,
      cancelable: !forced,
      rawPayload: List.unmodifiable(rawPayload),
    );
  }

  // 解析排序交互并保存全部合法索引
  void _applySortCards(ByteCursor cursor, int type, Uint8List rawPayload) {
    final player = cursor.readUint8();
    final count = cursor.readUint8();
    cursor.readBytes(count * 7);
    pendingAction = PendingAction(
      type: type,
      player: player,
      options: List<int>.generate(count, (index) => index, growable: false),
      selectionMin: type == 25 ? count : 0,
      selectionMax: type == 25 ? count : 0,
      selectionCount: count,
      rawPayload: List.unmodifiable(rawPayload),
    );
  }

  // 解析可选与取消列表交互
  void _applyUnselect(ByteCursor cursor, Uint8List rawPayload) {
    final player = cursor.readUint8();
    final finishable = cursor.readUint8() != 0;
    final cancelable = cursor.readUint8() != 0;
    final minimum = cursor.readUint8();
    final maximum = cursor.readUint8();
    final selectableCount = cursor.readUint8();
    final options = <int>[];
    for (var index = 0; index < selectableCount; index++) {
      cursor.readBytes(8);
      options.add(index);
    }
    final selectedCount = cursor.readUint8();
    cursor.readBytes(selectedCount * 8);
    pendingAction = PendingAction(
      type: 26,
      player: player,
      options: List.unmodifiable(options),
      selectionMin: minimum,
      selectionMax: maximum,
      cancelable: cancelable,
      finishable: finishable,
      rawPayload: List.unmodifiable(rawPayload),
    );
  }

  // 保存尚需专用算法处理的完整交互载荷
  void _applyRawInteraction(
    ByteCursor cursor,
    OcgMessage message, {
    required int playerOffset,
  }) {
    final player = message.payload.length > playerOffset
        ? message.payload[playerOffset]
        : 0;
    var selectionMinimum = 0;
    var selectionMaximum = 0;
    if (message.type == 23 && message.payload.length >= 8) {
      selectionMinimum = message.payload[6];
      selectionMaximum = message.payload[7];
    } else if ((message.type == 140 || message.type == 141) &&
        message.payload.length >= 2) {
      selectionMinimum = message.payload[1];
      selectionMaximum = message.payload[1];
    }
    cursor.readBytes(cursor.remaining);
    pendingAction = PendingAction(
      type: message.type,
      player: player,
      options: const <int>[],
      selectionMin: selectionMinimum,
      selectionMax: selectionMaximum,
      rawPayload: List.unmodifiable(message.payload),
    );
  }

  // 将一次查询更新合并到指定位置并保留未查询字段
  List<VisibleCard> _mergeQueryIntoCards(
    List<VisibleCard> source, {
    required int controller,
    required int location,
    required int sequence,
    required CardQueryUpdate update,
  }) {
    final index = source.indexWhere(
      (card) =>
          card.controller == controller &&
          card.location == location &&
          card.sequence == sequence,
    );
    final previous = index < 0
        ? VisibleCard(
            code: 0,
            controller: controller,
            location: location,
            sequence: sequence,
            position: 0,
            publiclyVisible: false,
            owner: controller,
          )
        : source[index];
    final clearData = update.clearData;
    var code = update.code ?? previous.code;
    final isHidden = update.isHidden ?? (clearData ? false : previous.isHidden);
    if (isHidden || update.code == 0) code = 0;
    final merged = VisibleCard(
      code: code,
      controller: controller,
      location: location,
      sequence: sequence,
      position: update.position ?? previous.position,
      publiclyVisible: code != 0 && !isHidden,
      alias: update.alias ?? (clearData ? 0 : previous.alias),
      type: update.type ?? (clearData ? 0 : previous.type),
      level: update.level ?? (clearData ? 0 : previous.level),
      rank: update.rank ?? (clearData ? 0 : previous.rank),
      attribute: update.attribute ?? (clearData ? 0 : previous.attribute),
      race: update.race ?? (clearData ? 0 : previous.race),
      attack: update.attack ?? (clearData ? 0 : previous.attack),
      defense: update.defense ?? (clearData ? 0 : previous.defense),
      baseAttack: update.baseAttack ?? (clearData ? 0 : previous.baseAttack),
      baseDefense: update.baseDefense ?? (clearData ? 0 : previous.baseDefense),
      reason: update.reason ?? (clearData ? 0 : previous.reason),
      owner: update.owner ?? previous.owner,
      status: update.status ?? (clearData ? 0 : previous.status),
      isPublic: update.isPublic ?? (clearData ? false : previous.isPublic),
      leftScale: update.leftScale ?? (clearData ? 0 : previous.leftScale),
      rightScale: update.rightScale ?? (clearData ? 0 : previous.rightScale),
      link: update.link ?? (clearData ? 0 : previous.link),
      linkMarker: update.linkMarker ?? (clearData ? 0 : previous.linkMarker),
      isHidden: isHidden,
      cover: update.cover ?? (clearData ? 0 : previous.cover),
      reasonCard: update.reasonCard ?? (clearData ? null : previous.reasonCard),
      equipCard: update.equipCard ?? (clearData ? null : previous.equipCard),
      targetCards: update.targetCards ??
          (clearData ? const <CardLocationReference>[] : previous.targetCards),
      overlayCodes: update.overlayCodes ??
          (clearData ? const <int>[] : previous.overlayCodes),
      counters: update.counters ??
          (clearData ? const <int, int>{} : previous.counters),
      isEquipped: clearData ? false : previous.isEquipped,
      usedEffectMask: clearData ? 0 : previous.usedEffectMask,
    );
    if (index < 0) {
      source.add(merged);
    } else {
      source[index] = merged;
    }
    return source;
  }

  // 删除指定位置的可见卡片
  void _removeCard(_DecodedLocation location) {
    cards = cards
        .where(
          (card) =>
              card.controller != location.controller ||
              card.location != location.location ||
              card.sequence != location.sequence,
        )
        .toList(growable: false);
  }

  // 按卡片移动增减指定玩家的区域数量
  void _adjustZoneCount(int controller, int location, int delta) {
    if (controller != 0 && controller != 1 ||
        location == 0 ||
        (location & locationOverlay) != 0) {
      return;
    }
    int adjust(int value) => (value + delta).clamp(0, 999).toInt();
    if (controller == 0 && location == locationDeck) {
      deck0Count = adjust(deck0Count);
    }
    if (controller == 1 && location == locationDeck) {
      deck1Count = adjust(deck1Count);
    }
    if (controller == 0 && location == locationHand) {
      hand0Count = adjust(hand0Count);
    }
    if (controller == 1 && location == locationHand) {
      hand1Count = adjust(hand1Count);
    }
    if (controller == 0 && location == locationGrave) {
      grave0Count = adjust(grave0Count);
    }
    if (controller == 1 && location == locationGrave) {
      grave1Count = adjust(grave1Count);
    }
    if (controller == 0 && location == locationRemoved) {
      removed0Count = adjust(removed0Count);
    }
    if (controller == 1 && location == locationRemoved) {
      removed1Count = adjust(removed1Count);
    }
    if (controller == 0 && location == locationExtra) {
      extra0Count = adjust(extra0Count);
    }
    if (controller == 1 && location == locationExtra) {
      extra1Count = adjust(extra1Count);
    }
  }

  // 根据己方公开移动维护仅驻留设备的剩余卡组卡密
  void _trackOwnDeckMove(
    int code,
    _DecodedLocation oldLocation,
    _DecodedLocation newLocation,
  ) {
    if (oldLocation.controller == playerId) {
      if (oldLocation.location == locationDeck) {
        ownRemainingDeckCodes = _removeOne(ownRemainingDeckCodes, code);
      }
      if (oldLocation.location == locationExtra) {
        ownRemainingExtraCodes = _removeOne(ownRemainingExtraCodes, code);
      }
    }
    if (newLocation.controller == playerId) {
      if (newLocation.location == locationDeck &&
          oldLocation.location != locationDeck) {
        ownRemainingDeckCodes = List<int>.unmodifiable(<int>[
          ...ownRemainingDeckCodes,
          code,
        ]);
      }
      if (newLocation.location == locationExtra &&
          oldLocation.location != locationExtra) {
        ownRemainingExtraCodes = List<int>.unmodifiable(<int>[
          ...ownRemainingExtraCodes,
          code,
        ]);
      }
    }
  }

  // 从卡密多重集合中只移除一次指定卡片
  static List<int> _removeOne(List<int> source, int code) {
    final index = source.indexOf(code);
    if (index < 0) return source;
    final result = List<int>.from(source)..removeAt(index);
    return List<int>.unmodifiable(result);
  }

  // 解码 OCG 位置整数
  static _DecodedLocation _decodeLocation(int value) {
    return _DecodedLocation(
      controller: value & 0xFF,
      location: (value >> 8) & 0xFF,
      sequence: (value >> 16) & 0xFF,
      position: (value >> 24) & 0xFF,
    );
  }
}

class _DecodedLocation {
  const _DecodedLocation({
    required this.controller,
    required this.location,
    required this.sequence,
    required this.position,
  });

  final int controller;
  final int location;
  final int sequence;
  final int position;
}
