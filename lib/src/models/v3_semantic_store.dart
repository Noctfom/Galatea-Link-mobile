// Galatea Model Protocol V3 移动端语义知识库，将 GKG JSON 编译为低内存定长缓存

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const int _semanticCacheVersion = 1;
const int _semanticHeaderBytes = 16;
const int _semanticRecordBytes = 740;
const int _semanticEffectSlots = 8;
const int _bindingCacheVersion = 1;
const int _bindingHeaderBytes = 12;
const int _bindingRecordBytes = 12;

const Map<String, int> _raceMap = <String, int>{
  'RACE_WARRIOR': 0x1,
  'RACE_SPELLCASTER': 0x2,
  'RACE_FAIRY': 0x4,
  'RACE_FIEND': 0x8,
  'RACE_ZOMBIE': 0x10,
  'RACE_MACHINE': 0x20,
  'RACE_AQUA': 0x40,
  'RACE_PYRO': 0x80,
  'RACE_ROCK': 0x100,
  'RACE_WINDBEAST': 0x200,
  'RACE_PLANT': 0x400,
  'RACE_INSECT': 0x800,
  'RACE_THUNDER': 0x1000,
  'RACE_DRAGON': 0x2000,
  'RACE_BEAST': 0x4000,
  'RACE_BEASTWARRIOR': 0x8000,
  'RACE_DINOSAUR': 0x10000,
  'RACE_FISH': 0x20000,
  'RACE_SEASERPENT': 0x40000,
  'RACE_REPTILE': 0x80000,
  'RACE_PSYCHO': 0x100000,
  'RACE_DEVINE': 0x200000,
  'RACE_CREATORGOD': 0x400000,
  'RACE_WYRM': 0x800000,
  'RACE_CYBERSE': 0x1000000,
  'RACE_ILLUSION': 0x2000000,
};

const Map<String, int> _attributeMap = <String, int>{
  'ATTRIBUTE_EARTH': 0x01,
  'ATTRIBUTE_WATER': 0x02,
  'ATTRIBUTE_FIRE': 0x04,
  'ATTRIBUTE_WIND': 0x08,
  'ATTRIBUTE_LIGHT': 0x10,
  'ATTRIBUTE_DARK': 0x20,
  'ATTRIBUTE_DEVINE': 0x40,
};

const List<String> _requirementKeys = <String>[
  'locations',
  'phases',
  'types',
  'summon_types',
  'reasons',
  'positions',
];

class V3SemanticStore {
  // 从已安装模型目录加载或首次编译语义缓存
  static Future<V3SemanticStore?> open(String modelDirectory) async {
    final separator = Platform.pathSeparator;
    final knowledgePath = '$modelDirectory${separator}knowledge_base.json';
    final indexPath = '$modelDirectory${separator}code_embeddings_idx.json';
    final knowledgeExists = await File(knowledgePath).exists();
    final indexExists = await File(indexPath).exists();
    if (!knowledgeExists && !indexExists) return null;
    if (!knowledgeExists || !indexExists) {
      throw const FormatException('V3 语义资产不完整');
    }
    final cachePath = '$modelDirectory${separator}mobile_semantics_v1.bin';
    final bindingCachePath =
        '$modelDirectory${separator}mobile_effect_bindings_v1.bin';
    final preparedPaths = await Isolate.run(
      () => <String>[
        _prepareSemanticCache(knowledgePath, indexPath, cachePath),
        _prepareEffectBindingCache(knowledgePath, bindingCachePath),
      ],
    );
    final bytes = await File(preparedPaths[0]).readAsBytes();
    final bindingBytes = await File(preparedPaths[1]).readAsBytes();
    return V3SemanticStore._fromBytes(bytes, bindingBytes);
  }

  // 从已校验的紧凑缓存创建只读语义存储
  V3SemanticStore._fromBytes(Uint8List bytes, Uint8List bindingBytes)
    : _bytes = bytes,
      _view = ByteData.sublistView(bytes),
      _bindingBytes = bindingBytes,
      _bindingView = ByteData.sublistView(bindingBytes),
      recordCount = _validateSemanticBytes(bytes),
      bindingCount = _validateEffectBindingBytes(bindingBytes);

