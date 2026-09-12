// Galatea Link 移动端状态控制器，串联连接、控制、聊天和事件流

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/link_models.dart';
import '../services/link_api_client.dart';
import '../services/secure_settings_store.dart';

class LinkController extends ChangeNotifier {
  LinkController(
      {required LinkApiClient client, required SecureSettingsStore store})
      : _client = client,
        _store = store;

  final LinkApiClient _client;
  final SecureSettingsStore _store;
  LinkConnectionState connectionState = LinkConnectionState.disconnected;
  LinkStatus status = LinkStatus.empty();
  LinkCapabilities? capabilities;
  LinkControls? controls;
  List<LinkChatMessage> chatMessages = const <LinkChatMessage>[];
  List<LinkEvent> events = const <LinkEvent>[];
  Map<String, dynamic>? observation;
  String baseUrl = '';
  String token = '';
  String? errorMessage;
  bool isBusy = false;
  bool darkTheme = false;
  WebSocketChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  // 恢复本地连接设置和主题偏好
  Future<void> initialize() async {
    final saved = await _client.restoreSavedConfiguration();
    if (saved) {
      baseUrl = (await _store.readBaseUrl()) ?? '';
      token = (await _store.readToken()) ?? '';
    }
    darkTheme = await _store.readDarkTheme() ?? false;
    notifyListeners();
  }

  // 连接 Link 服务并读取首屏数据
  Future<void> connect({required String url, required String apiToken}) async {
    final normalizedUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalizedUrl.isEmpty) {
      throw const LinkApiException('请输入 Link 服务地址');
    }
    isBusy = true;
    errorMessage = null;
    connectionState = LinkConnectionState.connecting;
    notifyListeners();
    try {
      await _client.persistConfiguration(
          baseUrl: normalizedUrl, token: apiToken);
      baseUrl = normalizedUrl;
      token = apiToken.trim();
      await _loadSnapshot();
      await _openEventStream();
      connectionState = LinkConnectionState.connected;
      _reconnectAttempt = 0;
    } on LinkApiException catch (error) {
      connectionState = error.statusCode == 401
          ? LinkConnectionState.unauthorized
          : LinkConnectionState.error;
      errorMessage = error.message;
      rethrow;
    } catch (error) {
      connectionState = LinkConnectionState.error;
      errorMessage = error.toString();
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  // 刷新服务状态和当前控制快照
  Future<void> refresh() async {
    if (connectionState == LinkConnectionState.disconnected) {
      return;
    }
    try {
      await _loadSnapshot();
      if (status.running) {
        observation = await _client.observation();
      }
      errorMessage = null;
    } catch (error) {
      errorMessage = error.toString();
      rethrow;
    }
    notifyListeners();
  }

  // 启动远程 Link 游戏会话
  Future<void> startSession() async {
    await _runBusy(() async {
      status = await _client.startSession();
      await _loadSnapshot();
      observation = await _client.observation();
    });
  }

  // 停止远程 Link 游戏会话
  Future<void> stopSession() async {
    await _runBusy(() async {
      await _client.stopSession();
      await _loadSnapshot();
    });
  }

  // 按当前 revision 更新介入策略
  Future<void> updateControls(Map<String, dynamic> patch) async {
    final current = controls;
    if (current == null) {
      throw const LinkApiException('尚未读取运行时控制');
    }
    await _runBusy(() async {
      controls = await _client.updateControls(patch, current.revision);
    });
  }

  // 读取最新游戏聊天历史
  Future<void> refreshChat() async {
    chatMessages = await _client.chatHistory();
    notifyListeners();
  }

  // 发送一条游戏内聊天消息
  Future<void> sendChat(String text) async {
    await _runBusy(() async {
      await _client.sendChat(text.trim());
      await refreshChat();
    });
  }

  // 保存用户选择的深色主题
  Future<void> setDarkTheme(bool value) async {
    darkTheme = value;
    await _store.writeDarkTheme(value);
    notifyListeners();
  }

  // 断开移动端连接但不停止 Link 对局
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _eventChannel?.sink.close();
    _eventChannel = null;
    connectionState = LinkConnectionState.disconnected;
    notifyListeners();
  }

