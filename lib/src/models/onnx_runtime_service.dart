// 移动端 ONNX Runtime 会话服务，负责加载模型并验证 V3 身份和原生推理

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'model_package_service.dart';
import 'v3_semantic_store.dart';
import 'v3_tensor_spec.dart';

const Set<String> expectedV3InputNames = <String>{
  'global',
  'card_idx',
  'card_overlay_idx',
  'card_race',
  'card_attr',
  'card_setcodes',
  'card_feats',
  'padding_mask',
  'sem_category',
  'sem_req',
  'sem_setcode',
  'sem_number',
  'sem_ref',
  'sem_race',
  'sem_attr',
  'sem_code_idx',
  'sem_mask',
  'deck_idx',
  'deck_race',
  'deck_attr',
  'deck_setcodes',
  'deck_mask',
  'd_sem_category',
  'd_sem_req',
  'd_sem_setcode',
  'd_sem_number',
  'd_sem_ref',
  'd_sem_race',
  'd_sem_attr',
  'd_sem_code_idx',
  'd_sem_mask',
  'c_mask',
  'c_card_idx',
  'c_desc',
  'c_context',
  'c_sem_category',
  'c_sem_req',
  'c_sem_setcode',
  'c_sem_number',
  'c_sem_ref',
  'c_sem_race',
  'c_sem_attr',
  'c_sem_code_idx',
  'c_sem_mask',
  'h_mask',
  'h_sem_category',
  'h_sem_req',
  'h_sem_setcode',
  'h_sem_number',
  'h_sem_ref',
  'h_sem_race',
  'h_sem_attr',
  'h_sem_code_idx',
  'h_sem_mask',
  'act_card_idx',
  'act_type',
  'act_desc',
  'act_effect_slot',
  'act_mask',
  'act_race',
  'act_attr',
  'act_code',
  'act_place',
  'act_operation',
  'act_response',
  'act_signature',
  'act_context',
  'act_target_code',
  'act_target_value',
  'act_controller',
  'act_location',
  'act_sequence',
};

const List<int> defaultV3MetaStaples = <int>[
  14558127,
  23434538,
  10045474,
  24094653,
  73642296,
  32807846,
];

// 从模型目录读取并规范化 MSG 142 卡名宣言兜底池
Future<List<int>> loadV3MetaStaples(String directoryPath) async {
  final file = File(
    '$directoryPath${Platform.pathSeparator}meta_staples.json',
  );
  if (!await file.exists()) {
    return defaultV3MetaStaples;
  }
  try {
    final source = (await file.readAsString()).replaceFirst('\ufeff', '');
    final decoded = jsonDecode(source);
    if (decoded is! List) return defaultV3MetaStaples;
    final normalized = <int>[];
    for (final value in decoded) {
      if (value is bool) continue;
      final code = value is num ? value.toInt() : int.tryParse('$value');
      if (code != null &&
          code > 0 &&
          code <= 0x0FFFFFFF &&
          !normalized.contains(code)) {
        normalized.add(code);
      }
    }
    return normalized.isEmpty
        ? defaultV3MetaStaples
        : List<int>.unmodifiable(normalized);
  } on Object {
    return defaultV3MetaStaples;
  }
}

const Set<String> expectedV3OutputNames = <String>{
  'action_logits',
  'values',
};

class OnnxModelHealth {
  const OnnxModelHealth({
    required this.modelId,
    required this.modelPrefix,
    required this.iteration,
    required this.modelProtocolVersion,
    required this.inputNames,
    required this.outputNames,
    required this.inputInfo,
    required this.outputInfo,
  });

  final String modelId;
  final String modelPrefix;
  final int iteration;
  final int modelProtocolVersion;
  final List<String> inputNames;
  final List<String> outputNames;
  final List<Map<String, dynamic>> inputInfo;
  final List<Map<String, dynamic>> outputInfo;
}

class OnnxInferenceProbe {
  // 保存一次最小原生推理自检的关键输出
  const OnnxInferenceProbe({
    required this.actionLogit,
    required this.value,
    required this.elapsed,
  });

  final double actionLogit;
  final double value;
  final Duration elapsed;
}

class OnnxInferenceResult {
  // 保存一次真实对局推理的动作分数价值和耗时
  const OnnxInferenceResult({
    required this.actionLogits,
    required this.value,
    required this.elapsed,
  });

  final List<double> actionLogits;
  final double value;
  final Duration elapsed;
}

class OnnxRuntimeService {
  OnnxRuntimeService({OnnxRuntime? runtime})
      : _runtime = runtime ?? OnnxRuntime();

  final OnnxRuntime _runtime;
  OrtSession? _session;
  InstalledOnnxModel? loadedModel;
  OnnxModelHealth? health;
  OnnxInferenceProbe? probe;
  V3SemanticStore? semanticStore;
  List<int> metaStaples = defaultV3MetaStaples;