  final Uint8List _bytes;
  final ByteData _view;
  final Uint8List _bindingBytes;
  final ByteData _bindingView;
  final int recordCount;
  final int bindingCount;

  // 返回紧凑缓存占用的内存字节数
  int get byteLength => _bytes.lengthInBytes;

  // 返回运行时效果绑定缓存占用的内存字节数
  int get bindingByteLength => _bindingBytes.lengthInBytes;

  // 根据卡号和完整运行时描述编号返回已证明的零基效果槽
  int? resolveEffectSlot(int code, int runtimeDescription) {
    final pureCode = code & 0x7FFFFFFF;
    final description = runtimeDescription & 0xFFFFFFFF;
    if (pureCode <= 0 || description == 0) return null;
    var low = 0;
    var high = bindingCount - 1;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      final offset = _bindingHeaderBytes + middle * _bindingRecordBytes;
      final currentCode = _bindingView.getUint32(offset, Endian.little);
      final currentDescription = _bindingView.getUint32(
        offset + 4,
        Endian.little,
      );
      if (currentCode == pureCode && currentDescription == description) {
        return _bindingView.getUint8(offset + 8);
      }
      if (currentCode < pureCode ||
          currentCode == pureCode && currentDescription < description) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return null;
  }

  // 将指定卡号的八槽语义直接写入目标 V3 张量
  bool writeCard({
    required Map<String, Object> inputs,
    required String prefix,
    required int entityIndex,
    required int entityCapacity,
    required int code,
    int? focusedEffectSlot,
  }) {
    if (entityIndex < 0 || entityIndex >= entityCapacity || code <= 0) {
      return false;
    }
    final recordOffset = _findRecordOffset(code);
    if (recordOffset == null) return false;
    var source = recordOffset + 4;
    final category = inputs['${prefix}sem_category']! as Int32List;
    final requirements = inputs['${prefix}sem_req']! as Int32List;
    final setcodes = inputs['${prefix}sem_setcode']! as Int32List;
    final numbers = inputs['${prefix}sem_number']! as Float32List;
    final references = inputs['${prefix}sem_ref']! as Int32List;
    final races = inputs['${prefix}sem_race']! as Int32List;
    final attributes = inputs['${prefix}sem_attr']! as Int32List;
    final codeIndices = inputs['${prefix}sem_code_idx']! as Int64List;
    final mask = inputs['${prefix}sem_mask']! as List<bool>;

    final categoryBase = entityIndex * 64;
    for (var index = 0; index < 64; index++, source += 2) {
      category[categoryBase + index] = _view.getInt16(source, Endian.little);
    }
    final requirementBase = entityIndex * 128;
    for (var index = 0; index < 128; index++, source++) {
      requirements[requirementBase + index] = _view.getInt8(source);
    }
    final setcodeBase = entityIndex * 32;
    for (var index = 0; index < 32; index++, source += 2) {
      setcodes[setcodeBase + index] = _view.getInt16(source, Endian.little);
    }
    final numberBase = entityIndex * 32;
    for (var index = 0; index < 32; index++, source += 4) {
      numbers[numberBase + index] = _view.getFloat32(source, Endian.little);
    }
    final referenceBase = entityIndex * 32;
    for (var index = 0; index < 32; index++, source += 4) {
      references[referenceBase + index] = _view.getInt32(source, Endian.little);
    }
    final raceBase = entityIndex * 32;
    for (var index = 0; index < 32; index++, source += 2) {
      races[raceBase + index] = _view.getInt16(source, Endian.little);
    }
    final attributeBase = entityIndex * 32;
    for (var index = 0; index < 32; index++, source += 2) {
      attributes[attributeBase + index] = _view.getInt16(source, Endian.little);
    }
    final codeIndexBase = entityIndex * 8;
    for (var index = 0; index < 8; index++, source += 4) {
      codeIndices[codeIndexBase + index] = _view.getInt32(
        source,
        Endian.little,
      );
    }
    _writeSemanticMask(
      category,
      codeIndices,
      mask,
      entityIndex,
      focusedEffectSlot,
    );
    return true;
  }

