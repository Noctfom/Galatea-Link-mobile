// Galatea Link 移动端网络服务，封装 HTTP JSON 和 WebSocket 事件流

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import '../models/link_models.dart';
import 'secure_settings_store.dart';

class LinkApiException implements Exception {
  const LinkApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

class LinkApiClient {
  LinkApiClient({
    required SecureSettingsStore store,
    http.Client? httpClient,
  })  : _store = store,
        _httpClient = httpClient ?? http.Client();

  final SecureSettingsStore _store;
  final http.Client _httpClient;
  String _baseUrl = '';
  String _token = '';

  // 设置当前服务地址并清理末尾斜杠
  void configure({required String baseUrl, required String token}) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(normalized);
    if (parsed == null ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme)) {
      throw const LinkApiException('Link 地址必须是有效的 HTTP 或 HTTPS 地址');
    }
    if (parsed.userInfo.isNotEmpty ||
        parsed.query.isNotEmpty ||
        parsed.fragment.isNotEmpty) {
      throw const LinkApiException('Link 地址不能包含用户凭据、查询参数或片段');
    }
    _baseUrl = normalized;
    _token = token.trim();
  }

  // 从本地存储恢复上一次连接配置
  Future<bool> restoreSavedConfiguration() async {
    final baseUrl = await _store.readBaseUrl();
    final token = await _store.readToken();
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      return false;
    }
    configure(baseUrl: baseUrl, token: token ?? '');
    return true;
  }

  // 保存当前连接配置并写入安全令牌
  Future<void> persistConfiguration(
      {required String baseUrl, required String token}) async {
    configure(baseUrl: baseUrl, token: token);
    await _store.writeBaseUrl(_baseUrl);
    if (_token.isEmpty) {
      await _store.clearToken();
    } else {
      await _store.writeToken(_token);
    }
  }

  // 请求公开健康状态
  Future<Map<String, dynamic>> health() async {
    return _asMap(await _get('/api/v1/health'));
  }

  // 请求服务能力声明
  Future<LinkCapabilities> capabilities() async {
    return LinkCapabilities.fromJson(await _get('/api/v1/capabilities'));
  }

  // 请求脱敏服务状态
  Future<LinkStatus> status() async {
    return LinkStatus.fromJson(await _get('/api/v1/status'));
  }

  // 请求运行时控制快照
  Future<LinkControls> controls() async {
    return LinkControls.fromJson(await _get('/api/v1/controls'));
  }

  // 请求最近一次传递给 LLM 的可见观察
  Future<Map<String, dynamic>?> observation() async {
    final response = await _get('/api/v1/observation');
    if (response == null) {
      return null;
    }
    return _asMap(response);
  }

  // 启动 Link 游戏会话
  Future<LinkStatus> startSession() async {
    return LinkStatus.fromJson(await _post('/api/v1/session/start', const {}));
  }

  // 停止 Link 游戏会话
  Future<bool> stopSession() async {
    final response = await _post('/api/v1/session/stop', const {});
    return response['stopped'] as bool? ?? false;
  }

  // 按 revision 更新运行时控制
  Future<LinkControls> updateControls(
    Map<String, dynamic> patch,
    int expectedRevision,
  ) async {
    final response = await _patch('/api/v1/controls', {
      'patch': patch,
      'expected_revision': expectedRevision,
    });
    return LinkControls.fromJson(response);
  }

  // 读取游戏内聊天历史
  Future<List<LinkChatMessage>> chatHistory({int limit = 30}) async {
    final response = await _get('/api/v1/chat/history?limit=$limit');
    if (response is! List) {
      return const <LinkChatMessage>[];
    }
    return response
        .whereType<Map>()
        .map((item) => LinkChatMessage.fromJson(_asMap(item)))
        .toList(growable: false);
  }

  // 发送一条游戏内聊天消息
  Future<Map<String, dynamic>> sendChat(String text) async {
    return _asMap(await _post('/api/v1/chat', {'text': text}));
  }

  // 建立 Link WebSocket 事件流
  Future<WebSocketChannel> connectEvents() async {
    final parsed = Uri.tryParse(_baseUrl);
    if (parsed == null || parsed.host.isEmpty) {
      throw const LinkApiException('Link 地址无效');
    }
    final scheme = parsed.scheme == 'https' ? 'wss' : 'ws';
    final uri =
        parsed.replace(scheme: scheme, path: '/api/v1/events', query: '');
    final headers = _token.isEmpty
        ? <String, dynamic>{}
        : {'Authorization': 'Bearer $_token'};
    return IOWebSocketChannel.connect(uri, headers: headers);
  }

  // 关闭网络客户端
  void close() {
    _httpClient.close();
  }

  // 发起带统一响应展开的 GET 请求
  Future<dynamic> _get(String path) {
    return _request('GET', path);
  }

  // 发起带统一响应展开的 POST 请求
  Future<dynamic> _post(String path, Map<String, dynamic> body) {
    return _request('POST', path, body: body);
  }

  // 发起带统一响应展开的 PATCH 请求
  Future<dynamic> _patch(String path, Map<String, dynamic> body) {
    return _request('PATCH', path, body: body);
  }

  // 执行 HTTP 请求并转换 Link API 错误
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (_baseUrl.isEmpty) {
      throw const LinkApiException('尚未配置 Link 地址');
    }
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
    };
    late http.Response response;
    try {
      if (method == 'GET') {
        response = await _httpClient.get(uri, headers: headers);
      } else if (method == 'POST') {
        response = await _httpClient.post(uri,
            headers: headers, body: jsonEncode(body));
      } else {
        response = await _httpClient.patch(uri,
            headers: headers, body: jsonEncode(body));
      }
    } on Exception catch (error) {
      throw LinkApiException('无法连接 Link 服务：$error');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw LinkApiException('Link 返回了无法解析的响应',
          statusCode: response.statusCode);
    }
    if (response.statusCode >= 400) {
      final error =
          decoded is Map ? _asMap(decoded['error']) : <String, dynamic>{};
      throw LinkApiException(
        error['message'] as String? ?? 'Link 请求失败（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
        code: error['code'] as String?,
      );
    }
    if (decoded is! Map || !decoded.containsKey('data')) {
      throw const LinkApiException('Link 返回了无效响应结构');
    }
    return decoded['data'];
  }

  // 将动态映射安全转换为字符串键映射
  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }
}