  // 返回是否已有通过 V3 校验和最小推理自检的原生推理会话
  bool get isLoaded =>
      _session != null &&
      loadedModel != null &&
      health != null &&
      probe != null;

  // 不启动 ONNX 会话时预载所选 GKG 的轻量宣言资产
  Future<void> prepareModelAssets(InstalledOnnxModel model) async {
    metaStaples = await loadV3MetaStaples(model.directoryPath);
  }

  // 创建受控 CPU 会话并核验模型身份与完整张量签名
  Future<OnnxModelHealth> load(InstalledOnnxModel model) async {
    await close();
    final session = await _runtime.createSession(
      model.primaryPath,
      options: OrtSessionOptions(
        intraOpNumThreads: 2,
        interOpNumThreads: 1,
        providers: const <OrtProvider>[OrtProvider.CPU],
        useArena: true,
      ),
    );
    try {
      final metadata = await session.getMetadata();
      final custom = metadata.customMetadataMap;
      final modelHealth = OnnxModelHealth(
        modelId: custom['galatea.model_id'] ?? '',
        modelPrefix: custom['galatea.model_prefix'] ?? '',
        iteration: int.tryParse(custom['galatea.iteration'] ?? '') ?? -1,
        modelProtocolVersion:
            int.tryParse(custom['galatea.model_protocol_version'] ?? '') ?? -1,
        inputNames: List<String>.unmodifiable(session.inputNames),
        outputNames: List<String>.unmodifiable(session.outputNames),
        inputInfo: List<Map<String, dynamic>>.unmodifiable(
          await session.getInputInfo(),
        ),
        outputInfo: List<Map<String, dynamic>>.unmodifiable(
          await session.getOutputInfo(),
        ),
      );
      validateHealth(model.record, modelHealth);
      final semantics = await V3SemanticStore.open(model.directoryPath);
      final staples = await loadV3MetaStaples(model.directoryPath);
      _session = session;
      loadedModel = model;
      health = modelHealth;
      semanticStore = semantics;
      metaStaples = staples;
      return modelHealth;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  // 使用最小合法 V3 输入真正执行一次原生推理并检查输出
  Future<OnnxInferenceProbe> runCompatibilityProbe() async {
    final session = _session;
    if (session == null || health == null) {
      throw StateError('请先加载并校验 ONNX 模型');
    }
    final inputs = <String, OrtValue>{};
    Map<String, OrtValue>? outputs;
    final stopwatch = Stopwatch()..start();
    try {
      for (final entry in modelProtocolV3TensorSpecs.entries) {
        inputs[entry.key] = await _createProbeTensor(entry.key, entry.value);
      }
      outputs = await session.run(inputs);
      final logits = await outputs['action_logits']?.asFlattenedList();
      final values = await outputs['values']?.asFlattenedList();
      if (logits == null ||
          logits.length != 120 ||
          values == null ||
          values.length != 1) {
        throw const FormatException('ONNX 原生推理输出形状不符合 V3');
      }
      final actionLogit = (logits.first as num).toDouble();
      final value = (values.first as num).toDouble();
      if (!actionLogit.isFinite || !value.isFinite) {
        throw const FormatException('ONNX 原生推理输出包含 NaN 或无穷值');
      }
      stopwatch.stop();
      final result = OnnxInferenceProbe(
        actionLogit: actionLogit,
        value: value,
        elapsed: stopwatch.elapsed,
      );
      probe = result;
      return result;
    } finally {
      stopwatch.stop();
      for (final value in outputs?.values ?? const <OrtValue>[]) {
        await value.dispose();
      }
      for (final value in inputs.values) {
        await value.dispose();
      }
    }
  }

  // 使用完整 V3 输入运行一次本地模型推理
  Future<OnnxInferenceResult> run(Map<String, Object> data) async {
    final session = _session;
    if (session == null || health == null) {
      throw StateError('请先加载并校验 ONNX 模型');
    }
    if (data.keys.toSet().difference(expectedV3InputNames).isNotEmpty ||
        expectedV3InputNames.difference(data.keys.toSet()).isNotEmpty) {
      throw const FormatException('ONNX 推理输入不是完整 Model Protocol V3');
    }
    final inputs = <String, OrtValue>{};
    Map<String, OrtValue>? outputs;
    final stopwatch = Stopwatch()..start();
    try {
      for (final entry in modelProtocolV3TensorSpecs.entries) {
        inputs[entry.key] = await _createTensor(
          data[entry.key]!,
          entry.value,
        );
      }
      outputs = await session.run(inputs);
      final rawLogits = await outputs['action_logits']?.asFlattenedList();
      final rawValues = await outputs['values']?.asFlattenedList();
      if (rawLogits == null ||
          rawLogits.length != 120 ||
          rawValues == null ||
          rawValues.length != 1) {
        throw const FormatException('ONNX 对局推理输出形状不符合 V3');
      }
      final logits = rawLogits
          .map((value) => (value as num).toDouble())
          .toList(growable: false);
      final value = (rawValues.first as num).toDouble();
      if (logits.any((item) => !item.isFinite) || !value.isFinite) {
        throw const FormatException('ONNX 对局推理输出包含 NaN 或无穷值');
      }
      stopwatch.stop();
      return OnnxInferenceResult(
        actionLogits: List<double>.unmodifiable(logits),
        value: value,
        elapsed: stopwatch.elapsed,
      );
    } finally {
      stopwatch.stop();
      for (final value in outputs?.values ?? const <OrtValue>[]) {
        await value.dispose();
      }
      for (final value in inputs.values) {
        await value.dispose();
      }
    }
  }

  // 根据固定规格创建自检输入并处理插件不直接接受的窄类型
  static Future<OrtValue> _createProbeTensor(
    String name,
    V3TensorSpec spec,
  ) async {
    final data = _createProbeData(name, spec);
    return _createTensor(data, spec);
  }

  // 按 V3 目标类型创建原生张量并转换插件不直接接收的窄类型
  static Future<OrtValue> _createTensor(
    Object data,
    V3TensorSpec spec,
  ) async {
    final source = await OrtValue.fromList(data, spec.shape);
    final targetType = switch (spec.type) {
      V3TensorType.float16 => OrtDataType.float16,
      V3TensorType.int16 => OrtDataType.int16,
      V3TensorType.int8 => OrtDataType.int8,
      _ => null,
    };
    if (targetType == null) return source;
    try {
      return await source.to(targetType);
    } finally {
      await source.dispose();
    }
  }

  // 生成具有安全掩码和一个合法动作的最小 V3 自检数据
  static Object _createProbeData(String name, V3TensorSpec spec) {
    final count = spec.elementCount;
    switch (spec.type) {
      case V3TensorType.float32:
      case V3TensorType.float16:
        return Float32List(count);
      case V3TensorType.int64:
        final data = Int64List(count);
        if (name == 'act_card_idx') data.fillRange(0, count, 120);
        if (name == 'card_idx' || name == 'deck_idx') data[0] = 1;
        if (name == 'act_type') data[0] = 13;
        return data;
      case V3TensorType.int32:
        return Int32List(count);
      case V3TensorType.int16:
      case V3TensorType.int8:
        final data = Int32List(count);
        if (name.endsWith('sem_req')) data.fillRange(0, count, -1);
        if (name == 'act_response') data[0] = 1;
        return data;
      case V3TensorType.uint8:
        return Uint8List(count);
      case V3TensorType.boolean:
        final data = List<bool>.filled(count, false);
        if (name == 'padding_mask' ||
            name == 'deck_mask' ||
            name == 'act_mask') {
          data[0] = true;
        }
        if (name == 'sem_mask' || name.endsWith('_sem_mask')) {
          for (var index = 0; index < count; index += 8) {
            data[index] = true;
          }
        }
        return data;
    }
  }

  // 严格比较 GKG 身份记录与 ONNX 内嵌身份和 V3 输入输出
  static void validateHealth(
    GkgModelRecord record,
    OnnxModelHealth health,
  ) {
    if (health.modelId != record.modelId ||
        health.modelPrefix != record.modelPrefix ||
        health.iteration != record.iteration ||
        health.modelProtocolVersion != record.modelProtocolVersion) {
      throw const FormatException('ONNX 内嵌身份与 GKG 清单不一致');
    }
    if (health.modelProtocolVersion != supportedModelProtocolVersion) {
      throw FormatException(
        'ONNX 模型协议不兼容: ${health.modelProtocolVersion}',
      );
    }
    final inputs = health.inputNames.toSet();
    if (inputs.length != health.inputNames.length ||
        inputs.difference(expectedV3InputNames).isNotEmpty ||
        expectedV3InputNames.difference(inputs).isNotEmpty) {
      throw const FormatException('ONNX 输入签名不是完整 Model Protocol V3');
    }
    final outputs = health.outputNames.toSet();
    if (outputs.length != health.outputNames.length ||
        outputs.difference(expectedV3OutputNames).isNotEmpty ||
        expectedV3OutputNames.difference(outputs).isNotEmpty) {
      throw const FormatException('ONNX 输出签名不是 action_logits 和 values');
    }
  }

  // 释放当前原生推理会话和模型健康状态
  Future<void> close() async {
    final session = _session;
    _session = null;
    loadedModel = null;
    health = null;
    probe = null;
    semanticStore = null;
    metaStaples = defaultV3MetaStaples;
    await session?.close();
  }
}
