// YGOPro TCP 客户端测试，验证登录包发送和服务器分片接收

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/game_protocol/frame_codec.dart';
import 'package:galatea_link_mobile/src/game_protocol/ygo_client.dart';
import 'package:galatea_link_mobile/src/game_protocol/ygo_constants.dart';

void main() {
  // 验证客户端发送玩家信息和进房包并能解析分片服务器帧
  test('connects and exchanges framed messages', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final receivedFourFrames = Completer<void>();
    final receivedFrames = <YgoFrame>[];
    final responseSent = Completer<void>();
    final responseCodec = YgoFrameCodec();
    final inputCodec = YgoFrameCodec();
    server.listen((socket) {
      socket.listen((chunk) {
        try {
          final frames = inputCodec.addChunk(chunk);
          receivedFrames.addAll(frames);
          if (!responseSent.isCompleted && frames.isNotEmpty) {
            responseSent.complete();
            final response = responseCodec.encode(stocJoinGame, const <int>[]);
            socket.add(response.sublist(0, 2));
            Timer(const Duration(milliseconds: 5),
                () => socket.add(response.sublist(2)));
          }
          if (!receivedFourFrames.isCompleted && receivedFrames.length >= 4) {
            receivedFourFrames.complete();
          }
        } catch (error) {
          if (!receivedFourFrames.isCompleted) {
            receivedFourFrames.completeError(error);
          }
        }
      });
    });

    final client = YgoTcpClient(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );
    final message = client.messages.first;
    try {
      await client.connect();
      await client.sendPlayerInfo('Mobile');
      await client.sendJoinGame(password: '123456');
      await client.sendReady();
      await client.sendStartDuel();
      await receivedFourFrames.future.timeout(const Duration(seconds: 2));
      final serverMessage = await message.timeout(const Duration(seconds: 2));

      expect(receivedFrames.map((frame) => frame.type),
          [ctosPlayerInfo, ctosJoinGame, ctosHsReady, ctosHsStart]);
      expect(receivedFrames[0].payload.length, 40);
      expect(receivedFrames[1].payload.length, 48);
      expect(serverMessage.type, stocJoinGame);
      expect(serverMessage.payload, isEmpty);
    } finally {
      await client.dispose();
      await server.close();
    }
  });

  // 验证服务器主动结束会话时客户端广播关闭并立即释放连接状态
  test('reports remote socket close', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<Socket>();
    server.listen((socket) => accepted.complete(socket));
    final client = YgoTcpClient(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );
    final closed = client.closed.first;
    try {
      await client.connect();
      final socket = await accepted.future.timeout(const Duration(seconds: 2));
      await socket.close();
      await closed.timeout(const Duration(seconds: 2));

      expect(client.state, YgoClientState.disconnected);
      expect(client.isConnected, isFalse);
    } finally {
      await client.dispose();
      await server.close();
    }
  });
}
