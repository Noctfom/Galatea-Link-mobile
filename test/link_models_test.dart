// Galatea Link 移动端模型测试，验证 API JSON 到界面状态的转换

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/models/link_models.dart';

void main() {
  // 验证服务状态能够保留运行时和脱敏模型信息
  test('parses link status', () {
    final status = LinkStatus.fromJson({
      'state': 'running',
      'running': true,
      'generation': 2,
      'last_event_type': 'duel.started',
      'runtime': {'connected': true, 'duel_active': true},
      'configured_model': {'protocol': 'v3'},
    });

    expect(status.running, isTrue);
    expect(status.generation, 2);
    expect(status.runtime?['duel_active'], isTrue);
    expect(status.configuredModel?['protocol'], 'v3');
  });

  // 验证事件时间戳和动态 payload 可以安全解析
  test('parses event payload', () {
    final event = LinkEvent.fromJson({
      'sequence': 8,
      'event_type': 'game_chat.received',
      'created_at': 1700000000.25,
      'payload': {'role': 'opponent', 'text': '你好'},
    });

    expect(event.sequence, 8);
    expect(event.eventType, 'game_chat.received');
    expect(event.createdAt, isNotNull);
    expect(event.payload['text'], '你好');
  });

  // 验证未知 JSON 类型不会让模型构造过程崩溃
  test('normalizes malformed collections', () {
    final controls = LinkControls.fromJson({
      'revision': 3,
      'intervention': null,
      'autonomy': 'unknown',
    });

    expect(controls.revision, 3);
    expect(controls.intervention, isEmpty);
    expect(controls.autonomy, isEmpty);
  });
}
