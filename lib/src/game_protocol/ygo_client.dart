// YGOPro TCP 客户端，直接连接游戏服务器并广播可验证的服务器帧

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'byte_cursor.dart';
import 'frame_codec.dart';
import 'ygo_constants.dart';
import 'ygo_payloads.dart';

enum YgoClientState {
  disconnected,
  connecting,
  connected,
  failed,
}

class YgoServerMessage {
  const YgoServerMessage({required this.type, required this.payload});

  final int type;
  final Uint8List payload;
}

class YgoTcpClient {
  YgoTcpClient({
    required this.host,
    required this.port,
    this.protocolVersion = 0x1361,
    this.gameId = 0,
    this.connectTimeout = const Duration(seconds: 10),
  });

  final String host;
  final int port;
  final int protocolVersion;
  final int gameId;
  final Duration connectTimeout;
  final YgoFrameCodec _codec = YgoFrameCodec();
  final StreamController<YgoServerMessage> _messages =
      StreamController.broadcast();
  final StreamController<Object> _errors = StreamController.broadcast();
  final StreamController<void> _closed = StreamController.broadcast();
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  Future<void> _writeTail = Future<void>.value();
  YgoClientState state = YgoClientState.disconnected;

  // 广播服务器消息帧
  Stream<YgoServerMessage> get messages => _messages.stream;

  // 广播连接和解析错误
  Stream<Object> get errors => _errors.stream;

  // 广播服务器主动关闭当前 TCP 会话的事件
  Stream<void> get closed => _closed.stream;

  // 返回当前 TCP 是否已建立
  bool get isConnected => _socket != null && state == YgoClientState.connected;

  // 建立 YGOPro TCP 连接并启动分包读取
  Future<void> connect() async {
    if (state == YgoClientState.connecting || isConnected) {
      return;
    }
    state = YgoClientState.connecting;
    try {
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      _socket = socket;
      state = YgoClientState.connected;
      _subscription = socket.listen(
        _handleChunk,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );
    } catch (error) {
      state = YgoClientState.failed;
      _errors.add(error);
      rethrow;
    }
  }

  // 发送玩家名称到游戏服务器
  Future<void> sendPlayerInfo(String name) {
    return _send(ctosPlayerInfo, buildPlayerInfoPayload(name));
  }

  // 发送加入房间请求
  Future<void> sendJoinGame({required String password}) {
    return _send(
      ctosJoinGame,
      buildJoinGamePayload(
        password: password,
        protocolVersion: protocolVersion,
        gameId: gameId,
      ),
    );
  }

  // 发送猜拳获胜后的先后攻选择
  Future<void> sendTpResult({required bool preferSecond}) {
    return _send(
      ctosTpResult,
      buildTpResultPayload(preferSecond: preferSecond),
    );
  }

  // 发送手牌结果或猜拳结果
  Future<void> sendHandResult(int result) {
    return _send(ctosHandResult, buildHandResultPayload(result));
  }

  // 发送主卡组额外卡组和副卡组到游戏服务器
  Future<void> sendDeck(
    List<int> mainDeck,
    List<int> extraDeck, [
    List<int> sideDeck = const <int>[],
  ]) {
    return _send(
      ctosUpdateDeck,
      buildDeckPayload(mainDeck, extraDeck, sideDeck),
    );
  }

  // 发送准备信号
  Future<void> sendReady() {
    return _send(ctosHsReady, const <int>[]);
  }

  // 房主在全部决斗座位准备后发送开始对局信号
  Future<void> sendStartDuel() {
    return _send(ctosHsStart, const <int>[]);
  }

  // 发送游戏内聊天文本
  Future<void> sendChat(String text) {
    return _send(ctosChat, buildChatPayload(text));
  }

  // 发送当前决策响应载荷
  Future<void> sendResponse(List<int> payload) {
    return _send(ctosResponse, payload);
  }

  // 发送心跳时间确认
  Future<void> sendTimeConfirm() {
    return _send(ctosTimeConfirm, const <int>[]);
  }

  // 发送投降请求
  Future<void> surrender() {
    return _send(ctosSurrender, const <int>[]);
  }

  // 主动断开游戏服务器连接
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    state = YgoClientState.disconnected;
    _codec.clear();
    await socket?.close();
  }

  // 释放 TCP 客户端和事件流资源
  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _errors.close();
    await _closed.close();
  }

  // 以串行尾部保证多个协议包不会交叉写入
  Future<void> _send(int type, List<int> payload) {
    if (!isConnected) {
      throw const YgoProtocolException('尚未连接 YGOPro 游戏服务器');
    }
    final packet = _codec.encode(type, payload);
    _writeTail = _writeTail.then((_) async {
      final socket = _socket;
      if (socket == null || !isConnected) {
        throw const YgoProtocolException('YGOPro 连接已断开');
      }
      socket.add(packet);
      await socket.flush();
    });
    return _writeTail;
  }

  // 将任意 TCP 分片解码成完整服务器消息
  void _handleChunk(List<int> chunk) {
    try {
      for (final frame in _codec.addChunk(chunk)) {
        _messages
            .add(YgoServerMessage(type: frame.type, payload: frame.payload));
      }
    } catch (error) {
      _errors.add(error);
      unawaited(disconnect());
    }
  }

  // 记录底层 Socket 错误并结束当前连接
  void _handleSocketError(Object error) {
    _errors.add(error);
    state = YgoClientState.failed;
  }

  // 记录服务器关闭并更新客户端状态
  void _handleSocketDone() {
    _socket = null;
    state = YgoClientState.disconnected;
    _codec.clear();
    if (!_closed.isClosed) _closed.add(null);
  }
}