  // 释放网络连接和定时器资源
  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _eventSubscription?.cancel();
    _eventChannel?.sink.close();
    _client.close();
    super.dispose();
  }

  // 并行读取移动端首屏需要的远程数据
  Future<void> _loadSnapshot() async {
    final values = await Future.wait<dynamic>([
      _client.capabilities(),
      _client.status(),
      _client.controls(),
      _client.chatHistory(),
    ]);
    capabilities = values[0] as LinkCapabilities;
    status = values[1] as LinkStatus;
    controls = values[2] as LinkControls;
    chatMessages = values[3] as List<LinkChatMessage>;
    notifyListeners();
  }

  // 建立 WebSocket 并持续消费公开事件
  Future<void> _openEventStream() async {
    await _eventSubscription?.cancel();
    await _eventChannel?.sink.close();
    _eventChannel = await _client.connectEvents();
    _eventSubscription = _eventChannel!.stream.listen(
      _handleEventMessage,
      onError: _handleEventError,
      onDone: _handleEventDone,
      cancelOnError: false,
    );
  }

  // 解析 WebSocket 信封并更新事件缓冲
  void _handleEventMessage(dynamic rawMessage) {
    try {
      final envelope = _decodeMap(rawMessage);
      final event = _decodeMap(envelope['event']);
      if (event.isEmpty) {
        return;
      }
      final item = LinkEvent.fromJson(event);
      events = <LinkEvent>[item, ...events].take(300).toList(growable: false);
      _applyEventSideEffects(item);
      notifyListeners();
    } catch (error) {
      errorMessage = '事件解析失败：$error';
      notifyListeners();
    }
  }

  // 根据事件类型同步状态、聊天和观察数据
  void _applyEventSideEffects(LinkEvent event) {
    if (event.eventType == 'service.connected' &&
        event.payload['runtime'] is Map) {
      status = LinkStatus.fromJson(event.payload);
    }
    if (event.eventType == 'game_chat.received' ||
        event.eventType == 'game_chat.sent') {
      final message = LinkChatMessage.fromJson(event.payload);
      chatMessages = <LinkChatMessage>[message, ...chatMessages]
          .take(100)
          .toList(growable: false);
    }
    if (event.eventType == 'observation.updated' &&
        event.payload['observation'] is Map) {
      observation = _decodeMap(event.payload['observation']);
    }
    if (event.eventType == 'observation.updated') {
      unawaited(_refreshObservation());
    }
    if (event.eventType.startsWith('service.session.')) {
      unawaited(refresh());
    }
    if (event.eventType == 'runtime.controls.updated' ||
        event.eventType == 'service.controls.updated') {
      unawaited(refresh());
    }
  }

  // 记录 WebSocket 错误并安排自动重连
  void _handleEventError(Object error) {
    errorMessage = '事件流连接异常：$error';
    _scheduleReconnect();
    notifyListeners();
  }

  // 在事件流正常结束后安排自动重连
  void _handleEventDone() {
    if (connectionState != LinkConnectionState.disconnected) {
      connectionState = LinkConnectionState.reconnecting;
      _scheduleReconnect();
      notifyListeners();
    }
  }

  // 使用指数退避重建事件流连接
  void _scheduleReconnect() {
    if (_reconnectTimer != null || baseUrl.isEmpty) {
      return;
    }
    final exponent = _reconnectAttempt < 0
        ? 0
        : _reconnectAttempt > 5
            ? 5
            : _reconnectAttempt;
    final seconds = 1 << exponent;
    if (_reconnectAttempt < 6) {
      _reconnectAttempt += 1;
    }
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      _reconnectTimer = null;
      try {
        await _openEventStream();
        connectionState = LinkConnectionState.connected;
        await refresh();
      } catch (error) {
        errorMessage = error.toString();
        _scheduleReconnect();
      }
      notifyListeners();
    });
  }

  // 执行带统一忙碌状态和错误通知的异步动作
  Future<void> _runBusy(Future<void> Function() action) async {
    if (isBusy) {
      return;
    }
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      errorMessage = error.toString();
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  // 单独刷新最近观察避免重复读取其他面板
  Future<void> _refreshObservation() async {
    if (!status.running) {
      return;
    }
    try {
      observation = await _client.observation();
      notifyListeners();
    } catch (_) {
      return;
    }
  }

  // 将动态事件值转换为字符串键映射
  static Map<String, dynamic> _decodeMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String) {
      final decoded = value.isEmpty ? null : _tryJsonDecode(value);
      return _decodeMap(decoded);
    }
    return <String, dynamic>{};
  }

  // 尝试解析字符串形式的 JSON 事件
  static dynamic _tryJsonDecode(String value) {
    try {
      return value.isEmpty
          ? null
          : value.startsWith('{')
              ? _jsonDecode(value)
              : null;
    } catch (_) {
      return null;
    }
  }

  // 通过局部导入保持控制器模型依赖简单
  static dynamic _jsonDecode(String value) {
    return const JsonDecoder().convert(value);
  }
}
