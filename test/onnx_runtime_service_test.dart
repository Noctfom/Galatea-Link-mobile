// 移动端 ONNX 会话校验测试，验证 V3 身份和张量签名边界

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/models/model_package_service.dart';
import 'package:galatea_link_mobile/src/models/onnx_runtime_service.dart';

const GkgModelRecord record = GkgModelRecord(
  primary: 'galatea_iter_10.onnx',
  files: <String>['galatea_iter_10.onnx'],
  externalData: <String>[],
  modelId: '5381b6f8-b492-43b8-9f16-6957920826fa',
  modelPrefix: 'galatea',
  iteration: 10,
  modelProtocolVersion: 3,
);

// 构建具有完整 V3 签名的模型健康信息
OnnxModelHealth validHealth() {
  return const OnnxModelHealth(
    modelId: '5381b6f8-b492-43b8-9f16-6957920826fa',
    modelPrefix: 'galatea',
    iteration: 10,
    modelProtocolVersion: 3,
    inputNames: <String>[...expectedV3InputNames],
    outputNames: <String>[...expectedV3OutputNames],
    inputInfo: <Map<String, dynamic>>[],
    outputInfo: <Map<String, dynamic>>[],
  );
}

void main() {
  // 验证 GKG 的 142 宣言兜底池会去重过滤并兼容 UTF-8 BOM
  test('loads normalized model meta staples', () async {
    final root = Directory.systemTemp.createTempSync('galatea-staples-test-');
    try {
      await File('${root.path}${Platform.pathSeparator}meta_staples.json')
          .writeAsString('\ufeff[14558127, "23434538", 0, true, 14558127]');

      final staples = await loadV3MetaStaples(root.path);

      expect(staples, <int>[14558127, 23434538]);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  // 验证模型未携带兜底池时使用 Core V3 默认卡密
  test('uses default meta staples when model asset is absent', () async {
    final root = Directory.systemTemp.createTempSync('galatea-staples-empty-');
    try {
      expect(await loadV3MetaStaples(root.path), defaultV3MetaStaples);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  // 验证完整 V3 身份和输入输出签名可以通过
  test('accepts complete v3 signature', () {
    expect(
      () => OnnxRuntimeService.validateHealth(record, validHealth()),
      returnsNormally,
    );
  });

  // 验证缺少动作遮罩输入时拒绝创建可用会话
  test('rejects missing v3 input', () {
    final inputs = expectedV3InputNames
        .where((name) => name != 'act_mask')
        .toList(growable: false);
    final health = OnnxModelHealth(
      modelId: record.modelId,
      modelPrefix: record.modelPrefix,
      iteration: record.iteration,
      modelProtocolVersion: record.modelProtocolVersion,
      inputNames: inputs,
      outputNames: const <String>[...expectedV3OutputNames],
      inputInfo: const <Map<String, dynamic>>[],
      outputInfo: const <Map<String, dynamic>>[],
    );

    expect(
      () => OnnxRuntimeService.validateHealth(record, health),
      throwsA(isA<FormatException>()),
    );
  });

  // 验证 ONNX 内嵌模型身份与 GKG 清单不一致时拒绝
  test('rejects mismatched model identity', () {
    final health = OnnxModelHealth(
      modelId: record.modelId,
      modelPrefix: record.modelPrefix,
      iteration: 11,
      modelProtocolVersion: record.modelProtocolVersion,
      inputNames: const <String>[...expectedV3InputNames],
      outputNames: const <String>[...expectedV3OutputNames],
      inputInfo: const <Map<String, dynamic>>[],
      outputInfo: const <Map<String, dynamic>>[],
    );

    expect(
      () => OnnxRuntimeService.validateHealth(record, health),
      throwsA(isA<FormatException>()),
    );
  });
}