  // 使用二分查找定位按卡号排序的定长记录
  int? _findRecordOffset(int code) {
    var low = 0;
    var high = recordCount - 1;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      final offset = _semanticHeaderBytes + middle * _semanticRecordBytes;
      final current = _view.getUint32(offset, Endian.little);
      if (current == code) return offset;
      if (current < code) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return null;
  }

  // 按 Core V3 规则生成普通或聚焦效果槽掩码
  static void _writeSemanticMask(
    Int32List categories,
    Int64List codeIndices,
    List<bool> masks,
    int entityIndex,
    int? focusedEffectSlot,
  ) {
    final maskBase = entityIndex * _semanticEffectSlots;
    var hasSemantic = false;
    for (var slot = 0; slot < _semanticEffectSlots; slot++) {
      final enabled =
          categories[entityIndex * 64 + slot * 8] != 0 ||
          codeIndices[entityIndex * 8 + slot] != 0;
      masks[maskBase + slot] = enabled;
      hasSemantic = hasSemantic || enabled;
    }
    if (!hasSemantic) masks[maskBase] = true;
    if (focusedEffectSlot != null &&
        focusedEffectSlot >= 0 &&
        focusedEffectSlot < _semanticEffectSlots &&
        masks[maskBase + focusedEffectSlot]) {
      for (var slot = 0; slot < _semanticEffectSlots; slot++) {
        masks[maskBase + slot] = slot == focusedEffectSlot;
      }
    }
  }
}

// 加载有效缓存或从语义 JSON 原子生成新缓存
String _prepareSemanticCache(
  String knowledgePath,
  String indexPath,
  String cachePath,
) {
  final cache = File(cachePath);
  if (cache.existsSync()) {
    try {
      _validateSemanticBytes(cache.readAsBytesSync());
      return cachePath;
    } catch (_) {
      cache.deleteSync();
    }
  }
  final knowledgeRaw = jsonDecode(File(knowledgePath).readAsStringSync());
  final indexRaw = jsonDecode(File(indexPath).readAsStringSync());
  if (knowledgeRaw is! Map || indexRaw is! Map) {
    throw const FormatException('V3 语义 JSON 根节点必须是对象');
  }
  final knowledge = knowledgeRaw.cast<String, dynamic>();
  final embeddingIndex = indexRaw.cast<String, dynamic>();
  final categories = <String, int>{'<PAD>': 0, '<UNK>': 1};
  final requirements = <String, int>{};
  for (final rawCard in knowledge.values) {
    if (rawCard is! Map) continue;
    for (final rawEffect in _asList(rawCard['effects'])) {
      if (rawEffect is! Map) continue;
      for (final rawCategory in _asList(rawEffect['categories'])) {
        if (rawCategory is String) {
          categories.putIfAbsent(rawCategory, () => categories.length);
        }
      }
      final rawRequirements = rawEffect['requirements'];
      if (rawRequirements is! Map) continue;
      for (final key in _requirementKeys) {
        for (final item in _asList(rawRequirements[key])) {
          if (item is String) {
            requirements.putIfAbsent(item, () => requirements.length);
          }
        }
      }
    }
  }
  final cardCodes =
      knowledge.keys
          .map(int.tryParse)
          .whereType<int>()
          .where((code) => code > 0)
          .toList()
        ..sort();
  final bytes = Uint8List(
    _semanticHeaderBytes + cardCodes.length * _semanticRecordBytes,
  );
  final view = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('GV3S'));
  view.setUint32(4, _semanticCacheVersion, Endian.little);
  view.setUint32(8, cardCodes.length, Endian.little);
  view.setUint32(12, _semanticRecordBytes, Endian.little);
  for (var index = 0; index < cardCodes.length; index++) {
    final code = cardCodes[index];
    final rawCard = knowledge['$code'];
    _writeSemanticRecord(
      view,
      _semanticHeaderBytes + index * _semanticRecordBytes,
      code,
      rawCard is Map ? rawCard : const <String, Object?>{},
      embeddingIndex,
      categories,
      requirements,
    );
  }
  final temporary = File('$cachePath.tmp');
  if (temporary.existsSync()) temporary.deleteSync();
  temporary.writeAsBytesSync(bytes, flush: true);
  try {
    temporary.renameSync(cachePath);
  } on FileSystemException {
    cache.writeAsBytesSync(bytes, flush: true);
    if (temporary.existsSync()) temporary.deleteSync();
  }
  return cachePath;
}

