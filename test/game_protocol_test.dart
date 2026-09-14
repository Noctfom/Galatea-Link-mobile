// YGOPro 协议基础测试，验证分包、边界和登录载荷不产生幻觉字节

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/game_protocol/byte_cursor.dart';
import 'package:galatea_link_mobile/src/game_protocol/frame_codec.dart';
import 'package:galatea_link_mobile/src/game_protocol/ygo_constants.dart';
import 'package:galatea_link_mobile/src/game_protocol/ygo_payloads.dart';

void main() {
  // 验证大厅座位房主标记和准备状态按高低半字节拆分
  test('parses lobby role and player state payloads', () {
    expect(
      parseLobbyRolePayload(<int>[0x10]),
      (player: 0, isHost: true),
    );
    expect(
      parseLobbyPlayerChangePayload(<int>[0x19]),
      (player: 1, state: playerChangeReady),
    );
    expect(parseRoomDuelMode(<int>[0, 0, 0, 0, 0, 2]), 2);
  });

  // 验证完整帧和跨 TCP 分片帧都能正确还原
  test('decodes complete and fragmented frames', () {
    final codec = YgoFrameCodec();
    final packet = codec.encode(stocTimeLimit, <int>[1, 0, 0x34, 0x12]);

    expect(codec.addChunk(packet.sublist(0, 2)), isEmpty);
    final frames = codec.addChunk(packet.sublist(2));

    expect(frames, hasLength(1));
    expect(frames.single.type, stocTimeLimit);
    expect(frames.single.payload, <int>[1, 0, 0x34, 0x12]);
  });

  // 验证连续帧在同一个 TCP 分片中保持顺序
  test('decodes consecutive frames', () {
    final codec = YgoFrameCodec();
    final first = codec.encode(stocSelectTp, const <int>[]);
    final second = codec.encode(stocDuelStart, <int>[0]);

    final frames = codec.addChunk(<int>[...first, ...second]);

    expect(frames.map((item) => item.type), [stocSelectTp, stocDuelStart]);
  });

  // 验证异常长度会拒绝并清空错位缓存
  test('rejects invalid frame length', () {
    final codec = YgoFrameCodec();

    expect(
      () => codec.addChunk(const <int>[0, 0]),
      throwsA(isA<YgoProtocolException>()),
    );
    expect(
        codec.addChunk(codec.encode(stocDuelEnd, const <int>[])), hasLength(1));
  });

  // 验证登录载荷使用协议要求的字段和密码布局
  test('builds join payload without extra byte', () {
    final payload = buildJoinGamePayload(
      password: '272129',
      protocolVersion: 0x1361,
      gameId: 9,
    );

    expect(payload, hasLength(48));
    expect(payload.sublist(0, 4), [0x61, 0x13, 0, 0]);
    expect(payload.sublist(4, 8), [9, 0, 0, 0]);
    expect(payload.sublist(8, 20),
        [0x32, 0, 0x37, 0, 0x32, 0, 0x31, 0, 0x32, 0, 0x39, 0]);
    expect(payload.sublist(20), everyElement(0));
  });

  // 验证玩家名称按 UTF-16 编码单元截断并零填充
  test('encodes fixed utf16 player info', () {
    final payload = buildPlayerInfoPayload('A龙');

    expect(payload, hasLength(40));
    expect(payload.sublist(0, 4), [0x41, 0, 0x99, 0x9F]);
  });

  // 验证游标读取小端整数并拒绝越界读取
  test('reads little endian values with strict bounds', () {
    final cursor = ByteCursor(Uint8List.fromList([1, 2, 3, 0xFE, 0xFF]));

    expect(cursor.readUint8(), 1);
    expect(cursor.readUint16Le(), 0x0302);
    expect(cursor.readInt16Le(), -2);
    cursor.requireEnd();
    expect(() => cursor.readUint8(), throwsA(isA<YgoProtocolException>()));
  });

  // 验证卡组载荷首计数包含主卡组和额外卡组且第二计数代表副卡组
  test('builds deck payload with combined duel deck count', () {
    final payload = buildDeckPayload(
      [100001, 100002],
      [200001, 200002, 200003],
      [300001],
    );
    final cursor = ByteCursor(payload);

    expect(cursor.readUint32Le(), 5);
    expect(cursor.readUint32Le(), 1);
    expect(
      List<int>.generate(6, (_) => cursor.readUint32Le()),
      [100001, 100002, 200001, 200002, 200003, 300001],
    );
    cursor.requireEnd();
  });

  // 验证三字节和四字节计时载荷均使用正确的秒数字段
  test('parses time limit payload variants', () {
    expect(
      parseTimeLimitPayload([1, 0x34, 0x12]),
      (player: 1, seconds: 0x1234),
    );
    expect(
      parseTimeLimitPayload([0, 0, 0x78, 0x56]),
      (player: 0, seconds: 0x5678),
    );
  });

  // 验证服务器版本错误兼容填充和紧凑两种代码布局
  test('parses aligned and compact server errors', () {
    expect(
      parseServerErrorPayload([4, 0, 0, 0, 0x67, 0x13, 0, 0]),
      (errorType: 4, code: 0x1367),
    );
    expect(
      parseServerErrorPayload([4, 0x68, 0x13, 0, 0]),
      (errorType: 4, code: 0x1368),
    );
    expect(
      parseServerErrorPayload([2]),
      (errorType: 2, code: null),
    );
  });

  // 验证卡组错误位域可以区分违规卡片和区域数量
  test('decodes detailed deck rejection fields', () {
    final banned = decodeDeckRejectionCode((1 << 28) | 89631139);
    final extraCount = decodeDeckRejectionCode((7 << 28) | 16);

    expect(banned.violation, 'lf_list');
    expect(banned.reason, contains('禁限卡表'));
    expect(banned.cardCode, 89631139);
    expect(banned.reportedCount, isNull);
    expect(extraCount.violation, 'extra_count');
    expect(extraCount.cardCode, isNull);
    expect(extraCount.reportedCount, 16);
  });
}
