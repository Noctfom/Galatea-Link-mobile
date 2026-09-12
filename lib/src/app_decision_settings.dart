// 移动端 Agent 设置模型，独立于 MDPro3 连接状态保存

class MobileDecisionSettings {
  const MobileDecisionSettings({
    required this.mode,
    required this.corePolicyMode,
    required this.coreTemperature,
    required this.coreConfidenceThreshold,
    required this.llmEnabled,
    required this.llmBaseUrl,
    required this.llmModel,
    required this.llmTemperature,
    required this.llmTimeout,
    required this.llmGameChatEnabled,
    required this.autonomyEnabled,
    this.forceLlmMessageTypes = const <int>[],
    this.includeCoreSuggestion = true,
    this.llmTimeBudget = 12,
    this.autonomyAllowedModes = const <String>[
      'core_only',
      'hybrid',
      'llm_review',
      'llm_only',
    ],
    this.autonomyCoreConfidenceMin = 0.2,
    this.autonomyCoreConfidenceMax = 0.9,
    this.autonomyMaxTtlDecisions = 3,
    this.autonomyMaxForceMessageTypes = 8,
  });

  final String mode;
  final String corePolicyMode;
  final double coreTemperature;
  final double coreConfidenceThreshold;
  final bool llmEnabled;
  final String llmBaseUrl;
  final String llmModel;
  final double llmTemperature;
  final double llmTimeout;
  final bool llmGameChatEnabled;
  final bool autonomyEnabled;
  final List<int> forceLlmMessageTypes;
  final bool includeCoreSuggestion;
  final double llmTimeBudget;
  final List<String> autonomyAllowedModes;
  final double autonomyCoreConfidenceMin;
  final double autonomyCoreConfidenceMax;
  final int autonomyMaxTtlDecisions;
  final int autonomyMaxForceMessageTypes;

  // 返回默认 Agent 设置
  factory MobileDecisionSettings.defaults() {
    return const MobileDecisionSettings(
      mode: 'core_only',
      corePolicyMode: 'greedy',
      coreTemperature: 0.8,
      coreConfidenceThreshold: 0.65,
      llmEnabled: false,
      llmBaseUrl: 'https://api.openai.com/v1',
      llmModel: '',
      llmTemperature: 0.1,
      llmTimeout: 30,
      llmGameChatEnabled: false,
      autonomyEnabled: false,
    );
  }

  // 复制人工基线设置并替换临时介入字段
  MobileDecisionSettings copyWith({
    String? mode,
    double? coreConfidenceThreshold,
    List<int>? forceLlmMessageTypes,
  }) {
    return MobileDecisionSettings(
      mode: mode ?? this.mode,
      corePolicyMode: corePolicyMode,
      coreTemperature: coreTemperature,
      coreConfidenceThreshold:
          coreConfidenceThreshold ?? this.coreConfidenceThreshold,
      llmEnabled: llmEnabled,
      llmBaseUrl: llmBaseUrl,
      llmModel: llmModel,
      llmTemperature: llmTemperature,
      llmTimeout: llmTimeout,
      llmGameChatEnabled: llmGameChatEnabled,
      autonomyEnabled: autonomyEnabled,
      forceLlmMessageTypes: List<int>.unmodifiable(
        forceLlmMessageTypes ?? this.forceLlmMessageTypes,
      ),
      includeCoreSuggestion: includeCoreSuggestion,
      llmTimeBudget: llmTimeBudget,
      autonomyAllowedModes: autonomyAllowedModes,
      autonomyCoreConfidenceMin: autonomyCoreConfidenceMin,
      autonomyCoreConfidenceMax: autonomyCoreConfidenceMax,
      autonomyMaxTtlDecisions: autonomyMaxTtlDecisions,
      autonomyMaxForceMessageTypes: autonomyMaxForceMessageTypes,
    );
  }
}
