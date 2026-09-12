// 移动端自主介入运行时，在人工护栏内应用有期限的 LLM 临时设置

import '../app_decision_settings.dart';

class MobileInterventionUpdate {
  const MobileInterventionUpdate({
    required this.ttlDecisions,
    required this.reason,
    required this.baseRevision,
    this.mode,
    this.coreConfidenceThreshold,
    this.forceLlmMessageTypes,
  });

  final String? mode;
  final double? coreConfidenceThreshold;
  final List<int>? forceLlmMessageTypes;
  final int ttlDecisions;
  final String reason;
  final int baseRevision;
}

class MobileAutonomousOverride {
  const MobileAutonomousOverride({
    required this.remainingDecisions,
    required this.reason,
    required this.originRevision,
  });

  final int remainingDecisions;
  final String reason;
  final int originRevision;

  // 复制临时覆盖并更新剩余动作数
  MobileAutonomousOverride withRemaining(int value) {
    return MobileAutonomousOverride(
      remainingDecisions: value,
      reason: reason,
      originRevision: originRevision,
    );
  }
}

class MobileInterventionApplyResult {
  const MobileInterventionApplyResult({required this.applied, this.reason});

  final bool applied;
  final String? reason;
}

class MobileInterventionProgress {
  const MobileInterventionProgress({
    required this.changed,
    required this.expired,
    this.remainingDecisions,
  });

  final bool changed;
  final bool expired;
  final int? remainingDecisions;
}

class MobileInterventionRuntime {
  MobileDecisionSettings _baseline = MobileDecisionSettings.defaults();
  MobileDecisionSettings _effective = MobileDecisionSettings.defaults();
  MobileAutonomousOverride? _activeOverride;
  int _revision = 0;

  MobileDecisionSettings get baseline => _baseline;
  MobileDecisionSettings get effective => _effective;
  MobileAutonomousOverride? get activeOverride => _activeOverride;
  int get revision => _revision;

  // 使用新人工设置替换基线并立即取消旧临时覆盖
  void setBaseline(MobileDecisionSettings settings) {
    _validateBaseline(settings);
    _baseline = settings;
    _effective = settings;
    _activeOverride = null;
    _revision += 1;
  }

  // 返回提供给 LLM 的当前控制面和人工护栏
  Map<String, Object?> toPromptJson() {
    return <String, Object?>{
      'revision': _revision,
      'intervention': <String, Object?>{
        'mode': _effective.mode,
        'core_confidence_threshold': _effective.coreConfidenceThreshold,
        'force_llm_message_types': _effective.forceLlmMessageTypes,
        'include_core_suggestion': _effective.includeCoreSuggestion,
        'llm_time_budget': _effective.llmTimeBudget,
      },
      'autonomy': <String, Object?>{
        'enabled': _baseline.autonomyEnabled,
        'allowed_modes': _baseline.autonomyAllowedModes,
        'core_confidence_min': _baseline.autonomyCoreConfidenceMin,
        'core_confidence_max': _baseline.autonomyCoreConfidenceMax,
        'max_ttl_decisions': _baseline.autonomyMaxTtlDecisions,
        'max_force_message_types': _baseline.autonomyMaxForceMessageTypes,
        'active_override': _activeOverride == null
            ? null
            : <String, Object?>{
                'remaining_decisions': _activeOverride!.remainingDecisions,
                'reason': _activeOverride!.reason,
                'origin_revision': _activeOverride!.originRevision,
              },
      },
    };
  }

