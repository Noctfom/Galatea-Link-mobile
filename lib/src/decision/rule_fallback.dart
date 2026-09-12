// 移动端最小 RuleBot，根据已解析合法动作生成确定性安全响应

import 'dart:typed_data';

import '../game_state.dart';

class RuleResponse {
  const RuleResponse({required this.payload, required this.description});

  final Uint8List payload;
  final String description;
}

class MobileRuleFallback {
  // 为明确支持的简单交互生成响应，复杂交互返回空值
  static RuleResponse? decide(PendingAction action) {
    switch (action.type) {
      case 10:
      case 11:
        if (action.options.isEmpty) return null;
        return RuleResponse(
          payload: _int32(action.options.first),
          description: action.type == 10 ? '执行首个合法战斗指令' : '执行首个合法主要阶段指令',
        );
      case 12:
      case 13:
        return RuleResponse(payload: _int32(0), description: '安全拒绝 Yes/No');
      case 14:
        if (action.options.isEmpty) return null;
        return RuleResponse(
            payload: _int32(action.options.first), description: '选择首个 Option');
      case 15:
        return _selectCards(action);
      case 16:
        if (action.options.isEmpty) return null;
        final choice = action.cancelable ? -1 : action.options.first;
        return RuleResponse(
          payload: _int32(choice),
          description: choice == -1 ? '跳过可选连锁' : '执行首个强制连锁',
        );
      case 18:
      case 24:
        return _selectPlaces(action);
      case 19:
        if (action.options.isEmpty) return null;
        return RuleResponse(
          payload: Uint8List.fromList([action.options.first]),
          description: '选择首个合法表示',
        );
      case 20:
        return _selectTributes(action);
      case 22:
        return _selectCounters(action);
      case 23:
        return _selectSum(action);
      case 21:
      case 25:
        if (action.selectionCount == 0) return null;
        return RuleResponse(
          payload: Uint8List.fromList(action.options),
          description: '保持服务器提供的卡片顺序',
        );
      case 26:
        if (action.finishable || action.cancelable && action.options.isEmpty) {
          return RuleResponse(payload: _int32(-1), description: '结束或取消可选卡片交互');
        }
        if (action.options.isEmpty) return null;
        return RuleResponse(
          payload: Uint8List.fromList([1, action.options.first]),
          description: '选择首张可操作卡片',
        );
      case 140:
      case 141:
        return _announceMask(action);
      case 143:
        if (action.rawPayload.length < 2 || action.rawPayload[1] == 0) {
          return null;
        }
        return RuleResponse(payload: _int32(0), description: '选择首个合法宣言数值');
      default:
        return null;
    }
  }

  // 为普通选卡交互选择满足最小数量的前若干张卡
  static RuleResponse? _selectCards(PendingAction action) {
    final count = action.selectionMin.clamp(0, action.options.length).toInt();
    if (count == 0 && action.cancelable) {
      return RuleResponse(payload: _int32(-1), description: '取消可选选卡交互');
    }
    if (count < action.selectionMin) return null;
    final indices = action.options.take(count).toList(growable: false);
    return RuleResponse(
      payload: Uint8List.fromList([indices.length, ...indices]),
      description: '选择满足最低数量的卡片',
    );
  }

  // 为祭品选择寻找首个满足解放值范围的组合
  static RuleResponse? _selectTributes(PendingAction action) {
    final raw = action.rawPayload;
    if (raw.length < 5) return null;
    final count = raw[4];
    if (raw.length != 5 + count * 8) return null;
    final values = List<int>.generate(count, (index) => raw[5 + index * 8 + 7]);
    List<int>? solution;

    // 深度优先寻找最短且索引稳定的合法祭品组合
    bool search(int start, int total, List<int> selected) {
      if (selected.isNotEmpty &&
          total >= action.selectionMin &&
          (action.selectionMax == 0 ||
              selected.length <= action.selectionMax)) {
        solution = List<int>.from(selected);
        return true;
      }
      if (action.selectionMax > 0 && selected.length >= action.selectionMax) {
        return false;
      }
      for (var index = start; index < values.length; index++) {
        selected.add(index);
        if (search(index + 1, total + values[index], selected)) return true;
        selected.removeLast();
      }
      return false;
    }

    search(0, 0, <int>[]);
    if (solution == null) {
      if (action.cancelable) {
        return RuleResponse(payload: _int32(-1), description: '取消无可用组合的祭品选择');
      }
      return null;
    }
    return RuleResponse(
      payload: Uint8List.fromList([solution!.length, ...solution!]),
      description: '选择首个合法祭品组合',
    );
  }

  // 将位置掩码索引转换为 YGOPro 三字节绝对位置
  static RuleResponse? _selectPlaces(PendingAction action) {
    if (action.options.length < action.selectionCount ||
        action.selectionCount <= 0) {
      return null;
    }
    final payload = <int>[];
    for (final zone in action.options.take(action.selectionCount)) {
      final relativePlayer = (zone & 16) == 0 ? 0 : 1;
      final targetPlayer =
          relativePlayer == 0 ? action.player : 1 - action.player;
      final location = (zone & 8) == 0 ? locationMonster : locationSpellTrap;
      payload.addAll([targetPlayer, location, zone & 7]);
    }
    return RuleResponse(
      payload: Uint8List.fromList(payload),
      description: '选择首批合法区域',
    );
  }

