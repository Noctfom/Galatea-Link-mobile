// 移动端滚动诊断日志，负责脱敏保存、按时间清理和生成 JSONL 导出内容

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DiagnosticLogEntry {
  const DiagnosticLogEntry({
    required this.createdAt,
    required this.level,
    required this.event,
    required this.data,
  });

  final DateTime createdAt;
  final String level;
  final String event;
  final Map<String, Object?> data;

  // 将日志条目转换为可持久化对象
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'created_at': createdAt.toUtc().toIso8601String(),
      'level': level,
      'event': event,
      'data': data,
    };
  }

  // 从持久化对象恢复日志条目
  static DiagnosticLogEntry? fromJson(Object? source) {
    if (source is! Map) return null;
    final json = Map<String, dynamic>.from(source);
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    final level = json['level'];
    final event = json['event'];
    if (createdAt == null || level is! String || event is! String) return null;
    final rawData = json['data'];
    final data = rawData is Map
        ? Map<String, Object?>.from(rawData)
        : const <String, Object?>{};
    return DiagnosticLogEntry(
      createdAt: createdAt,
      level: level,
      event: event,
      data: data,
    );
  }
}

class DiagnosticLogStore {
  static const Duration retention = Duration(days: 7);
  static const int maximumEntries = 1200;
  static const int maximumStoredCharacters = 1500000;
  static const Duration persistenceBatchDelay = Duration(milliseconds: 500);
  static const String _storageKey = 'galatea_mobile_diagnostic_logs_v1';

  SharedPreferences? _preferences;
  List<DiagnosticLogEntry> _entries = <DiagnosticLogEntry>[];
  Future<void> _writeTail = Future<void>.value();
  Timer? _persistTimer;
  bool _persistDirty = false;
  int _storedCharacters = 2;

  // 返回从新到旧排列的近期日志副本
  List<DiagnosticLogEntry> get recent =>
      List<DiagnosticLogEntry>.unmodifiable(_entries.reversed);

  // 加载日志并清理过期或超出容量的记录
  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    final source = preferences.getString(_storageKey);
    if (source != null && source.isNotEmpty) {
      try {
        final decoded = jsonDecode(source);
        if (decoded is List) {
          _entries = decoded
              .map(DiagnosticLogEntry.fromJson)
              .whereType<DiagnosticLogEntry>()
              .toList(growable: true);
        }
      } catch (_) {
        _entries = <DiagnosticLogEntry>[];
      }
    }
    _recalculateStoredCharacters();
    _trim();
    await _persist();
  }

  // 追加一条已脱敏日志并合并密集时段的本地持久化写入
  Future<void> record(
    String event, {
    String level = 'info',
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    final entry = DiagnosticLogEntry(
      createdAt: DateTime.now(),
      level: level,
      event: event,
      data: Map<String, Object?>.unmodifiable(
        _sanitizeMap(data),
      ),
    );
    if (_entries.isNotEmpty) _storedCharacters += 1;
    _entries.add(entry);
    _storedCharacters += _encodedEntryLength(entry);
    _trim();
    _persistDirty = true;
    _schedulePersist();
    return Future<void>.value();
  }

  // 清空设备上保存的全部诊断日志
  Future<void> clear() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persistDirty = false;
    _writeTail = _writeTail.then((_) async {
      _entries = <DiagnosticLogEntry>[];
      _storedCharacters = 2;
      await _persist();
    });
    return _writeTail;
  }

  // 等待现有写入完成并生成便于跨设备分析的 JSONL 文本
  Future<String> exportJsonLines() async {
    await _flushPendingPersist();
    final lines = <String>[
      jsonEncode(<String, Object?>{
        'schema': 'galatea.mobile.logs.v1',
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'retention_days': retention.inDays,
        'entry_count': _entries.length,
      }),
      ..._entries.map((entry) => jsonEncode(entry.toJson())),
    ];
    return lines.join('\n');
  }

  // 返回不会泄露密钥的日志导出文件名
  String exportFileName() {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'galatea-mobile-log-$stamp.jsonl';
  }

  // 删除过期记录并限制条目数量和序列化体积
  void _trim() {
    final cutoff = DateTime.now().toUtc().subtract(retention);
    final previousLength = _entries.length;
    _entries.removeWhere((entry) => entry.createdAt.toUtc().isBefore(cutoff));
    if (_entries.length != previousLength) _recalculateStoredCharacters();
    if (_entries.length > maximumEntries) {
      _entries.removeRange(0, _entries.length - maximumEntries);
      _recalculateStoredCharacters();
    }
    while (_entries.isNotEmpty && _storedCharacters > maximumStoredCharacters) {
      final removed = _entries.removeAt(0);
      _storedCharacters -= _encodedEntryLength(removed);
      if (_entries.isNotEmpty) _storedCharacters -= 1;
    }
  }

  // 延迟启动一次日志写入以合并同一批高频网络事件
  void _schedulePersist() {
    if (_persistTimer != null) return;
    _persistTimer = Timer(persistenceBatchDelay, () {
      _persistTimer = null;
      if (!_persistDirty) return;
      _persistDirty = false;
      _writeTail = _writeTail.then((_) => _persist());
    });
  }

  // 在导出前立即提交尚未落盘的诊断日志
  Future<void> _flushPendingPersist() {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (_persistDirty) {
      _persistDirty = false;
      _writeTail = _writeTail.then((_) => _persist());
    }
    return _writeTail;
  }

  // 重新计算当前日志数组的近似 JSON 字符数
  void _recalculateStoredCharacters() {
    _storedCharacters = 2;
    for (var index = 0; index < _entries.length; index++) {
      if (index > 0) _storedCharacters += 1;
      _storedCharacters += _encodedEntryLength(_entries[index]);
    }
  }

  // 返回单条日志序列化后的字符数
  static int _encodedEntryLength(DiagnosticLogEntry entry) {
    return jsonEncode(entry.toJson()).length;
  }

  // 将当前日志集合写入本地持久化存储
  Future<void> _persist() async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    _preferences = preferences;
    await preferences.setString(
      _storageKey,
      jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
    );
  }

  // 递归脱敏日志数据中的密码令牌和认证字段
  static Map<String, Object?> _sanitizeMap(Map source) {
    final result = <String, Object?>{};
    for (final entry in source.entries) {
      final key = entry.key.toString();
      result[key] =
          _isSensitiveKey(key) ? '[REDACTED]' : _sanitizeValue(entry.value);
    }
    return result;
  }

  // 将嵌套日志值转换为可安全 JSON 编码的结构
  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Map) return _sanitizeMap(value);
    if (value is Iterable) {
      return value.map(_sanitizeValue).toList(growable: false);
    }
    return value.toString();
  }

  // 判断日志字段名是否可能包含认证或房间机密
  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll('-', '_');
    if (normalized == 'tokens' ||
        normalized.endsWith('_tokens') ||
        normalized.endsWith('_token_count')) {
      return false;
    }
    return const <String>[
          'password',
          'passphrase',
          'api_key',
          'authorization',
          'secret',
          'credential',
        ].any(normalized.contains) ||
        normalized == 'token' ||
        normalized.startsWith('token_') ||
        normalized.endsWith('_token');
  }
}