  // 校验 LLM 建议并在护栏内创建后续动作临时覆盖
  MobileInterventionApplyResult apply(MobileInterventionUpdate update) {
    if (!_baseline.autonomyEnabled) {
      return const MobileInterventionApplyResult(
        applied: false,
        reason: '自主介入开关未启用',
      );
    }
    if (update.baseRevision != _revision) {
      return MobileInterventionApplyResult(
        applied: false,
        reason: '控制版本已变化 当前 $_revision 建议 ${update.baseRevision}',
      );
    }
    if (_activeOverride != null) {
      return const MobileInterventionApplyResult(
        applied: false,
        reason: '已有临时覆盖仍在有效期内',
      );
    }
    final mode = update.mode;
    if (mode != null && !_baseline.autonomyAllowedModes.contains(mode)) {
      return MobileInterventionApplyResult(
        applied: false,
        reason: '介入模式不在允许范围 $mode',
      );
    }
    final threshold = update.coreConfidenceThreshold;
    if (threshold != null &&
        (threshold < _baseline.autonomyCoreConfidenceMin ||
            threshold > _baseline.autonomyCoreConfidenceMax)) {
      return const MobileInterventionApplyResult(
        applied: false,
        reason: 'Core 置信度超出人工护栏',
      );
    }
    final forceTypes = update.forceLlmMessageTypes?.toSet().toList(
      growable: false,
    );
    if (forceTypes != null) {
      if (forceTypes.any((value) => value < 0 || value > 255)) {
        return const MobileInterventionApplyResult(
          applied: false,
          reason: '强制时点必须位于 0 到 255',
        );
      }
      if (forceTypes.length > _baseline.autonomyMaxForceMessageTypes) {
        return const MobileInterventionApplyResult(
          applied: false,
          reason: '强制时点数量超出人工护栏',
        );
      }
    }
    if (update.ttlDecisions < 1) {
      return const MobileInterventionApplyResult(
        applied: false,
        reason: 'TTL 必须大于零',
      );
    }
    final ttl = update.ttlDecisions
        .clamp(1, _baseline.autonomyMaxTtlDecisions)
        .toInt();
    _effective = _baseline.copyWith(
      mode: mode,
      coreConfidenceThreshold: threshold,
      forceLlmMessageTypes: forceTypes,
    );
    _activeOverride = MobileAutonomousOverride(
      remainingDecisions: ttl,
      reason: update.reason.length <= 500
          ? update.reason
          : update.reason.substring(0, 500),
      originRevision: _revision,
    );
    _revision += 1;
    return const MobileInterventionApplyResult(applied: true);
  }

  // 消耗当前临时覆盖的一次后续动作并在归零时恢复人工基线
  MobileInterventionProgress onDecisionCommitted() {
    final active = _activeOverride;
    if (active == null) {
      return const MobileInterventionProgress(changed: false, expired: false);
    }
    final remaining = active.remainingDecisions - 1;
    if (remaining > 0) {
      _activeOverride = active.withRemaining(remaining);
      return MobileInterventionProgress(
        changed: true,
        expired: false,
        remainingDecisions: remaining,
      );
    }
    _activeOverride = null;
    _effective = _baseline;
    _revision += 1;
    return const MobileInterventionProgress(
      changed: true,
      expired: true,
      remainingDecisions: 0,
    );
  }

  // 校验人工设置本身不会生成无效控制范围
  static void _validateBaseline(MobileDecisionSettings settings) {
    const modes = <String>{'core_only', 'hybrid', 'llm_review', 'llm_only'};
    if (!modes.contains(settings.mode)) {
      throw FormatException('未知介入模式 ${settings.mode}');
    }
    if (settings.autonomyAllowedModes.isEmpty ||
        settings.autonomyAllowedModes.any((mode) => !modes.contains(mode))) {
      throw const FormatException('自主介入至少需要一个有效模式');
    }
    if (settings.autonomyCoreConfidenceMin < 0 ||
        settings.autonomyCoreConfidenceMax > 1 ||
        settings.autonomyCoreConfidenceMin >
            settings.autonomyCoreConfidenceMax) {
      throw const FormatException('自主置信度护栏必须位于 0 到 1 且下限不高于上限');
    }
    if (settings.autonomyMaxTtlDecisions < 1 ||
        settings.autonomyMaxForceMessageTypes < 0) {
      throw const FormatException('自主介入 TTL 和强制时点上限无效');
    }
    if (settings.forceLlmMessageTypes.any(
      (value) => value < 0 || value > 255,
    )) {
      throw const FormatException('强制 LLM 时点必须位于 0 到 255');
    }
    if (settings.llmTimeBudget <= 0) {
      throw const FormatException('LLM 决策时间预算必须为正数');
    }
  }
}
