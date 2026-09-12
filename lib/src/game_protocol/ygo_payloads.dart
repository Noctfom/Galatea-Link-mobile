// YGOPro 登录、房间和决策载荷构建，统一处理 UTF-16LE 和小端整数

import 'dart:typed_data';

import '../game_chat.dart';
import 'byte_cursor.dart';

// 构建 CTOS_CHAT 使用的 UTF-16LE 空结尾文本载荷
Uint8List buildChatPayload(String text) {
  return encodeClientGameChat(text);
}

// 构建固定长度的 UTF-16LE 零填充字段
Uint8List encodeUtf16LeFixed(String value, int codeUnits) {
  if (codeUnits < 0) {
    throw const YgoProtocolException('UTF-16LE 字段长度不能为负数');
  }
  final units = value.codeUnits.take(codeUnits).toList(growable: false);
  final result = Uint8List(codeUnits * 2);
  for (var index = 0; index < units.length; index++) {
    result[index * 2] = units[index] & 0xFF;
    result[index * 2 + 1] = (units[index] >> 8) & 0xFF;
  }
  return result;
}

// 构建 CTOS_PLAYER_INFO 使用的玩家名称载荷
Uint8List buildPlayerInfoPayload(String name) {
  return encodeUtf16LeFixed(name, 20);
}

// 构建 CTOS_UPDATE_DECK 使用的对局卡组和副卡组载荷
Uint8List buildDeckPayload(
  List<int> mainDeck,
  List<int> extraDeck, [
  List<int> sideDeck = const <int>[],
]) {
  final duelDeckCount = mainDeck.length + extraDeck.length;
  if (duelDeckCount > 0xFFFFFFFF || sideDeck.length > 0xFFFFFFFF) {
    throw const YgoProtocolException('卡组数量超出协议范围');
  }
  final data = ByteData(8 + (duelDeckCount + sideDeck.length) * 4);
  data.setUint32(0, duelDeckCount, Endian.little);
  data.setUint32(4, sideDeck.length, Endian.little);
  var offset = 8;
  for (final code in <int>[...mainDeck, ...extraDeck, ...sideDeck]) {
    if (code < 0 || code > 0xFFFFFFFF) {
      throw const YgoProtocolException('卡片代码必须位于无符号三十二位范围');
    }
    data.setUint32(offset, code, Endian.little);
    offset += 4;
  }
  return data.buffer.asUint8List();
}

// 构建 CTOS_JOIN_GAME 使用的版本、房间和密码载荷
Uint8List buildJoinGamePayload({
  required String password,
  required int protocolVersion,
  int gameId = 0,
}) {
  if (protocolVersion < 0 || protocolVersion > 0xFFFFFFFF) {
    throw const YgoProtocolException('游戏协议版本必须位于无符号三十二位范围');
  }
  if (gameId < 0 || gameId > 0xFFFFFFFF) {
    throw const YgoProtocolException('房间编号必须位于无符号三十二位范围');
  }
  final result = ByteData(48);
  result.setUint32(0, protocolVersion, Endian.little);
  result.setUint32(4, gameId, Endian.little);
  result.buffer.asUint8List().setRange(8, 48, encodeUtf16LeFixed(password, 20));
  return result.buffer.asUint8List();
}

// 解析服务器错误类型以及兼容两种对齐方式的四字节错误代码
({int errorType, int? code}) parseServerErrorPayload(List<int> payload) {
  if (payload.isEmpty) {
    throw const YgoProtocolException('STOC_ERROR_MSG 载荷为空');
  }
  final bytes = Uint8List.fromList(payload);
  final view = ByteData.sublistView(bytes);
  if (bytes.length >= 8) {
    return (
      errorType: bytes.first,
      code: view.getUint32(4, Endian.little),
    );
  }
  if (bytes.length >= 5) {
    return (
      errorType: bytes.first,
      code: view.getUint32(1, Endian.little),
    );
  }
  return (errorType: bytes.first, code: null);
}

// 从加入房间载荷读取单打或双打模式
int parseRoomDuelMode(List<int> payload) {
  return payload.length >= 6 ? payload[5] : 0;
}

// 从大厅身份变化载荷读取座位和房主标记
({int player, bool isHost}) parseLobbyRolePayload(List<int> payload) {
  if (payload.isEmpty) {
    throw const YgoProtocolException('STOC_TYPE_CHANGE 载荷为空');
  }
  final playerType = payload.first;
  return (
    player: playerType & 0x0F,
    isHost: ((playerType >> 4) & 0x0F) != 0,
  );
}

// 从大厅玩家变化载荷读取原座位和目标状态
({int player, int state}) parseLobbyPlayerChangePayload(List<int> payload) {
  if (payload.isEmpty) {
    throw const YgoProtocolException('STOC_HS_PLAYER_CHANGE 载荷为空');
  }
  final status = payload.first;
  return (player: (status >> 4) & 0x0F, state: status & 0x0F);
}

// 构建猜拳获胜后选择先后攻的单字节载荷
Uint8List buildTpResultPayload({required bool preferSecond}) {
  return Uint8List.fromList(<int>[preferSecond ? 0 : 1]);
}

// 构建确认手牌或猜拳结果的单字节载荷
Uint8List buildHandResultPayload(int result) {
  if (result < 0 || result > 0xFF) {
    throw const YgoProtocolException('手牌结果必须是单字节值');
  }
  return Uint8List.fromList(<int>[result]);
}

// 解析 STOC_TIME_LIMIT 中的 Core 玩家编号和剩余秒数
({int player, int seconds}) parseTimeLimitPayload(List<int> payload) {
  if (payload.length < 3) {
    throw const YgoProtocolException('计时消息载荷长度不足');
  }
  final player = payload[0];
  if (player != 0 && player != 1) {
    throw YgoProtocolException('计时消息玩家编号非法: $player');
  }
  final offset = payload.length >= 4 ? 2 : 1;
  final seconds = payload[offset] | (payload[offset + 1] << 8);
  return (player: player, seconds: seconds);
}
