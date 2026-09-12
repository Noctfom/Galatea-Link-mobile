// 移动端 V3 张量规格测试，锁定稳定模型协议的输入集合和关键形状

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/models/onnx_runtime_service.dart';
import 'package:galatea_link_mobile/src/models/v3_tensor_spec.dart';

void main() {
  // 验证固定张量规格完整覆盖稳定 ONNX 输入签名
  test('covers complete v3 input signature', () {
    expect(modelProtocolV3TensorSpecs.keys.toSet(), expectedV3InputNames);
  });

  // 验证关键动作和语义张量形状保持协议一致
  test('keeps v3 action and semantic shapes', () {
    expect(modelProtocolV3TensorSpecs['act_card_idx']?.shape, <int>[1, 120, 5]);
    expect(modelProtocolV3TensorSpecs['act_mask']?.shape, <int>[1, 120]);
    expect(modelProtocolV3TensorSpecs['sem_req']?.shape, <int>[1, 120, 8, 16]);
    expect(modelProtocolV3TensorSpecs['c_context']?.shape, <int>[1, 12, 9]);
  });

  // 验证元素数量计算不会漏乘批次和末级维度
  test('calculates tensor element count', () {
    expect(modelProtocolV3TensorSpecs['act_target_value']?.elementCount, 1200);
  });
}
