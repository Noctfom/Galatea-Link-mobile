// 移动端异步决策编排器，在 LLM、确定性动作和规则回退之间选择安全响应

import '../app_decision_settings.dart';
import '../cards/card_database_service.dart';
import '../game_state.dart';
import '../models/onnx_runtime_service.dart';
import 'autonomous_intervention.dart';
import 'decision_catalog.dart';
import 'llm_decision_client.dart';
import 'onnx_decision_policy.dart';
import 'rule_fallback.dart';

class MobileDecisionOutcome {
  const MobileDecisionOutcome({
    required this.response,
    required this.source,
    required this.description,
    this.chatMessage,
    this.rawLlmContent,
    this.elapsed = Duration.zero,
    this.cacheHit = false,
    this.promptTokens,
    this.completionTokens,
    this.cachedTokens,
    this.coreConfidence,
    this.coreValue,
    this.interventionUpdate,
  });

  final RuleResponse? response;
  final String source;
  final String description;
  final String? chatMessage;
  final String? rawLlmContent;
  final Duration elapsed;
  final bool cacheHit;
  final int? promptTokens;
  final int? completionTokens;
  final int? cachedTokens;
  final double? coreConfidence;
  final double? coreValue;
  final MobileInterventionUpdate? interventionUpdate;
}

class MobileDecisionEngine {
  // 创建可选接入本地 ONNX 会话的异步决策编排器
  MobileDecisionEngine({
    LlmDecisionClient? llmClient,
    OnnxRuntimeService? onnxRuntimeService,
    OnnxDecisionPolicy? onnxPolicy,
    CardDatabaseService? cardDatabase,
  })  : _llmClient = llmClient ?? LlmDecisionClient(),
        _onnxRuntimeService = onnxRuntimeService,
        _onnxPolicy = onnxPolicy ?? OnnxDecisionPolicy(),
        _cardDatabase = cardDatabase;

  final LlmDecisionClient _llmClient;
  final OnnxRuntimeService? _onnxRuntimeService;
  final OnnxDecisionPolicy _onnxPolicy;
  final CardDatabaseService? _cardDatabase;

