// OCG 内层消息解析器，按模型协议前的在线消息长度严格切分

import 'dart:typed_data';

import 'byte_cursor.dart';

const Set<int> ocgInteractionTypes = <int>{
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  140,
  141,
  142,
  143
};

class OcgMessage {
  const OcgMessage({required this.type, required this.payload});

  final int type;
  final Uint8List payload;
}

class OcgParser {
  static const Map<int, int> _fixedLengths = <int, int>{
    1: 0,
    2: 6,
    3: 0,
    5: 2,
    12: 13,
    13: 5,
    18: 6,
    19: 6,
    24: 6,
    32: 1,
    35: 1,
    37: 0,
    38: 6,
    40: 1,
    41: 2,
    50: 16,
    53: 9,
    54: 8,
    55: 16,
    56: 4,
    60: 8,
    61: 0,
    62: 8,
    63: 0,
    64: 8,
    65: 0,
    70: 16,
    71: 1,
    72: 1,
    73: 1,
    74: 0,
    75: 1,
    76: 1,
    91: 5,
    92: 5,
    93: 8,
    94: 5,
    96: 8,
    97: 8,
    100: 5,
    101: 7,
    102: 7,
    110: 8,
    111: 26,
    112: 0,
    113: 0,
    114: 0,
    120: 8,
    132: 1,
    133: 1,
    140: 6,
    141: 6,
    160: 9,
    165: 6,
    170: 4,
  };

  // 严格解析一组连续 OCG 消息并拒绝无法确定长度的类型
  static List<OcgMessage> parse(List<int> source) {
    final data = Uint8List.fromList(source);
    final messages = <OcgMessage>[];
    var offset = 0;
    while (offset < data.length) {
      final type = data[offset++];
      final payloadLength = const <int>{4, 6, 7, 8}.contains(type)
          ? data.length - offset
          : _payloadLength(type, data, offset);
      if (payloadLength < 0 || offset + payloadLength > data.length) {
        throw YgoProtocolException(
          'OCG 消息 Type $type 长度不足 declared=$payloadLength remaining=${data.length - offset}',
        );
      }
      messages.add(OcgMessage(
          type: type,
          payload: Uint8List.fromList(
              data.sublist(offset, offset + payloadLength))));
      offset += payloadLength;
    }
    return messages;
  }

  // 计算固定或动态 OCG 消息的载荷长度
  static int _payloadLength(int type, Uint8List data, int offset) {
    final fixed = _fixedLengths[type];
    if (fixed != null) return fixed;
    switch (type) {
      case 10:
        return _battleCommandLength(data, offset);
      case 11:
        return _idleCommandLength(data, offset);
      case 14:
        return _countedLength(data, offset, headerBytes: 2, itemBytes: 4);
      case 15:
      case 20:
        return _countedLength(data, offset,
            headerBytes: 5, itemBytes: 8, countOffset: 4);
      case 16:
        return _countedLength(data, offset,
            headerBytes: 11, itemBytes: 13, countOffset: 1);
      case 21:
      case 25:
        return _countedLength(data, offset, headerBytes: 2, itemBytes: 7);
      case 22:
        return _countedLength(data, offset,
            headerBytes: 6, itemBytes: 9, countOffset: 5);
      case 23:
        return _sumCommandLength(data, offset);
      case 26:
        return _twoCountLength(data, offset);
      case 30:
      case 31:
      case 34:
      case 42:
        return _countedLength(data, offset, headerBytes: 2, itemBytes: 7);
      case 33:
      case 39:
      case 81:
      case 90:
      case 142:
      case 143:
        return _countedLength(data, offset, headerBytes: 2, itemBytes: 4);
      case 83:
        return _countedLength(data, offset,
            headerBytes: 1, itemBytes: 4, countOffset: 0);
      case 36:
        return _countedLength(data, offset, headerBytes: 2, itemBytes: 8);
      case 130:
      case 131:
        return _countedLength(data, offset, headerBytes: 2, itemBytes: 1);
      case 163:
      case 164:
        return _stringLength(data, offset);
      default:
        throw YgoProtocolException('未知 OCG 消息 Type $type 缺少长度定义');
    }
  }

  // 计算战斗指令消息长度
  static int _battleCommandLength(Uint8List data, int offset) {
    _requireBytes(data, offset, 2);
    final monsterCount = data[offset + 1];
    var length = 2 + monsterCount * 11;
    _requireBytes(data, offset + length, 1);
    final spellCount = data[offset + length];
    length += 1 + spellCount * 8 + 2;
    return length;
  }

  // 计算待机指令消息长度
  static int _idleCommandLength(Uint8List data, int offset) {
    _requireBytes(data, offset, 1);
    var length = 1;
    for (var index = 0; index < 6; index++) {
      _requireBytes(data, offset + length, 1);
      final count = data[offset + length];
      length += 1 + count * (index == 5 ? 11 : 7);
    }
    return length + 3;
  }

  // 计算一个数量和定长项目组成的消息长度
  static int _countedLength(Uint8List data, int offset,
      {required int headerBytes, required int itemBytes, int countOffset = 1}) {
    _requireBytes(data, offset, headerBytes);
    return headerBytes + data[offset + countOffset] * itemBytes;
  }

  // 计算选择数值消息长度
  static int _sumCommandLength(Uint8List data, int offset) {
    _requireBytes(data, offset, 9);
    final mustCount = data[offset + 8];
    final first = 9 + mustCount * 11;
    _requireBytes(data, offset + first + 1, 1);
    final selectCount = data[offset + first];
    return first + 1 + selectCount * 11;
  }

  // 计算双列表选择消息长度
  static int _twoCountLength(Uint8List data, int offset) {
    _requireBytes(data, offset, 6);
    final firstCount = data[offset + 5];
    final secondOffset = offset + 6 + firstCount * 8;
    _requireBytes(data, secondOffset, 1);
    final secondCount = data[secondOffset];
    return 6 + firstCount * 8 + 1 + secondCount * 8;
  }

  // 计算带十六位长度头的字符串消息长度
  static int _stringLength(Uint8List data, int offset) {
    _requireBytes(data, offset, 2);
    final stringLength = data[offset] | (data[offset + 1] << 8);
    return 2 + stringLength + 1;
  }

  // 检查动态长度计算所需的字节范围
  static void _requireBytes(Uint8List data, int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > data.length) {
      throw YgoProtocolException(
          'OCG 动态消息头部不完整 offset=$offset need=$length total=${data.length}');
    }
  }
}