  // 按服务器给出的每张卡上限依次分配所需指示物
  static RuleResponse? _selectCounters(PendingAction action) {
    final raw = action.rawPayload;
    if (raw.length < 6) return null;
    final cursor = ByteData.sublistView(Uint8List.fromList(raw));
    var remaining = cursor.getUint16(3, Endian.little);
    final count = raw[5];
    if (raw.length != 6 + count * 9) return null;
    final selected = List<int>.filled(count, 0);
    for (var index = 0; index < count && remaining > 0; index++) {
      final available = cursor.getUint16(6 + index * 9 + 7, Endian.little);
      final take = available < remaining ? available : remaining;
      selected[index] = take;
      remaining -= take;
    }
    if (remaining != 0) return null;
    final response = ByteData(count * 2);
    for (var index = 0; index < count; index++) {
      response.setUint16(index * 2, selected[index], Endian.little);
    }
    return RuleResponse(
      payload: response.buffer.asUint8List(),
      description: '按卡片顺序分配所需指示物',
    );
  }

  // 为种族或属性宣言选择掩码中的最低若干位
  static RuleResponse? _announceMask(PendingAction action) {
    final raw = action.rawPayload;
    if (raw.length != 6) return null;
    final view = ByteData.sublistView(Uint8List.fromList(raw));
    final count = raw[1];
    final available = view.getUint32(2, Endian.little);
    var selected = 0;
    var selectedCount = 0;
    for (var bit = 0; bit < 32 && selectedCount < count; bit++) {
      final value = 1 << bit;
      if ((available & value) != 0) {
        selected |= value;
        selectedCount += 1;
      }
    }
    if (selectedCount != count) return null;
    return RuleResponse(payload: _uint32(selected), description: '选择首批合法宣言项');
  }

  // 为凑数交互寻找首个满足协议规则的候选组合
  static RuleResponse? _selectSum(PendingAction action) {
    final raw = action.rawPayload;
    if (raw.length < 10) return null;
    final view = ByteData.sublistView(Uint8List.fromList(raw));
    final mode = raw[0];
    final target = view.getUint32(2, Endian.little);
    final minimum = raw[6];
    final maximum = raw[7];
    final mandatoryCount = raw[8];
    var offset = 9;
    if (raw.length < offset + mandatoryCount * 11 + 1) return null;
    final mandatoryValues = <int>[];
    for (var index = 0; index < mandatoryCount; index++) {
      mandatoryValues.add(view.getUint32(offset + 7, Endian.little));
      offset += 11;
    }
    final candidateCount = raw[offset++];
    if (raw.length != offset + candidateCount * 11) return null;
    final candidateValues = <int>[];
    for (var index = 0; index < candidateCount; index++) {
      candidateValues
          .add(view.getUint32(offset + index * 11 + 7, Endian.little));
    }
    List<int>? solution;
    var visited = 0;
    final realMaximum = maximum == 0 ? candidateCount : maximum;

    // 有界搜索第一个合法凑数组合以防止移动端长时间阻塞
    bool search(int start, List<int> selected) {
      visited += 1;
      if (visited > 20000) return false;
      if (selected.length >= minimum) {
        final values = <int>[
          ...mandatoryValues,
          ...selected.map((index) => candidateValues[index]),
        ];
        if (sumMatches(values, target, mode)) {
          solution = List<int>.from(selected);
          return true;
        }
      }
      if (selected.length >= realMaximum) return false;
      for (var index = start; index < candidateValues.length; index++) {
        selected.add(index);
        if (search(index + 1, selected)) return true;
        selected.removeLast();
      }
      return false;
    }

    search(0, <int>[]);
    if (solution == null) return null;
    return RuleResponse(
      payload: Uint8List.fromList([
        mandatoryCount + solution!.length,
        ...List<int>.filled(mandatoryCount, 0),
        ...solution!,
      ]),
      description: '选择首个合法凑数组合',
    );
  }

  // 检查每个双重数值的可选取值是否能满足凑数条件
  static bool sumMatches(List<int> values, int target, int mode) {
    bool visit(int index, int total, int minimum) {
      if (index == values.length) {
        return mode == 0
            ? total == target
            : total >= target && total - minimum < target;
      }
      final first = values[index] & 0xFFFF;
      final second = values[index] >> 16;
      final nextMinimum = minimum < 0 || first < minimum ? first : minimum;
      if (visit(index + 1, total + first, nextMinimum)) return true;
      if (second != 0 && second != first) {
        final alternateMinimum =
            minimum < 0 || second < minimum ? second : minimum;
        if (visit(index + 1, total + second, alternateMinimum)) return true;
      }
      return false;
    }

    return visit(0, 0, -1);
  }

  // 将整数响应编码为 YGOPro 小端有符号四字节
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
