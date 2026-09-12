// Galatea Link 移动端数据模型，映射稳定 API 和事件流结构

import 'dart:convert';

// 表示移动端与 Link 服务的连接阶段
enum LinkConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  unauthorized,
  error,
}

// 保存服务能力声明
class LinkCapabilities {
  const LinkCapabilities({
    required this.apiVersions,
    required this.gameProtocolProfile,
    required this.transports,
    required this.inferenceBackends,
    required this.modelManagement,
  });

  final List<String> apiVersions;
  final String gameProtocolProfile;
  final List<String> transports;
  final Map<String, dynamic> inferenceBackends;
  final Map<String, dynamic> modelManagement;

  // 从 API JSON 创建能力声明
  factory LinkCapabilities.fromJson(Map<String, dynamic> json) {
    return LinkCapabilities(
      apiVersions: _stringList(json['external_api_versions']),
      gameProtocolProfile:
          json['game_protocol_profile'] as String? ?? 'unknown',
      transports: _stringList(json['transports']),
      inferenceBackends: _map(json['inference_backends']),
      modelManagement: _map(json['model_management']),
    );
  }
}

// 保存 Link 服务的脱敏运行状态
class LinkStatus {
  const LinkStatus({
    required this.state,
    required this.running,
    required this.generation,
    required this.lastEventType,
    required this.lastError,
    required this.runtime,
    required this.configuredModel,
  });

  final String state;
  final bool running;
  final int generation;
  final String? lastEventType;
  final String? lastError;
  final Map<String, dynamic>? runtime;
  final Map<String, dynamic>? configuredModel;

  // 从 API JSON 创建服务状态
  factory LinkStatus.fromJson(Map<String, dynamic> json) {
    return LinkStatus(
      state: json['state'] as String? ?? 'unknown',
      running: json['running'] as bool? ?? false,
      generation: json['generation'] as int? ?? 0,
      lastEventType: json['last_event_type'] as String?,
      lastError: json['last_error'] as String?,
      runtime: _nullableMap(json['runtime']),
      configuredModel: _nullableMap(json['configured_model']),
    );
  }

  // 返回空闲状态供界面初始化使用
  factory LinkStatus.empty() {
    return const LinkStatus(
      state: 'unknown',
      running: false,
      generation: 0,
      lastEventType: null,
      lastError: null,
      runtime: null,
      configuredModel: null,
    );
  }
}

// 保存运行时策略和聊天设置及其 revision
class LinkControls {
  const LinkControls({
    required this.revision,
    required this.intervention,
    required this.baselineIntervention,
    required this.autonomy,
    required this.gameChat,
  });

  final int revision;
  final Map<String, dynamic> intervention;
  final Map<String, dynamic> baselineIntervention;
  final Map<String, dynamic> autonomy;
  final Map<String, dynamic> gameChat;

  // 从 API JSON 创建运行时控制快照
  factory LinkControls.fromJson(Map<String, dynamic> json) {
    return LinkControls(
      revision: json['revision'] as int? ?? 0,
      intervention: _map(json['intervention']),
      baselineIntervention: _map(json['baseline_intervention']),
      autonomy: _map(json['autonomy']),
      gameChat: _map(json['game_chat']),
    );
  }
}

// 保存一条 WebSocket 事件
class LinkEvent {
  const LinkEvent({
    required this.sequence,
    required this.eventType,
    required this.createdAt,
    required this.payload,
  });

  final int sequence;
  final String eventType;
  final DateTime? createdAt;
  final Map<String, dynamic> payload;

  // 从 WebSocket 事件 JSON 创建事件对象
  factory LinkEvent.fromJson(Map<String, dynamic> json) {
    final rawTime = json['created_at'];
    final timestamp = rawTime is num
        ? DateTime.fromMillisecondsSinceEpoch((rawTime * 1000).round())
        : null;
    return LinkEvent(
      sequence: json['sequence'] as int? ?? 0,
      eventType: json['event_type'] as String? ?? 'unknown',
      createdAt: timestamp,
      payload: _map(json['payload']),
    );
  }
}

// 保存游戏内聊天消息
class LinkChatMessage {
  const LinkChatMessage({
    required this.sequence,
    required this.direction,
    required this.role,
    required this.text,
    required this.source,
  });

  final int? sequence;
  final String direction;
  final String role;
  final String text;
  final String source;

  // 从 API JSON 创建聊天消息
  factory LinkChatMessage.fromJson(Map<String, dynamic> json) {
    return LinkChatMessage(
      sequence: json['sequence'] as int?,
      direction: json['direction'] as String? ?? 'inbound',
      role: json['role'] as String? ?? 'unknown',
      text: json['text'] as String? ?? '',
      source: json['source'] as String? ?? 'game_server',
    );
  }
}

// 将 API 返回的动态列表转换为字符串列表
List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().toList(growable: false);
}

// 将动态值转换为可变映射副本
Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

// 将动态值转换为可空映射
Map<String, dynamic>? _nullableMap(dynamic value) {
  if (value == null) {
    return null;
  }
  return _map(value);
}

// 格式化动态 JSON 供观察页和事件页安全显示
String formatJsonValue(dynamic value) {
  const encoder = JsonEncoder.withIndent('  ');
  try {
    return encoder.convert(value);
  } on JsonUnsupportedObjectError {
    return value.toString();
  }
}