// 将一张卡的结构语义写成固定七百四十字节记录
void _writeSemanticRecord(
  ByteData view,
  int offset,
  int code,
  Map rawCard,
  Map<String, dynamic> embeddingIndex,
  Map<String, int> categories,
  Map<String, int> requirements,
) {
  view.setUint32(offset, code, Endian.little);
  final categoryValues = Int32List(64);
  final requirementValues = Int32List(128)..fillRange(0, 128, -1);
  final setcodeValues = Int32List(32);
  final numberValues = Float32List(32);
  final referenceValues = Int32List(32);
  final raceValues = Int32List(32);
  final attributeValues = Int32List(32);
  final codeIndexValues = Int32List(8);
  var fallbackSlot = 1;
  for (final rawEffect in _asList(rawCard['effects'])) {
    if (rawEffect is! Map) {
      fallbackSlot++;
      continue;
    }
    final slot = _parseInteger(rawEffect['slot']) ?? fallbackSlot;
    fallbackSlot++;
    final slotIndex = slot - 1;
    if (slotIndex < 0 || slotIndex >= 8) continue;
    var itemIndex = 0;
    for (final rawCategory in _asList(rawEffect['categories'])) {
      if (itemIndex >= 8) break;
      if (rawCategory is String) {
        categoryValues[slotIndex * 8 + itemIndex] =
            categories[rawCategory] ?? 1;
        itemIndex++;
      }
    }
    final rawRequirements = rawEffect['requirements'];
    if (rawRequirements is Map) {
      var requirementIndex = 0;
      for (final key in _requirementKeys) {
        for (final item in _asList(rawRequirements[key])) {
          final value = item is String ? requirements[item] : null;
          if (value != null && value < 128 && requirementIndex < 16) {
            requirementValues[slotIndex * 16 + requirementIndex] = value;
            requirementIndex++;
          }
        }
      }
      itemIndex = 0;
      for (final item in _asList(rawRequirements['setcodes'])) {
        if (itemIndex >= 4) break;
        final value = _parseSetcode(item);
        if (value != null) {
          setcodeValues[slotIndex * 4 + itemIndex] = value % 4096;
        }
        itemIndex++;
      }
      itemIndex = 0;
      for (final item in _asList(rawRequirements['races'])) {
        if (itemIndex >= 4) break;
        if (item is String && _raceMap.containsKey(item)) {
          raceValues[slotIndex * 4 + itemIndex] = _raceMap[item]! % 30;
        }
        itemIndex++;
      }
      itemIndex = 0;
      for (final item in _asList(rawRequirements['attributes'])) {
        if (itemIndex >= 4) break;
        if (item is String && _attributeMap.containsKey(item)) {
          attributeValues[slotIndex * 4 + itemIndex] =
              _attributeMap[item]! % 10;
        }
        itemIndex++;
      }
      var numberIndex = 0;
      var referenceIndex = 0;
      for (final item in _asList(rawRequirements['custom_numbers'])) {
        final value = _parseDouble(item);
        if (value == null) continue;
        if (value > 10000 && referenceIndex < 4) {
          referenceValues[slotIndex * 4 + referenceIndex] =
              (value.toInt() % 19990) + 10;
          referenceIndex++;
        } else if (numberIndex < 4) {
          numberValues[slotIndex * 4 + numberIndex] = value / 4000;
          numberIndex++;
        }
      }
    }
    final rawCodeIndex = embeddingIndex['${code}_$slotIndex'];
    if (rawCodeIndex is num) {
      codeIndexValues[slotIndex] = rawCodeIndex.toInt() + 1;
    }
  }
  var cursor = offset + 4;
  for (final value in categoryValues) {
    view.setInt16(cursor, value, Endian.little);
    cursor += 2;
  }
  for (final value in requirementValues) {
    view.setInt8(cursor, value);
    cursor++;
  }
  for (final value in setcodeValues) {
    view.setInt16(cursor, value, Endian.little);
    cursor += 2;
  }
  for (final value in numberValues) {
    view.setFloat32(cursor, value, Endian.little);
    cursor += 4;
  }
  for (final value in referenceValues) {
    view.setInt32(cursor, value, Endian.little);
    cursor += 4;
  }
  for (final value in raceValues) {
    view.setInt16(cursor, value, Endian.little);
    cursor += 2;
  }
  for (final value in attributeValues) {
    view.setInt16(cursor, value, Endian.little);
    cursor += 2;
  }
  for (final value in codeIndexValues) {
    view.setInt32(cursor, value, Endian.little);
    cursor += 4;
  }
  if (cursor != offset + _semanticRecordBytes) {
    throw const FormatException('V3 语义缓存记录长度计算错误');
  }
}

