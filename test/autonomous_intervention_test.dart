// 移动端自主介入测试，验证人工护栏、版本校验和 TTL 自动恢复

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/app_decision_settings.dart';
import 'package:galatea_link_mobile/src/decision/autonomous_intervention.dart';

// 构建启用自主介入且限制范围的测试基线
MobileDecisionSettings guardedSettings({bool enabled = true}) {
  return MobileDecisionSettings(
    mode: 'hybrid',
    corePolicyMode: 'greedy',
    coreTemperature: 0.8,
    coreConfidenceThreshold: 0.65,
    llmEnabled: true,
    llmBaseUrl: 'https://example.test/v1',
    llmModel: 'test-model',
    llmTemperature: 0.1,
    llmTimeout: 30,
    llmGameChatEnabled: false,
    autonomyEnabled: enabled,
    forceLlmMessageTypes: const <int>[16],
    includeCoreSuggestion: true,
    llmTimeBudget: 8,
    autonomyAllowedModes: const <String>['hybrid', 'llm_review'],
    autonomyCoreConfidenceMin: 0.3,
    autonomyCoreConfidenceMax: 0.8,
    autonomyMaxTtlDecisions: 2,
    autonomyMaxForceMessageTypes: 2,
  );
}

void main() {
  // 验证合法临时覆盖只影响指定数量的后续动作
  test('applies guarded override and restores baseline after ttl', () {
    final runtime = MobileInterventionRuntime()..setBaseline(guardedSettings());
    final baseRevision = runtime.revision;

    final result = runtime.apply(
      MobileInterventionUpdate(
        mode: 'llm_review',
        coreConfidenceThreshold: 0.75,
        forceLlmMessageTypes: const <int>[16, 23],
        ttlDecisions: 9,
        reason: '复杂展开阶段临时复核',
        baseRevision: baseRevision,
      ),
    );

    expect(result.applied, isTrue);
    expect(runtime.effective.mode, 'llm_review');
    expect(runtime.effective.coreConfidenceThreshold, 0.75);
    expect(runtime.activeOverride?.remainingDecisions, 2);

    final first = runtime.onDecisionCommitted();
    expect(first.remainingDecisions, 1);
    expect(first.expired, isFalse);
    expect(runtime.effective.mode, 'llm_review');

    final second = runtime.onDecisionCommitted();
    expect(second.expired, isTrue);
    expect(runtime.activeOverride, isNull);
    expect(runtime.effective.mode, 'hybrid');
    expect(runtime.effective.coreConfidenceThreshold, 0.65);
    expect(runtime.effective.forceLlmMessageTypes, <int>[16]);
  });

  // 验证模式和置信度越过人工护栏时会拒绝建议
  test('rejects updates outside manual guardrails', () {
    final runtime = MobileInterventionRuntime()..setBaseline(guardedSettings());

    final modeResult = runtime.apply(
      MobileInterventionUpdate(
        mode: 'llm_only',
        ttlDecisions: 1,
        reason: '越界模式',
        baseRevision: runtime.revision,
      ),
    );
    expect(modeResult.applied, isFalse);
    expect(runtime.activeOverride, isNull);

    final thresholdResult = runtime.apply(
      MobileInterventionUpdate(
        coreConfidenceThreshold: 0.95,
        ttlDecisions: 1,
        reason: '越界阈值',
        baseRevision: runtime.revision,
      ),
    );
    expect(thresholdResult.applied, isFalse);
    expect(runtime.effective.coreConfidenceThreshold, 0.65);

    final forceTypesResult = runtime.apply(
      MobileInterventionUpdate(
        forceLlmMessageTypes: const <int>[16, 23, 26],
        ttlDecisions: 1,
        reason: '过多强制时点',
        baseRevision: runtime.revision,
      ),
    );
    expect(forceTypesResult.applied, isFalse);
    expect(runtime.effective.forceLlmMessageTypes, <int>[16]);
  });

  // 验证关闭开关或控制版本过期时不会创建覆盖
  test('rejects disabled and stale autonomous updates', () {
    final disabled = MobileInterventionRuntime()
      ..setBaseline(guardedSettings(enabled: false));
    final disabledResult = disabled.apply(
      MobileInterventionUpdate(
        mode: 'llm_review',
        ttlDecisions: 1,
        reason: '关闭状态',
        baseRevision: disabled.revision,
      ),
    );
    expect(disabledResult.applied, isFalse);

    final active = MobileInterventionRuntime()..setBaseline(guardedSettings());
    final staleResult = active.apply(
      MobileInterventionUpdate(
        mode: 'llm_review',
        ttlDecisions: 1,
        reason: '旧版本',
        baseRevision: active.revision - 1,
      ),
    );
    expect(staleResult.applied, isFalse);
    expect(active.activeOverride, isNull);
  });

  // 验证提示控制面同时公开生效值和人工护栏
  test('exposes effective controls and guardrails to llm', () {
    final runtime = MobileInterventionRuntime()..setBaseline(guardedSettings());
    final payload = runtime.toPromptJson();
    final intervention = payload['intervention'] as Map<String, Object?>;
    final autonomy = payload['autonomy'] as Map<String, Object?>;

    expect(intervention['mode'], 'hybrid');
    expect(intervention['force_llm_message_types'], <int>[16]);
    expect(autonomy['enabled'], isTrue);
    expect(autonomy['max_ttl_decisions'], 2);
  });
}
