// 移动端决策编排测试，验证被服务器拒绝的响应不会再次提交

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:galatea_link_mobile/src/app_decision_settings.dart';
import 'package:galatea_link_mobile/src/decision/decision_catalog.dart';
import 'package:galatea_link_mobile/src/decision/llm_decision_client.dart';
import 'package:galatea_link_mobile/src/decision/mobile_decision_engine.dart';
import 'package:galatea_link_mobile/src/game_state.dart';

void main() {
  // 验证默认拒绝被排除后会选择剩余的同意响应
  test('excludes rejected response from retry', () async {
    final engine = MobileDecisionEngine();
    const action = PendingAction(type: 13, player: 0, options: <int>[0, 1]);
    final rejected = DecisionCatalog.build(action).first.payload;

    final result = await engine.decide(
      settings: MobileDecisionSettings.defaults(),
      apiKey: '',
      gameState: MobileGameState(),
      action: action,
      excludedPayloadKeys: <String>{DecisionCatalog.payloadKey(rejected)},
    );

    expect(result.response?.payload, [1, 0, 0, 0]);
    expect(result.source, 'deterministic');
    engine.close();
  });

  // 验证仅 Core 模式即使保留 LLM 开关也绝不会发起网络请求
  test('core only never requests llm', () async {
    var requestCount = 0;
    final llmClient = LlmDecisionClient(
      client: MockClient((_) async {
        requestCount += 1;
        return http.Response('{}', 500);
      }),
    );
    final engine = MobileDecisionEngine(llmClient: llmClient);
    const settings = MobileDecisionSettings(
      mode: 'core_only',
      corePolicyMode: 'greedy',
      coreTemperature: 0.8,
      coreConfidenceThreshold: 0.65,
      llmEnabled: true,
      llmBaseUrl: 'https://example.test/v1',
      llmModel: 'must-not-be-called',
      llmTemperature: 0.1,
      llmTimeout: 5,
      llmGameChatEnabled: false,
      autonomyEnabled: false,
    );
    const action = PendingAction(type: 13, player: 0, options: <int>[0, 1]);

    final outcome = await engine.decide(
      settings: settings,
      apiKey: 'unused',
      gameState: MobileGameState(),
      action: action,
    );

    expect(requestCount, 0);
    expect(outcome.source, 'core_fallback');
    expect(outcome.response, isNotNull);
    engine.close();
  });

  // 验证编排器会把 LLM 临时介入建议交还给控制器
  test('forwards llm autonomous intervention update', () async {
    final llmClient = LlmDecisionClient(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'message': <String, Object?>{
                    'content': jsonEncode(<String, Object?>{
                      'choice_id': 1,
                      'reason': '测试临时介入',
                      'chat_message': null,
                      'intervention_update': <String, Object?>{
                        'mode': 'llm_review',
                        'core_confidence_threshold': null,
                        'force_llm_message_types': null,
                        'ttl_decisions': 2,
                        'reason': '复杂时点',
                        'base_revision': 3,
                      },
                    }),
                  },
                },
              ],
            }),
          ),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      ),
    );
    final engine = MobileDecisionEngine(llmClient: llmClient);
    const settings = MobileDecisionSettings(
      mode: 'llm_only',
      corePolicyMode: 'greedy',
      coreTemperature: 0.8,
      coreConfidenceThreshold: 0.65,
      llmEnabled: true,
      llmBaseUrl: 'https://example.test/v1',
      llmModel: 'test-model',
      llmTemperature: 0.1,
      llmTimeout: 5,
      llmGameChatEnabled: false,
      autonomyEnabled: true,
    );
    const action = PendingAction(type: 13, player: 0, options: <int>[0, 1]);

    final outcome = await engine.decide(
      settings: settings,
      apiKey: 'secret-key',
      gameState: MobileGameState(),
      action: action,
      runtimeControls: const <String, Object?>{'revision': 3},
    );

    expect(outcome.response?.payload, <int>[1, 0, 0, 0]);
    expect(outcome.interventionUpdate?.mode, 'llm_review');
    expect(outcome.interventionUpdate?.ttlDecisions, 2);
    engine.close();
  });
}