// 校验缓存头、记录尺寸和排序完整性
int _validateSemanticBytes(Uint8List bytes) {
  if (bytes.lengthInBytes < _semanticHeaderBytes ||
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'GV3S') {
    throw const FormatException('V3 语义缓存文件头无效');
  }
  final view = ByteData.sublistView(bytes);
  final version = view.getUint32(4, Endian.little);
  final count = view.getUint32(8, Endian.little);
  final recordBytes = view.getUint32(12, Endian.little);
  if (version != _semanticCacheVersion ||
      recordBytes != _semanticRecordBytes ||
      bytes.lengthInBytes != _semanticHeaderBytes + count * recordBytes) {
    throw const FormatException('V3 语义缓存版本或长度无效');
  }
  var previous = 0;
  for (var index = 0; index < count; index++) {
    final code = view.getUint32(
      _semanticHeaderBytes + index * recordBytes,
      Endian.little,
    );
    if (code <= previous) throw const FormatException('V3 语义缓存卡号未排序');
    previous = code;
  }
  return count;
}

// 从知识库构建卡号与完整运行时描述编号到效果槽的紧凑映射
String _prepareEffectBindingCache(String knowledgePath, String cachePath) {
  final cache = File(cachePath);
  if (cache.existsSync()) {
    try {
      _validateEffectBindingBytes(cache.readAsBytesSync());
      return cachePath;
    } on FormatException {
      cache.deleteSync();
    }
  }
  final knowledgeRaw = jsonDecode(File(knowledgePath).readAsStringSync());
  if (knowledgeRaw is! Map) {
    throw const FormatException('V3 语义知识库必须是 JSON 对象');
  }
  final bindings = <(int, int), int>{};
  for (final entry in knowledgeRaw.entries) {
    final code = int.tryParse('${entry.key}');
    final rawCard = entry.value;
    if (code == null || code <= 0 || rawCard is! Map) continue;
    var fallbackSlot = 1;
    for (final rawEffect in _asList(rawCard['effects'])) {
      if (rawEffect is! Map) {
        fallbackSlot++;
        continue;
      }
      final slot = _parseInteger(rawEffect['slot']) ?? fallbackSlot;
      fallbackSlot++;
      final slotIndex = slot - 1;
      final descriptions = _asList(rawEffect['runtime_desc_ids']);
      if (descriptions.isNotEmpty && (slotIndex < 0 || slotIndex >= 8)) {
        throw FormatException('卡片 $code 的运行时效果槽超出 V3 范围');
      }
      for (final rawDescription in descriptions) {
        final description = _parseInteger(rawDescription);
        if (description == null ||
            description <= 0 ||
            description > 0xFFFFFFFF) {
          throw FormatException('卡片 $code 包含无效运行时效果描述编号');
        }
        final key = (code & 0x7FFFFFFF, description);
        final previous = bindings[key];
        if (previous != null && previous != slotIndex) {
          throw FormatException('卡片 $code 的运行时效果描述映射到多个槽');
        }
        bindings[key] = slotIndex;
      }
    }
  }
  final entries = bindings.entries.toList(growable: false)
    ..sort((left, right) {
      final codeOrder = left.key.$1.compareTo(right.key.$1);
      return codeOrder != 0 ? codeOrder : left.key.$2.compareTo(right.key.$2);
    });
  final bytes = Uint8List(
    _bindingHeaderBytes + entries.length * _bindingRecordBytes,
  );
  final view = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('GV3B'));
  view.setUint32(4, _bindingCacheVersion, Endian.little);
  view.setUint32(8, entries.length, Endian.little);
  for (var index = 0; index < entries.length; index++) {
    final offset = _bindingHeaderBytes + index * _bindingRecordBytes;
    final entry = entries[index];
    view.setUint32(offset, entry.key.$1, Endian.little);
    view.setUint32(offset + 4, entry.key.$2, Endian.little);
    view.setUint8(offset + 8, entry.value);
  }
  final temporary = File('$cachePath.tmp');
  if (temporary.existsSync()) temporary.deleteSync();
  temporary.writeAsBytesSync(bytes, flush: true);
  try {
    temporary.renameSync(cachePath);
  } on FileSystemException {
    cache.writeAsBytesSync(bytes, flush: true);
    if (temporary.existsSync()) temporary.deleteSync();
  }
  return cachePath;
}

