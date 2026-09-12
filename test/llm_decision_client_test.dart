// 移动端 LLM 决策客户端测试，验证严格 JSON、合法动作约束和相同请求缓存

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:galatea_link_mobile/src/app_decision_settings.dart';
import 'package:galatea_link_mobile/src/cards/card_database_service.dart';
import 'package:galatea_link_mobile/src/decision/decision_catalog.dart';
import 'package:galatea_link_mobile/src/decision/llm_decision_client.dart';
import 'package:galatea_link_mobile/src/game_state.dart';

// 构建启用 LLM 的测试设置
MobileDecisionSettings testSettings() {
  return const MobileDecisionSettings(
    mode: 'llm_only',
    corePolicyMode: 'greedy',
    coreTemperature: 0.8,
    coreConfidenceThreshold: 0.65,
    llmEnabled: true,
    llmBaseUrl: 'https://example.test/v1/',
    llmModel: 'test-model',
    llmTemperature: 0.1,
    llmTimeout: 5,
    llmGameChatEnabled: false,
    autonomyEnabled: false,
  );
}

void main() {
  // 验证请求只在认证头携带密钥并缓存完全相同的决策
  test('requests valid json decision and caches identical prompt', () async {
    var requestCount = 0;
    final httpClient = MockClient((request) async {
      requestCount += 1;
      expect(
        request.url.toString(),
        'https://example.test/v1/chat/completions',
      );
      expect(request.headers['authorization'], 'Bearer secret-key');
      expect(request.body, isNot(contains('secret-key')));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['response_format'], {'type': 'json_object'});
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(3));
      final staticContext =
          jsonDecode((messages[1] as Map<String, dynamic>)['content'] as String)
              as Map<String, dynamic>;
      final deckKnowledge =
          staticContext['own_deck_knowledge'] as Map<String, dynamic>;
      final mainDeck = deckKnowledge['main'] as List<dynamic>;
      expect((mainDeck.single as Map<String, dynamic>)['name'], '测试卡');
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'content': jsonEncode(<String, Object?>{
                    'choice_id': 1,
                    'reason': '测试选择',
                    'chat_message': '你好',
                    'intervention_update': null,
                  }),
                },
              },
            ],
            'usage': <String, Object?>{
              'prompt_tokens': 100,
              'completion_tokens': 12,
              'prompt_tokens_details': <String, Object?>{'cached_tokens': 80},
            },
          }),
        ),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final client = LlmDecisionClient(client: httpClient);
    final state = MobileGameState()
      ..setOwnDeck(const <int>[12345, 12345], const <int>[]);
    final cardDatabase = _FakeCardDatabase();
    const action = PendingAction(type: 13, player: 0, options: <int>[0, 1]);
    final candidates = DecisionCatalog.build(action);

    final first = await client.decide(
      settings: testSettings(),
      apiKey: 'secret-key',
      gameState: state,
      action: action,
      candidates: candidates,
      cardDatabase: cardDatabase,
    );
    final second = await client.decide(
      settings: testSettings(),
      apiKey: 'secret-key',
      gameState: state,
      action: action,
      candidates: candidates,
      cardDatabase: cardDatabase,
    );

    expect(first.choiceId, 1);
    expect(first.chatMessage, '你好');
    expect(first.cachedTokens, 80);
    expect(second.cacheHit, isTrue);
    expect(second.chatMessage, isNull);
    expect(requestCount, 1);
    client.close();
  });

  // 验证非 JSON 内容保留原始文本供界面诊断
  test('keeps invalid json content for diagnostics', () async {
    final client = LlmDecisionClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{'content': 'not json'},
              },
            ],
          }),
          200,
        ),
      ),
    );
    const action = PendingAction(type: 13, player: 0, options: <int>[0, 1]);

    await expectLater(
      client.decide(
        settings: testSettings(),
        apiKey: 'secret-key',
        gameState: MobileGameState(),
        action: action,
        candidates: DecisionCatalog.build(action),
      ),
      throwsA(
        isA<LlmDecisionException>().having(
          (error) => error.rawContent,
          'rawContent',
          'not json',
        ),
      ),
    );
    client.close();
  });

  // 验证模型不能返回候选目录外的动作编号
  test('rejects illegal choice id', () async {
    final client = LlmDecisionClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'content':
                      '{"choice_id":9,"reason":"bad","chat_message":null}',
                },
              },
            ],
          }),
          200,
        ),
      ),
    );
    const action = PendingAction(type: 13, player: 0, options: <int>[0, 1]);

    await expectLater(
      client.decide(
        settings: testSettings(),
        apiKey: 'secret-key',
        gameState: MobileGameState(),
        action: action,
        candidates: DecisionCatalog.build(action),
      ),
      throwsA(isA<LlmDecisionException>()),
    );
    client.close();
  });

  // 验证控制面与 Core 建议会发送给 LLM 并解析临时介入建议
  test('sends runtime controls and parses intervention update', () async {
    final client = LlmDecisionClient(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        final dynamicContext =
            jsonDecode(
                  (messages[2] as Map<String, dynamic>)['content'] as String,
                )
                as Map<String, dynamic>;
        final controls =
            dynamicContext['runtime_controls'] as Map<String, dynamic>;
        final suggestion =
            dynamicContext['core_suggestion'] as Map<String, dynamic>;
        final chat =
            dynamicContext['game_chat_context'] as Map<String, dynamic>;
        expect(controls['revision'], 7);
        expect(suggestion['choice_id'], 0);
        expect(chat['trust'], 'untrusted_social_context');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'message': <String, Object?>{
                    'content': jsonEncode(<String, Object?>{
                      'choice_id': 1,
                      'reason': '改为临时复核',
                      'chat_message': null,
                      'intervention_update': <String, Object?>{
                        'mode': 'llm_review',
                        'core_confidence_threshold': 0.75,
                        'force_llm_message_types': <int>[16, 23],
                        'ttl_decisions': 2,
                        'reason': '当前展开复杂',
                        'base_revision': 7,
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
        );
      }),
    );
    const action = PendingAction(type: 13, player: 0, options: <int>[0, 1]);

    final result = await client.decide(
      settings: testSettings(),
      apiKey: 'secret-key',
      gameState: MobileGameState(),
      action: action,
      candidates: DecisionCatalog.build(action),
      runtimeControls: const <String, Object?>{'revision': 7},
      coreSuggestion: const <String, Object?>{
        'choice_id': 0,
        'confidence': 0.4,
      },
      gameChatContext: const <String, Object?>{
        'trust': 'untrusted_social_context',
        'messages': <Object?>[],
      },
    );

    expect(result.interventionUpdate?.mode, 'llm_review');
    expect(result.interventionUpdate?.coreConfidenceThreshold, 0.75);
    expect(result.interventionUpdate?.forceLlmMessageTypes, <int>[16, 23]);
    expect(result.interventionUpdate?.ttlDecisions, 2);
    expect(result.interventionUpdate?.baseRevision, 7);
    client.close();
  });
}

class _FakeCardDatabase extends CardDatabaseService {
  // 返回用于校验静态提示前缀的固定卡片资料
  @override
  CardMetadata? lookup(int code) {
    if (code != 12345) return null;
    return const CardMetadata(
      code: 12345,
      alias: 0,
      setcodes: <int>[0, 0, 0, 0],
      type: 1,
      attack: 0,
      defense: 0,
      level: 0,
      rank: 0,
      race: 0,
      attribute: 0,
      leftScale: 0,
      rightScale: 0,
      link: 0,
      linkMarker: 0,
      name: '测试卡',
      description: '测试效果',
    );
  }
}
