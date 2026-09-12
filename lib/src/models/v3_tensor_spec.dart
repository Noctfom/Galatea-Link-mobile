// Galatea Model Protocol V3 固定张量规格，供移动端校验和构造原生推理输入

enum V3TensorType {
  float32,
  float16,
  int64,
  int32,
  int16,
  int8,
  uint8,
  boolean,
}

class V3TensorSpec {
  // 创建一个固定类型和形状的 V3 张量规格
  const V3TensorSpec(this.type, this.shape);

  final V3TensorType type;
  final List<int> shape;

  // 返回张量包含的固定元素数量
  int get elementCount => shape.fold(1, (total, value) => total * value);
}

const Map<String, V3TensorSpec> modelProtocolV3TensorSpecs =
    <String, V3TensorSpec>{
  'global': V3TensorSpec(V3TensorType.float32, <int>[1, 15]),
  'card_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'card_overlay_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'card_race': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'card_attr': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'card_setcodes': V3TensorSpec(V3TensorType.int64, <int>[1, 120, 4]),
  'card_feats': V3TensorSpec(V3TensorType.float32, <int>[1, 120, 66]),
  'padding_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 120]),
  'sem_category': V3TensorSpec(V3TensorType.int16, <int>[1, 120, 8, 8]),
  'sem_req': V3TensorSpec(V3TensorType.int8, <int>[1, 120, 8, 16]),
  'sem_setcode': V3TensorSpec(V3TensorType.int16, <int>[1, 120, 8, 4]),
  'sem_number': V3TensorSpec(V3TensorType.float16, <int>[1, 120, 8, 4]),
  'sem_ref': V3TensorSpec(V3TensorType.int32, <int>[1, 120, 8, 4]),
  'sem_race': V3TensorSpec(V3TensorType.int16, <int>[1, 120, 8, 4]),
  'sem_attr': V3TensorSpec(V3TensorType.int16, <int>[1, 120, 8, 4]),
  'sem_code_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 120, 8]),
  'sem_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 120, 8]),
  'deck_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 75]),
  'deck_race': V3TensorSpec(V3TensorType.int64, <int>[1, 75]),
  'deck_attr': V3TensorSpec(V3TensorType.int64, <int>[1, 75]),
  'deck_setcodes': V3TensorSpec(V3TensorType.int64, <int>[1, 75, 4]),
  'deck_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 75]),
  'd_sem_category': V3TensorSpec(V3TensorType.int16, <int>[1, 75, 8, 8]),
  'd_sem_req': V3TensorSpec(V3TensorType.int8, <int>[1, 75, 8, 16]),
  'd_sem_setcode': V3TensorSpec(V3TensorType.int16, <int>[1, 75, 8, 4]),
  'd_sem_number': V3TensorSpec(V3TensorType.float16, <int>[1, 75, 8, 4]),
  'd_sem_ref': V3TensorSpec(V3TensorType.int32, <int>[1, 75, 8, 4]),
  'd_sem_race': V3TensorSpec(V3TensorType.int16, <int>[1, 75, 8, 4]),
  'd_sem_attr': V3TensorSpec(V3TensorType.int16, <int>[1, 75, 8, 4]),
  'd_sem_code_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 75, 8]),
  'd_sem_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 75, 8]),
  'c_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 12]),
  'c_card_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 12]),
  'c_desc': V3TensorSpec(V3TensorType.int64, <int>[1, 12]),
  'c_context': V3TensorSpec(V3TensorType.float16, <int>[1, 12, 9]),
  'c_sem_category': V3TensorSpec(V3TensorType.int16, <int>[1, 12, 8, 8]),
  'c_sem_req': V3TensorSpec(V3TensorType.int8, <int>[1, 12, 8, 16]),
  'c_sem_setcode': V3TensorSpec(V3TensorType.int16, <int>[1, 12, 8, 4]),
  'c_sem_number': V3TensorSpec(V3TensorType.float16, <int>[1, 12, 8, 4]),
  'c_sem_ref': V3TensorSpec(V3TensorType.int32, <int>[1, 12, 8, 4]),
  'c_sem_race': V3TensorSpec(V3TensorType.int16, <int>[1, 12, 8, 4]),
  'c_sem_attr': V3TensorSpec(V3TensorType.int16, <int>[1, 12, 8, 4]),
  'c_sem_code_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 12, 8]),
  'c_sem_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 12, 8]),
  'h_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 8]),
  'h_sem_category': V3TensorSpec(V3TensorType.int16, <int>[1, 8, 8, 8]),
  'h_sem_req': V3TensorSpec(V3TensorType.int8, <int>[1, 8, 8, 16]),
  'h_sem_setcode': V3TensorSpec(V3TensorType.int16, <int>[1, 8, 8, 4]),
  'h_sem_number': V3TensorSpec(V3TensorType.float16, <int>[1, 8, 8, 4]),
  'h_sem_ref': V3TensorSpec(V3TensorType.int32, <int>[1, 8, 8, 4]),
  'h_sem_race': V3TensorSpec(V3TensorType.int16, <int>[1, 8, 8, 4]),
  'h_sem_attr': V3TensorSpec(V3TensorType.int16, <int>[1, 8, 8, 4]),
  'h_sem_code_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 8, 8]),
  'h_sem_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 8, 8]),
  'act_card_idx': V3TensorSpec(V3TensorType.int64, <int>[1, 120, 5]),
  'act_type': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'act_desc': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'act_effect_slot': V3TensorSpec(V3TensorType.uint8, <int>[1, 120]),
  'act_mask': V3TensorSpec(V3TensorType.boolean, <int>[1, 120]),
  'act_race': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'act_attr': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'act_code': V3TensorSpec(V3TensorType.int64, <int>[1, 120]),
  'act_place': V3TensorSpec(V3TensorType.int64, <int>[1, 120, 5]),
  'act_operation': V3TensorSpec(V3TensorType.uint8, <int>[1, 120]),
  'act_response': V3TensorSpec(V3TensorType.int16, <int>[1, 120]),
  'act_signature': V3TensorSpec(V3TensorType.uint8, <int>[1, 120, 4]),
  'act_context': V3TensorSpec(V3TensorType.float16, <int>[1, 120, 6]),
  'act_target_code': V3TensorSpec(V3TensorType.int32, <int>[1, 120, 5]),
  'act_target_value': V3TensorSpec(V3TensorType.uint8, <int>[1, 120, 5, 2]),
  'act_controller': V3TensorSpec(V3TensorType.uint8, <int>[1, 120]),
  'act_location': V3TensorSpec(V3TensorType.uint8, <int>[1, 120]),
  'act_sequence': V3TensorSpec(V3TensorType.uint8, <int>[1, 120]),
};
