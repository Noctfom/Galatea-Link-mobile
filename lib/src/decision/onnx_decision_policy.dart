// 移动端 ONNX 决策策略，执行 V3 编码推理并按部署策略选择合法响应

import 'dart:math';

import '../app_decision_settings.dart';
import '../cards/card_database_service.dart';
import '../game_state.dart';
import '../models/onnx_runtime_service.dart';
import '../models/v3_feature_encoder.dart';
import 'decision_catalog.dart';

class OnnxPolicyDecision {
  // 保存本地模型选择结果和可解释的置信度指标
  const OnnxPolicyDecision({
    required this.candidate,
    required this.confidence,
    required this.selectedProbability,
    required this.value,
    required this.encodingElapsed,
    required this.elapsed,
  });

  final DecisionCandidate candidate;
  final double confidence;
  final double selectedProbability;
  final double value;
  final Duration encodingElapsed;
  final Duration elapsed;
}

class OnnxDecisionPolicy {
  // 创建支持可复现实验随机源的本地策略
  OnnxDecisionPolicy({V3FeatureEncoder? encoder, Random? random})
      : _encoder = encoder ?? V3FeatureEncoder(),
        _random = random ?? Random.secure();

  final V3FeatureEncoder _encoder;
  final Random _random;

  // 编码当前决策帧并从有效候选中选择模型动作
  Future<OnnxPolicyDecision> decide({
    required OnnxRuntimeService runtime,
    required MobileDecisionSettings settings,
    required MobileGameState gameState,
    required List<DecisionCandidate> candidates,
    CardDatabaseService? cardDatabase,
  }) async {
    if (candidates.isEmpty) {
      throw const FormatException('本地模型没有可选择的合法动作');
    }
    final encodingStopwatch = Stopwatch()..start();
    final batch = _encoder.encode(
      gameState,
      candidates,
      semanticStore: runtime.semanticStore,
      cardDatabase: cardDatabase,
    );
    encodingStopwatch.stop();
    final inference = await runtime.run(batch.inputs);
    final temperature = settings.coreTemperature.clamp(0.05, 2).toDouble();
    final logits = inference.actionLogits
        .take(batch.candidateCount)
        .map((value) => value / temperature)
        .toList(growable: false);
    final probabilities = _softmax(logits);
    final bestIndex = _maximumIndex(probabilities);
    final selectedIndex = settings.corePolicyMode == 'deployment'
        ? _sampleIndex(probabilities)
        : bestIndex;
    return OnnxPolicyDecision(
      candidate: candidates[selectedIndex],
      confidence: probabilities[bestIndex],
      selectedProbability: probabilities[selectedIndex],
      value: inference.value,
      encodingElapsed: encodingStopwatch.elapsed,
      elapsed: inference.elapsed,
    );
  }

  // 将有限动作分数稳定归一化为概率
  static List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) throw const FormatException('本地模型动作分数为空');
    final maximum = logits.reduce(max);
    final weights = logits.map((value) => exp(value - maximum)).toList();
    final total = weights.fold<double>(0, (sum, value) => sum + value);
    if (!total.isFinite || total <= 0) {
      throw const FormatException('本地模型动作概率无法归一化');
    }
    return weights.map((value) => value / total).toList(growable: false);
  }

  // 返回概率最高候选的索引
  static int _maximumIndex(List<double> probabilities) {
    var result = 0;
    for (var index = 1; index < probabilities.length; index++) {
      if (probabilities[index] > probabilities[result]) result = index;
    }
    return result;
  }

  // 按部署温度归一化后的概率抽取一个候选
  int _sampleIndex(List<double> probabilities) {
    final target = _random.nextDouble();
    var cumulative = 0.0;
    for (var index = 0; index < probabilities.length; index++) {
      cumulative += probabilities[index];
      if (target <= cumulative) return index;
    }
    return probabilities.length - 1;
  }
}
