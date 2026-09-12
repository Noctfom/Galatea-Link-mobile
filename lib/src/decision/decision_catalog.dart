// 移动端合法动作目录，将服务器交互转换为 LLM 可选择且可直接发送的候选响应

import 'dart:convert';
import 'dart:typed_data';

import '../cards/card_database_service.dart';
import '../game_state.dart';
import 'rule_fallback.dart';

class DecisionCandidate {
  const DecisionCandidate({
    required this.choiceId,
    required this.label,
    required this.payload,
    this.details = const <String, Object?>{},
  });

  final int choiceId;
  final String label;
  final Uint8List payload;
  final Map<String, Object?> details;

  // 将候选动作转换为不包含协议响应字节的提示对象
  Map<String, Object?> toPromptJson() {
    return <String, Object?>{
      'choice_id': choiceId,
      'label': label,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

class DecisionCatalog {
  static const int _maximumCandidates = 120;
  static const int _maximumCombinationVisits = 50000;

  // 返回协议响应字节的稳定去重键
  static String payloadKey(List<int> payload) => base64Encode(payload);

  // 根据交互类型生成有上限的服务器合法动作目录
  static List<DecisionCandidate> build(
    PendingAction action, {
    CardDatabaseService? cardDatabase,
    Iterable<int> knownCodes = const <int>[],
  }) {
    final output = <DecisionCandidate>[];
    switch (action.type) {
      case 10:
      case 11:
      case 14:
      case 16:
        for (final option in action.options) {
          final details = _integerOptionDetails(action, option);
          _add(
            output,
            _integerOptionLabel(action, option, details),
            _int32(option),
            details,
          );
        }
        break;
      case 12:
      case 13:
        final details = _yesNoDetails(action);
        _add(output, '拒绝', _int32(0), details);
        _add(output, '同意', _int32(1), details);
        break;
      case 15:
        _addCardSelections(output, action);
        break;
      case 20:
        _addTributeSelections(output, action);
        break;
      case 21:
      case 25:
        _addSortSelections(output, action);
        break;
      case 22:
        _addCounterSelections(output, action);
        break;
      case 23:
        _addSumSelections(output, action);
        break;
      case 18:
      case 24:
        _addPlaceSelections(output, action);
        break;
      case 19:
        for (final position in action.options) {
          _add(
            output,
            '选择表示形式 $position',
            Uint8List.fromList([position]),
            <String, Object?>{'position': position},
          );
        }
        break;
      case 26:
        if (action.finishable) {
          _add(output, '完成当前选择', _int32(-1));
        }
        for (final index in action.options) {
          _add(
            output,
            '选择候选卡片 ${index + 1}',
            Uint8List.fromList([1, index]),
            _cardDetails(action, index, 6),
          );
        }
        if (action.cancelable && !action.finishable) {
          _add(output, '取消当前选择', _int32(-1));
        }
        break;
      case 143:
        _addAnnounceNumbers(output, action);
        break;
      case 142:
        _addAnnounceCards(output, action, cardDatabase, knownCodes);
        break;
      case 140:
      case 141:
        _addAnnounceMasks(output, action);
        break;
      default:
        _addFallback(output, action);
        break;
    }
    if (output.isEmpty) {
      _addFallback(output, action);
    }
    return List<DecisionCandidate>.unmodifiable(output);
  }

  // 为普通选卡生成有限数量的组合并保留卡密和位置信息
  static void _addCardSelections(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    final maximum = action.selectionMax == 0
        ? action.options.length
        : action.selectionMax.clamp(0, action.options.length).toInt();
    final minimum = action.selectionMin.clamp(0, action.options.length).toInt();
    for (var count = minimum; count <= maximum; count++) {
      _visitCombinations(action.options, count, (indices) {
        final label = indices.isEmpty
            ? '不选择卡片'
            : '选择候选卡片 ${indices.map((value) => value + 1).join(', ')}';
        final details = indices
            .map((index) => _cardDetails(action, index, 5))
            .toList(growable: false);
        _add(
          output,
          label,
          Uint8List.fromList([indices.length, ...indices]),
          <String, Object?>{'cards': details},
        );
        return output.length < _maximumCandidates;
      });
      if (output.length >= _maximumCandidates) break;
    }
    if (action.cancelable && output.length < _maximumCandidates) {
      _add(output, '取消选卡', _int32(-1));
    }
  }

  // 为祭品交互枚举张数受限且解放值达到下限的卡片组合
  static void _addTributeSelections(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    final raw = Uint8List.fromList(action.rawPayload);
    if (raw.length < 5) return;
    final count = raw[4];
    if (raw.length != 5 + count * 8) return;
    final maximum = action.selectionMax <= 0
        ? count
        : action.selectionMax.clamp(0, count).toInt();
    final values = List<int>.generate(
      count,
      (index) => raw[5 + index * 8 + 7],
      growable: false,
    );
    final candidateLimit =
        action.cancelable ? _maximumCandidates - 1 : _maximumCandidates;
    var visited = 0;
    for (var selectedCount = 1; selectedCount <= maximum; selectedCount++) {
      _visitCombinations(action.options, selectedCount, (indices) {
        visited += 1;
        if (visited > _maximumCombinationVisits) return false;
        final releaseValue = indices.fold<int>(
          0,
          (total, index) => total + values[index],
        );
        if (releaseValue >= action.selectionMin) {
          final cards = indices
              .map((index) => _cardDetails(action, index, 5))
              .toList(growable: false);
          _add(
            output,
            '选择 ${indices.map((value) => value + 1).join(', ')} 作为祭品，解放值 $releaseValue',
            Uint8List.fromList(<int>[indices.length, ...indices]),
            <String, Object?>{'cards': cards, 'release_value': releaseValue},
          );
        }
        return output.length < candidateLimit;
      });
      if (output.length >= candidateLimit ||
          visited > _maximumCombinationVisits) {
        break;
      }
    }
    if (action.cancelable) {
      _add(output, '取消祭品选择', _int32(-1));
    }
  }

  // 为指示物交互枚举每张卡上限内且总量精确匹配的分配方案
  static void _addCounterSelections(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    final raw = Uint8List.fromList(action.rawPayload);
    if (raw.length < 6) return;
    final count = raw[5];
    if (raw.length != 6 + count * 9) return;
    final counterType = _readUint16(raw, 1);
    final required = _readUint16(raw, 3);
    final available = List<int>.generate(
      count,
      (index) => _readUint16(raw, 6 + index * 9 + 7),
      growable: false,
    );
    final distribution = List<int>.filled(count, 0);
    var visited = 0;

    // 深度优先收集当前总量的所有有界分配
    bool visit(int cardIndex, int remaining) {
      visited += 1;
      if (visited > _maximumCombinationVisits) return false;
      if (output.length >= _maximumCandidates) return false;
      if (cardIndex == count) {
        if (remaining != 0) return true;
        final response = ByteData(count * 2);
        final cards = <Map<String, Object?>>[];
        for (var index = 0; index < count; index++) {
          response.setUint16(index * 2, distribution[index], Endian.little);
          if (distribution[index] > 0) {
            cards.add(<String, Object?>{
              ..._counterCardDetails(raw, index),
              'counter_count': distribution[index],
              'position_or_value': distribution[index],
            });
          }
        }
        _add(
          output,
          '分配指示物 ${distribution.join(', ')}',
          response.buffer.asUint8List(),
          <String, Object?>{
            'counter_type': counterType,
            'counter_total': required,
            'cards': cards,
          },
        );
        return output.length < _maximumCandidates;
      }
      final maximum =
          available[cardIndex] < remaining ? available[cardIndex] : remaining;
      for (var take = maximum; take >= 0; take--) {
        distribution[cardIndex] = take;
        if (!visit(cardIndex + 1, remaining - take)) return false;
      }
      distribution[cardIndex] = 0;
      return true;
    }

    visit(0, required);
  }

  // 为凑值交互枚举满足双重数值和模式规则的卡片组合
  static void _addSumSelections(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    final raw = Uint8List.fromList(action.rawPayload);
    if (raw.length < 10) return;
    final mode = raw[0];
    final target = _readUint32(raw, 2);
    final minimum = raw[6];
    final mandatoryCount = raw[8];
    var offset = 9;
    if (raw.length < offset + mandatoryCount * 11 + 1) return;
    final mandatoryCards = <Map<String, Object?>>[];
    final mandatoryValues = <int>[];
    for (var index = 0; index < mandatoryCount; index++) {
      final details = _sumCardDetails(raw, offset, mandatory: true);
      mandatoryCards.add(details);
      mandatoryValues.add(details['position_or_value']! as int);
      offset += 11;
    }
    final count = raw[offset++];
    if (raw.length != offset + count * 11) return;
    final candidateCards = List<Map<String, Object?>>.generate(
      count,
      (index) => _sumCardDetails(raw, offset + index * 11),
      growable: false,
    );
    final maximum = raw[7] == 0 ? count : raw[7].clamp(0, count).toInt();
    final candidateIndices = List<int>.generate(count, (index) => index);
    var visited = 0;
    for (var selectedCount = minimum;
        selectedCount <= maximum;
        selectedCount++) {
      _visitCombinations(candidateIndices, selectedCount, (indices) {
        visited += 1;
        if (visited > _maximumCombinationVisits) return false;
        final values = <int>[
          ...mandatoryValues,
          ...indices.map(
            (index) => candidateCards[index]['position_or_value']! as int,
          ),
        ];
        if (MobileRuleFallback.sumMatches(values, target, mode)) {
          final cards = <Map<String, Object?>>[
            ...mandatoryCards,
            ...indices.map((index) => candidateCards[index]),
          ];
          _add(
            output,
            '选择凑值卡片 ${indices.map((value) => value + 1).join(', ')}',
            Uint8List.fromList(<int>[
              mandatoryCount + indices.length,
              ...List<int>.filled(mandatoryCount, 0),
              ...indices,
            ]),
            <String, Object?>{
              'mode': mode,
              'target_value': target,
              'mandatory_count': mandatoryCount,
              'cards': cards,
            },
          );
        }
        return output.length < _maximumCandidates - 1;
      });
      if (output.length >= _maximumCandidates - 1 ||
          visited > _maximumCombinationVisits) {
        break;
      }
    }
    _add(output, '取消凑值选择', _int32(-1));
  }

  // 为排序交互枚举有限数量的合法索引排列
  static void _addSortSelections(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    _visitPermutations(action.options, (order) {
      final cards = order.indexed
          .map(
            (entry) => <String, Object?>{
              ..._sortCardDetails(action, entry.$2),
              'position_or_value': entry.$1 + 1,
            },
          )
          .toList(growable: false);
      _add(
        output,
        '排序为 ${order.map((value) => value + 1).join(', ')}',
        Uint8List.fromList(order),
        <String, Object?>{
          'cards': cards,
          'order': order,
          'target_values': List<int>.generate(
            order.length,
            (index) => index + 1,
            growable: false,
          ),
        },
      );
      return output.length < _maximumCandidates;
    });
  }

  // 为区域交互生成有限数量的位置组合
  static void _addPlaceSelections(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    if (action.selectionCount <= 0) return;
    if (action.selectionMin == 0) {
      _add(
        output,
        '不选择区域',
        Uint8List.fromList(const <int>[0, 0, 0]),
        const <String, Object?>{'places': <Object>[]},
      );
    }
    _visitCombinations(action.options, action.selectionCount, (zones) {
      final response = <int>[];
      final details = <Map<String, int>>[];
      for (final zone in zones) {
        final relativePlayer = (zone & 16) == 0 ? 0 : 1;
        final targetPlayer =
            relativePlayer == 0 ? action.player : 1 - action.player;
        final location = (zone & 8) == 0 ? locationMonster : locationSpellTrap;
        final sequence = zone & 7;
        response.addAll([targetPlayer, location, sequence]);
        details.add(<String, int>{
          'player': targetPlayer,
          'location': location,
          'sequence': sequence,
        });
      }
      _add(
        output,
        '选择区域 ${zones.join(', ')}',
        Uint8List.fromList(response),
        <String, Object?>{'places': details},
      );
      return output.length < _maximumCandidates;
    });
  }

  // 为数字宣言建立索引和值的对应关系
  static void _addAnnounceNumbers(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    final raw = Uint8List.fromList(action.rawPayload);
    if (raw.length < 2) return;
    final count = raw[1];
    if (raw.length != 2 + count * 4) return;
    final view = ByteData.sublistView(raw);
    for (var index = 0; index < count; index++) {
      final value = view.getUint32(2 + index * 4, Endian.little);
      _add(output, '宣言数值 $value', _int32(index), <String, Object?>{
        'value': value,
      });
    }
  }

  // 为卡名宣言执行 RPN 过滤并建立真实卡密响应候选
  static void _addAnnounceCards(
    List<DecisionCandidate> output,
    PendingAction action,
    CardDatabaseService? cardDatabase,
    Iterable<int> knownCodes,
  ) {
    final raw = Uint8List.fromList(action.rawPayload);
    if (raw.length < 2) return;
    final count = raw[1];
    if (raw.length != 2 + count * 4) return;
    final view = ByteData.sublistView(raw);
    final opcodes = List<int>.generate(
      count,
      (index) => view.getUint32(2 + index * 4, Endian.little),
      growable: false,
    );
    final metadata = cardDatabase?.findAnnounceCandidates(
          opcodes,
          knownCodes,
          limit: _maximumCandidates,
        ) ??
        const <CardMetadata>[];
    if (metadata.isNotEmpty) {
      for (final card in metadata) {
        _add(
          output,
          '宣言 ${card.name} (${card.code})',
          _int32(card.code),
          <String, Object?>{'code': card.code, 'name': card.name},
        );
      }
      return;
    }
    final directCodes = opcodes
        .where((value) => value > 10000 && value < 0x40000000)
        .map((value) => value & 0x0fffffff)
        .toSet();
    for (final code in directCodes) {
      _add(output, '宣言卡密 $code', _int32(code), <String, Object?>{'code': code});
    }
  }

  // 为种族和属性宣言枚举恰好包含指定数量位的掩码
  static void _addAnnounceMasks(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    final raw = Uint8List.fromList(action.rawPayload);
    if (raw.length != 6) return;
    final required = raw[1];
    final available = _readUint32(raw, 2);
    final bits = <int>[];
    for (var bit = 0; bit < 32; bit++) {
      if ((available & (1 << bit)) != 0) bits.add(bit);
    }
    _visitCombinations(bits, required, (selectedBits) {
      var mask = 0;
      for (final bit in selectedBits) {
        mask |= 1 << bit;
      }
      _add(
        output,
        '宣言项目 ${selectedBits.map((value) => value + 1).join(', ')}',
        _uint32(mask),
        <String, Object?>{
          'mask': mask,
          'bits': selectedBits,
          'target_values':
              selectedBits.map((value) => value + 1).toList(growable: false),
        },
      );
      return output.length < _maximumCandidates;
    });
  }

  // 从选卡原始载荷提取公开卡密和位置字段
  static Map<String, Object?> _cardDetails(
    PendingAction action,
    int index,
    int headerLength,
  ) {
    final offset = headerLength + index * 8;
    if (offset < 0 || offset + 8 > action.rawPayload.length) {
      return <String, Object?>{'index': index};
    }
    final raw = Uint8List.fromList(action.rawPayload);
    final view = ByteData.sublistView(raw);
    return <String, Object?>{
      'index': index,
      'code': view.getUint32(offset, Endian.little) & 0x7FFFFFFF,
      'controller': raw[offset + 4],
      'location': raw[offset + 5],
      'sequence': raw[offset + 6],
      'position_or_value': raw[offset + 7],
    };
  }

  // 从指示物交互中提取候选卡片和可用数量
  static Map<String, Object?> _counterCardDetails(Uint8List raw, int index) {
    final offset = 6 + index * 9;
    return <String, Object?>{
      'index': index,
      'code': _readUint32(raw, offset) & 0x7FFFFFFF,
      'controller': raw[offset + 4],
      'location': raw[offset + 5],
      'sequence': raw[offset + 6],
      'available_count': _readUint16(raw, offset + 7),
    };
  }

  // 从凑值交互中提取候选卡片和双重数值
  static Map<String, Object?> _sumCardDetails(
    Uint8List raw,
    int offset, {
    bool mandatory = false,
  }) {
    return <String, Object?>{
      'code': _readUint32(raw, offset) & 0x7FFFFFFF,
      'controller': raw[offset + 4],
      'location': raw[offset + 5],
      'sequence': raw[offset + 6],
      'position_or_value': _readUint32(raw, offset + 7),
      'mandatory': mandatory,
    };
  }

  // 从排序交互中提取指定索引的卡片位置
  static Map<String, Object?> _sortCardDetails(
    PendingAction action,
    int index,
  ) {
    final raw = Uint8List.fromList(action.rawPayload);
    final offset = 2 + index * 7;
    if (offset < 0 || offset + 7 > raw.length) {
      return <String, Object?>{'index': index};
    }
    return <String, Object?>{
      'index': index,
      'code': _readUint32(raw, offset) & 0x7FFFFFFF,
      'controller': raw[offset + 4],
      'location': raw[offset + 5],
      'sequence': raw[offset + 6],
    };
  }

  // 从确认交互中提取卡片位置和描述编号
  static Map<String, Object?> _yesNoDetails(PendingAction action) {
    final raw = Uint8List.fromList(action.rawPayload);
    if (action.type == 13 && raw.length == 5) {
      return <String, Object?>{'description_id': _readUint32(raw, 1)};
    }
    if (action.type == 12 && raw.length == 13) {
      return <String, Object?>{
        'code': _readUint32(raw, 1) & 0x7FFFFFFF,
        'controller': raw[5],
        'location': raw[6],
        'sequence': raw[7],
        'position': raw[8],
        'description_id': _readUint32(raw, 9),
      };
    }
    return const <String, Object?>{};
  }

  // 枚举固定数量的索引组合并允许调用方提前停止
  static void _visitCombinations(
    List<int> source,
    int count,
    bool Function(List<int>) visitor,
  ) {
    if (count < 0 || count > source.length) return;
    final selected = <int>[];

    // 深度优先生成当前数量的组合
    bool visit(int start) {
      if (selected.length == count) {
        return visitor(List<int>.from(selected));
      }
      final remaining = count - selected.length;
      for (var index = start; index <= source.length - remaining; index++) {
        selected.add(source[index]);
        if (!visit(index + 1)) return false;
        selected.removeLast();
      }
      return true;
    }

    visit(0);
  }

  // 枚举索引全排列并允许调用方在达到候选上限时停止
  static void _visitPermutations(
    List<int> source,
    bool Function(List<int>) visitor,
  ) {
    final selected = <int>[];
    final used = List<bool>.filled(source.length, false);

    // 深度优先生成当前排列
    bool visit() {
      if (selected.length == source.length) {
        return visitor(List<int>.from(selected));
      }
      for (var index = 0; index < source.length; index++) {
        if (used[index]) continue;
        used[index] = true;
        selected.add(source[index]);
        if (!visit()) return false;
        selected.removeLast();
        used[index] = false;
      }
      return true;
    }

    visit();
  }

  // 在无法枚举多个动作时加入规则层已经验证的安全响应
  static void _addFallback(
    List<DecisionCandidate> output,
    PendingAction action,
  ) {
    final fallback = MobileRuleFallback.decide(action);
    if (fallback != null) {
      _add(output, fallback.description, fallback.payload);
    }
  }

  // 添加候选并按响应字节去重和限制总数
  static void _add(
    List<DecisionCandidate> output,
    String label,
    Uint8List payload, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    if (output.length >= _maximumCandidates) return;
    final key = payloadKey(payload);
    if (output.any((candidate) => payloadKey(candidate.payload) == key)) {
      return;
    }
    output.add(
      DecisionCandidate(
        choiceId: output.length,
        label: label,
        payload: payload,
        details: details,
      ),
    );
  }

  // 返回整数动作在提示中的简短说明
  static String _integerOptionLabel(
    PendingAction action,
    int value,
    Map<String, Object?> details,
  ) {
    if (action.type == 16 && value == -1) return '不发动连锁';
    final code = details['code'];
    if (action.type == 10 || action.type == 11) {
      final category = value & 0xFFFF;
      final index = (value >> 16) & 0xFFFF;
      final actionName = action.type == 10
          ? const <int, String>{
              0: '发动效果',
              1: '攻击',
              2: '进入主要阶段二',
              3: '进入结束阶段',
            }[category]
          : const <int, String>{
              0: '通常召唤',
              1: '特殊召唤',
              2: '改变表示形式',
              3: '盖放怪兽',
              4: '盖放魔法陷阱',
              5: '发动效果',
              6: '进入战斗阶段',
              7: '进入结束阶段',
              8: '洗切手牌',
            }[category];
      final suffix = code is int && code != 0 ? ' 卡密 $code' : '';
      return '${actionName ?? '动作类别 $category'} 候选 ${index + 1}$suffix';
    }
    if (action.type == 14 &&
        value >= 0 &&
        value < action.optionDescriptions.length) {
      return '选择选项 ${value + 1} 描述 ${action.optionDescriptions[value]}';
    }
    if (action.type == 16 && code is int) return '发动卡密 $code 的连锁';
    return '选择选项 ${value + 1}';
  }

  // 从主要阶段战斗和连锁载荷提取候选动作上下文
  static Map<String, Object?> _integerOptionDetails(
    PendingAction action,
    int value,
  ) {
    final base = <String, Object?>{};
    if (value < 0) return <String, Object?>{'cancel': true};
    final raw = Uint8List.fromList(action.rawPayload);
    if (action.type == 14) {
      base['response_value'] = value;
      if (value < action.optionDescriptions.length) {
        base['description_id'] = action.optionDescriptions[value];
      }
      return base;
    }
    if (action.type == 11) {
      final category = value & 0xFFFF;
      final index = (value >> 16) & 0xFFFF;
      base['category'] = category;
      if (category >= 6 || raw.isEmpty) return base;
      var offset = 1;
      for (var current = 0; current < 6; current++) {
        if (offset >= raw.length) return base;
        final count = raw[offset++];
        final itemLength = current == 5 ? 11 : 7;
        if (current == category && index < count) {
          return <String, Object?>{
            ...base,
            ..._commandCardDetails(
              raw,
              offset + index * itemLength,
              itemLength,
            ),
          };
        }
        offset += count * itemLength;
      }
      return base;
    }
    if (action.type == 10 && raw.length >= 2) {
      final category = value & 0xFFFF;
      final index = (value >> 16) & 0xFFFF;
      base['category'] = category;
      final activateCount = raw[1];
      if (category == 0 && index < activateCount) {
        return <String, Object?>{
          ...base,
          ..._commandCardDetails(raw, 2 + index * 11, 11),
        };
      }
      final attackCountOffset = 2 + activateCount * 11;
      if (attackCountOffset < raw.length) {
        final attackCount = raw[attackCountOffset];
        if (category == 1 && index < attackCount) {
          final details = _commandCardDetails(
            raw,
            attackCountOffset + 1 + index * 8,
            8,
          );
          return <String, Object?>{
            ...base,
            ...details,
            'response_value': details['direct_attack'] == true ? 1 : 0,
          };
        }
      }
      return base;
    }
    if (action.type == 16 && raw.length >= 11) {
      final count = raw[1];
      if (value >= count) return base;
      final offset = 11 + value * 13;
      if (offset + 13 > raw.length) return base;
      final location = _readUint32(raw, offset + 5);
      return <String, Object?>{
        ...base,
        'response_value': value,
        'effect_flag': raw[offset],
        'code': _readUint32(raw, offset + 1) & 0x7FFFFFFF,
        'controller': location & 0xFF,
        'location': (location >> 8) & 0xFF,
        'sequence': (location >> 16) & 0xFF,
        'position': (location >> 24) & 0xFF,
        'description_id': _readUint32(raw, offset + 9),
      };
    }
    return base;
  }

  // 从命令项中提取卡密位置和可选描述编号
  static Map<String, Object?> _commandCardDetails(
    Uint8List raw,
    int offset,
    int itemLength,
  ) {
    if (offset < 0 || offset + itemLength > raw.length || itemLength < 7) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      'code': _readUint32(raw, offset) & 0x7FFFFFFF,
      'controller': raw[offset + 4],
      'location': raw[offset + 5],
      'sequence': raw[offset + 6],
      if (itemLength == 11) 'description_id': _readUint32(raw, offset + 7),
      if (itemLength == 8) 'direct_attack': raw[offset + 7] != 0,
    };
  }

  // 从字节列表读取小端三十二位无符号整数
  static int _readUint32(Uint8List raw, int offset) {
    return ByteData.sublistView(raw).getUint32(offset, Endian.little);
  }

  // 从字节列表读取小端十六位无符号整数
  static int _readUint16(Uint8List raw, int offset) {
    return ByteData.sublistView(raw).getUint16(offset, Endian.little);
  }

  // 将整数响应编码为 YGOPro 小端四字节
  static Uint8List _int32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  // 将无符号整数响应编码为 YGOPro 小端四字节
  static Uint8List _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }
}