// 校验效果绑定缓存的文件头、排序和槽位边界
int _validateEffectBindingBytes(Uint8List bytes) {
  if (bytes.lengthInBytes < _bindingHeaderBytes ||
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'GV3B') {
    throw const FormatException('V3 效果绑定缓存文件头无效');
  }
  final view = ByteData.sublistView(bytes);
  final version = view.getUint32(4, Endian.little);
  final count = view.getUint32(8, Endian.little);
  if (version != _bindingCacheVersion ||
      bytes.lengthInBytes !=
          _bindingHeaderBytes + count * _bindingRecordBytes) {
    throw const FormatException('V3 效果绑定缓存版本或长度无效');
  }
  var previousCode = -1;
  var previousDescription = -1;
  for (var index = 0; index < count; index++) {
    final offset = _bindingHeaderBytes + index * _bindingRecordBytes;
    final code = view.getUint32(offset, Endian.little);
    final description = view.getUint32(offset + 4, Endian.little);
    final slot = view.getUint8(offset + 8);
    if (code == 0 ||
        description == 0 ||
        slot >= 8 ||
        code < previousCode ||
        code == previousCode && description <= previousDescription) {
      throw const FormatException('V3 效果绑定缓存记录无效或未排序');
    }
    previousCode = code;
    previousDescription = description;
  }
  return count;
}

// 将动态 JSON 数组安全转换为空或列表
List<dynamic> _asList(Object? value) {
  return value is List ? value : const <dynamic>[];
}

// 将动态数值解析为整数
int? _parseInteger(Object? value) {
  if (value is num) return value.toInt();
  return value is String ? int.tryParse(value) : null;
}

// 将十六进制或十进制字段解析为原型编码
int? _parseSetcode(Object? value) {
  if (value is num) return value.toInt();
  if (value is! String) return null;
  return value.toLowerCase().startsWith('0x')
      ? int.tryParse(value.substring(2), radix: 16)
      : int.tryParse(value);
}

// 将动态数值解析为双精度浮点数
double? _parseDouble(Object? value) {
  if (value is num) return value.toDouble();
  return value is String ? double.tryParse(value) : null;
}
