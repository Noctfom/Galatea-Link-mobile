// 移动端诊断日志测试，验证脱敏、过期清理和 JSONL 导出

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:galatea_link_mobile/src/services/diagnostic_log_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 验证认证字段在保存和导出前会被递归脱敏
  test('redacts sensitive fields from export', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = DiagnosticLogStore();
    await store.initialize();

    await store.record(
      'llm.request',
      data: <String, Object?>{
        'api_key': 'secret-key',
        'nested': <String, Object?>{'authorization': 'Bearer secret-key'},
        'model': 'test-model',
      },
    );
    final exported = await store.exportJsonLines();

    expect(exported, contains('[REDACTED]'));
    expect(exported, contains('test-model'));
    expect(exported, isNot(contains('secret-key')));
  });

  // 验证初始化时会删除超过保留期的旧日志
  test('removes expired logs during initialization', () async {
    final oldDate = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 30))
        .toIso8601String();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'galatea_mobile_diagnostic_logs_v1': jsonEncode(<Object?>[
        <String, Object?>{
          'created_at': oldDate,
          'level': 'info',
          'event': 'expired',
          'data': <String, Object?>{},
        },
      ]),
    });
    final store = DiagnosticLogStore();

    await store.initialize();

    expect(store.recent, isEmpty);
  });

  // 验证清空操作会同步删除近期日志
  test('clears recent logs', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = DiagnosticLogStore();
    await store.initialize();
    await store.record('duel.started');

    await store.clear();

    expect(store.recent, isEmpty);
  });
}