  // 根据模式异步选择动作并在 LLM 失败时回退到本地规则
  Future<MobileDecisionOutcome> decide({
    required MobileDecisionSettings settings,
    required String apiKey,
    required MobileGameState gameState,
    required PendingAction action,
    Set<String> excludedPayloadKeys = const <String>{},
    Map<String, Object?> runtimeControls = const <String, Object?>{},
    Map<String, Object?>? gameChatContext,
  }) async {
    final candidates = DecisionCatalog.build(
      action,
      cardDatabase: _cardDatabase,
      knownCodes: <int>{
        ...gameState.ownInitialDeckCodes,
        ...gameState.ownInitialExtraCodes,
        ...gameState.cards.map((card) => card.code),
        ...?_onnxRuntimeService?.metaStaples,
      },
    )
        .where(
          (candidate) => !excludedPayloadKeys.contains(
            DecisionCatalog.payloadKey(candidate.payload),
          ),
        )
        .toList(growable: false);
    final ruleFallback = MobileRuleFallback.decide(action);
    RuleResponse? fallback;
    if (ruleFallback != null &&
        !excludedPayloadKeys.contains(
          DecisionCatalog.payloadKey(ruleFallback.payload),
        )) {
      fallback = ruleFallback;
    } else if (candidates.isNotEmpty) {
      fallback = RuleResponse(
        payload: candidates.first.payload,
        description: candidates.first.label,
      );
    }
    if (candidates.isEmpty) {
      return const MobileDecisionOutcome(
        response: null,
        source: 'paused',
        description: '服务器拒绝后没有剩余的已验证响应',
      );
    }
    if (candidates.length == 1) {
      final candidate = candidates.single;
      return MobileDecisionOutcome(
        response: RuleResponse(
          payload: candidate.payload,
          description: candidate.label,
        ),
        source: 'deterministic',
        description: '当前仅有一个合法响应 ${candidate.label}',
      );
    }
    OnnxPolicyDecision? coreDecision;
    String? coreFailure;
    final runtime = _onnxRuntimeService;
    if (settings.mode != 'llm_only' && runtime?.isLoaded == true) {
      try {
        coreDecision = await _onnxPolicy.decide(
          runtime: runtime!,
          settings: settings,
          gameState: gameState,
          candidates: candidates,
          cardDatabase: _cardDatabase,
        );
      } catch (error) {
        coreFailure = error.toString();
      }
    }
    if (settings.mode == 'core_only') {
      if (coreDecision != null) return _asCoreOutcome(coreDecision);
      return MobileDecisionOutcome(
        response: fallback,
        source: fallback == null ? 'paused' : 'core_fallback',
        description: fallback == null
            ? '本地模型不可用且没有安全规则响应${coreFailure == null ? '' : ': $coreFailure'}'
            : '本地模型${runtime?.isLoaded == true ? '推理失败' : '尚未加载'}，已回退为 ${fallback.description}${coreFailure == null ? '' : ': $coreFailure'}',
      );
    }
    if (settings.mode == 'hybrid' && coreDecision != null) {
      if (!settings.llmEnabled ||
          (!settings.forceLlmMessageTypes.contains(action.type) &&
              coreDecision.confidence >= settings.coreConfidenceThreshold)) {
        return _asCoreOutcome(coreDecision);
      }
    }
    final useLlm = settings.llmEnabled &&
        const <String>{
          'hybrid',
          'llm_review',
          'llm_only',
        }.contains(settings.mode);
    if (!useLlm) {
      if (coreDecision != null) return _asCoreOutcome(coreDecision);
      return MobileDecisionOutcome(
        response: fallback,
        source: fallback == null ? 'paused' : 'rule',
        description: fallback?.description ?? '当前动作需要后续决策后端处理',
      );
    }
    try {
      final result = await _llmClient.decide(
        settings: settings,
        apiKey: apiKey,
        gameState: gameState,
        action: action,
        candidates: candidates,
        cardDatabase: _cardDatabase,
        runtimeControls: runtimeControls,
        gameChatContext: gameChatContext,
        coreSuggestion: settings.includeCoreSuggestion && coreDecision != null
            ? <String, Object?>{
                'choice_id': coreDecision.candidate.choiceId,
                'confidence': coreDecision.confidence,
                'selected_probability': coreDecision.selectedProbability,
                'value': coreDecision.value,
                'policy_mode': settings.corePolicyMode,
                'temperature': settings.coreTemperature,
              }
            : null,
      );
      final candidate = candidates.firstWhere(
        (candidate) => candidate.choiceId == result.choiceId,
      );
      return MobileDecisionOutcome(
        response: RuleResponse(
          payload: candidate.payload,
          description: result.reason,
        ),
        source: result.cacheHit ? 'llm_cache' : 'llm',
        description: result.reason,
        chatMessage: result.chatMessage,
        rawLlmContent: result.rawContent,
        elapsed: result.elapsed,
        cacheHit: result.cacheHit,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        cachedTokens: result.cachedTokens,
        coreConfidence: coreDecision?.confidence,
        coreValue: coreDecision?.value,
        interventionUpdate: result.interventionUpdate,
      );
    } on LlmDecisionException catch (error) {
      final coreFallback = coreDecision == null
          ? null
          : RuleResponse(
              payload: coreDecision.candidate.payload,
              description: coreDecision.candidate.label,
            );
      final selectedFallback = coreFallback ?? fallback;
      return MobileDecisionOutcome(
        response: selectedFallback,
        source: selectedFallback == null
            ? 'paused'
            : coreFallback == null
                ? 'llm_fallback'
                : 'llm_core_fallback',
        description: selectedFallback == null
            ? '${error.message} 且当前没有安全规则回退'
            : '${error.message} 已回退为 ${selectedFallback.description}',
        rawLlmContent: error.rawContent,
        coreConfidence: coreDecision?.confidence,
        coreValue: coreDecision?.value,
      );
    } catch (error) {
      final coreFallback = coreDecision == null
          ? null
          : RuleResponse(
              payload: coreDecision.candidate.payload,
              description: coreDecision.candidate.label,
            );
      final selectedFallback = coreFallback ?? fallback;
      return MobileDecisionOutcome(
        response: selectedFallback,
        source: selectedFallback == null
            ? 'paused'
            : coreFallback == null
                ? 'llm_fallback'
                : 'llm_core_fallback',
        description: selectedFallback == null
            ? 'LLM 决策异常 $error'
            : 'LLM 决策异常并回退为 ${selectedFallback.description}: $error',
        coreConfidence: coreDecision?.confidence,
        coreValue: coreDecision?.value,
      );
    }
  }

  // 将本地模型候选转换为可直接发送的统一决策结果
  static MobileDecisionOutcome _asCoreOutcome(OnnxPolicyDecision decision) {
    return MobileDecisionOutcome(
      response: RuleResponse(
        payload: decision.candidate.payload,
        description: decision.candidate.label,
      ),
      source: 'core_onnx',
      description:
          '本地 ONNX 选择 ${decision.candidate.label}，置信度 ${(decision.confidence * 100).toStringAsFixed(1)}%',
      elapsed: decision.elapsed,
      coreConfidence: decision.confidence,
      coreValue: decision.value,
    );
  }

  // 释放决策引擎持有的网络资源
  void close() {
    _llmClient.close();
  }
}
