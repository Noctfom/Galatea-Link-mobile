// 移动端 YGOPro 卡片数据库服务，负责安全导入 CDB 并提供模型和 LLM 所需资料

import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class CardDatabaseInfo {
  // 保存一次卡片数据库结构检查结果
  const CardDatabaseInfo({
    required this.path,
    required this.dataCount,
    required this.textCount,
  });

  final String path;
  final int dataCount;
  final int textCount;
}

class CardMetadata {
  // 保存一张卡的静态规则字段和本地化文本
  const CardMetadata({
    required this.code,
    required this.alias,
    required this.setcodes,
    required this.type,
    required this.attack,
    required this.defense,
    required this.level,
    required this.rank,
    required this.race,
    required this.attribute,
    required this.leftScale,
    required this.rightScale,
    required this.link,
    required this.linkMarker,
    required this.name,
    required this.description,
  });

  final int code;
  final int alias;
  final List<int> setcodes;
  final int type;
  final int attack;
  final int defense;
  final int level;
  final int rank;
  final int race;
  final int attribute;
  final int leftScale;
  final int rightScale;
  final int link;
  final int linkMarker;
  final String name;
  final String description;

  // 转换为不包含数据库内部字段的 LLM 卡片知识
  Map<String, Object?> toPromptJson({bool includeDescription = true}) {
    return <String, Object?>{
      'code': code,
      'name': name,
      if (alias != 0) 'alias': alias,
      'type': type,
      'race': race,
      'attribute': attribute,
      'level': level,
      'rank': rank,
      'attack': attack,
      'defense': defense,
      if (leftScale != 0 || rightScale != 0) ...<String, Object?>{
        'left_scale': leftScale,
        'right_scale': rightScale,
      },
      if (link != 0) ...<String, Object?>{
        'link': link,
        'link_marker': linkMarker,
      },
      if (setcodes.any((value) => value != 0)) 'setcodes': setcodes,
      if (includeDescription) 'description': description,
    };
  }
}

class CardDatabaseService {
  // 创建支持注入应用目录的卡片数据库服务
  CardDatabaseService({
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const int _maximumCacheEntries = 512;
  final Future<Directory> Function() _supportDirectoryProvider;
  final LinkedHashMap<int, CardMetadata?> _cache =
      LinkedHashMap<int, CardMetadata?>();
  Database? _database;
  CardDatabaseInfo? info;

  // 返回卡片数据库是否已经通过结构检查并以只读方式打开
  bool get isLoaded => _database != null && info != null;

  // 加载应用私有目录中已经导入的卡片数据库
  Future<CardDatabaseInfo?> initialize() async {
    final target = await _targetFile();
    if (!await target.exists()) return null;
    try {
      return await _openValidated(target.path);
    } catch (_) {
      await close();
      return null;
    }
  }

  // 将用户选定的 CDB 检查后替换到应用私有目录
  Future<CardDatabaseInfo> installFrom(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists() || !sourcePath.toLowerCase().endsWith('.cdb')) {
      throw const FormatException('请选择可读取的 cards.cdb 文件');
    }
    final target = await _targetFile();
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.importing');
    if (await temporary.exists()) await temporary.delete();
    await source.copy(temporary.path);
    try {
      await Isolate.run(() => _inspectCardDatabase(temporary.path));
      await close();
      if (await target.exists()) {
        final backup = File('${target.path}.previous');
        if (await backup.exists()) await backup.delete();
        await target.rename(backup.path);
      }
      await temporary.rename(target.path);
      try {
        return await _openValidated(target.path);
      } catch (_) {
        final backup = File('${target.path}.previous');
        if (await backup.exists()) {
          if (await target.exists()) await target.delete();
          await backup.rename(target.path);
          await _openValidated(target.path);
        }
        rethrow;
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  // 查询一张卡的静态规则字段与卡名效果文本
  CardMetadata? lookup(int code) {
    if (code <= 0) return null;
    if (_cache.containsKey(code)) {
      final cached = _cache.remove(code);
      _cache[code] = cached;
      return cached;
    }
    final database = _database;
    if (database == null) return null;
    CardMetadata? result;
    try {
      final rows = database.select(
        'SELECT d.id, d.alias, d.setcode, d.type, d.atk, d.def, '
        'd.level, d.race, d.attribute, t.name, t.desc '
        'FROM datas d LEFT JOIN texts t ON t.id = d.id WHERE d.id = ?',
        <Object?>[code],
      );
      if (rows.isNotEmpty) result = _metadataFromRow(rows.first);
    } catch (_) {
      result = null;
    }
    _cache[code] = result;
    if (_cache.length > _maximumCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  // 按 OCG 宣言表达式筛选卡片并优先返回当前对局已知卡号
  List<CardMetadata> findAnnounceCandidates(
    List<int> opcodes,
    Iterable<int> preferredCodes, {
    int limit = 120,
  }) {
    final database = _database;
    if (database == null || limit <= 0) return const <CardMetadata>[];
    final preferred = preferredCodes.where((code) => code > 0).toSet();
    final directCodes = opcodes
        .where((value) => value > 10000 && value < 0x40000000)
        .map((value) => value & 0x0fffffff)
        .toSet();
    final hasOperations = opcodes.any((value) => value >= 0x40000000);
    final matched = <CardMetadata>[];
    if (!hasOperations && opcodes.isNotEmpty) {
      for (final code in directCodes) {
        final metadata = lookup(code);
        if (metadata != null) matched.add(metadata);
      }
    } else {
      final rows = database.select(
        'SELECT id, alias, setcode, type, atk, def, level, race, attribute, '
        "'' AS name, '' AS desc FROM datas",
      );
      for (final row in rows) {
        final metadata = _metadataFromRow(row);
        if (opcodes.isEmpty || _evaluateAnnounceRpn(metadata, opcodes)) {
          matched.add(metadata);
        }
      }
    }
    if (matched.isEmpty) {
      for (final code in <int>{...preferred, ...directCodes}) {
        final metadata = lookup(code);
        if (metadata != null) matched.add(metadata);
      }
    }
    matched.sort((left, right) {
      final leftScore = (preferred.contains(left.code) ? 100 : 0) +
          (directCodes.contains(left.code) ? 50 : 0);
      final rightScore = (preferred.contains(right.code) ? 100 : 0) +
          (directCodes.contains(right.code) ? 50 : 0);
      final scoreOrder = rightScore.compareTo(leftScore);
      return scoreOrder != 0 ? scoreOrder : left.code.compareTo(right.code);
    });
    return matched.take(limit).map((metadata) {
      return lookup(metadata.code) ?? metadata;
    }).toList(growable: false);
  }

  // 释放只读数据库连接和内存查询缓存
  Future<void> close() async {
    _database?.dispose();
    _database = null;
    info = null;
    _cache.clear();
  }

  // 返回应用私有目录中的固定数据库路径
  Future<File> _targetFile() async {
    final support = await _supportDirectoryProvider();
    return File(
      '${support.path}${Platform.pathSeparator}galatea_cards'
      '${Platform.pathSeparator}cards.cdb',
    );
  }

  // 重新检查并打开指定数据库
  Future<CardDatabaseInfo> _openValidated(String path) async {
    final inspected = await Isolate.run(() => _inspectCardDatabase(path));
    final database = sqlite3.open(path, mode: OpenMode.readOnly);
    _database?.dispose();
    _database = database;
    _cache.clear();
    info = inspected;
    return inspected;
  }

  // 将 SQLite 查询行转换为与 Core V3 一致的卡片静态字段
  static CardMetadata _metadataFromRow(Row row) {
    final type = (row['type'] as num?)?.toInt() ?? 0;
    final rawLevel = (row['level'] as num?)?.toInt() ?? 0;
    final rawAttack = (row['atk'] as num?)?.toInt() ?? 0;
    final rawDefense = (row['def'] as num?)?.toInt() ?? 0;
    final isLink = (type & 0x4000000) != 0;
    final isXyz = (type & 0x800000) != 0;
    final isPendulum = (type & 0x1000000) != 0;
    final level = isXyz ? 0 : rawLevel & 0xffff;
    final rank = isXyz ? rawLevel & 0xffff : 0;
    final link = isLink ? rawLevel & 0xffff : 0;
    final rawSetcode = (row['setcode'] as num?)?.toInt() ?? 0;
    final setcodes = List<int>.filled(4, 0);
    var remainingSetcode = rawSetcode;
    for (var index = 0; index < 4; index++) {
      setcodes[index] = remainingSetcode & 0xffff;
      remainingSetcode = remainingSetcode >>> 16;
    }
    final code = (row['id'] as num).toInt();
    return CardMetadata(
      code: code,
      alias: (row['alias'] as num?)?.toInt() ?? 0,
      setcodes: List<int>.unmodifiable(setcodes),
      type: type,
      attack: rawAttack < 0 ? 0 : rawAttack,
      defense: isLink || rawDefense < 0 ? 0 : rawDefense,
      level: level,
      rank: rank,
      race: (row['race'] as num?)?.toInt() ?? 0,
      attribute: (row['attribute'] as num?)?.toInt() ?? 0,
      leftScale: isPendulum ? (rawLevel >> 24) & 0xff : 0,
      rightScale: isPendulum ? (rawLevel >> 16) & 0xff : 0,
      link: link,
      linkMarker: isLink && rawDefense > 0 ? rawDefense : 0,
      name: row['name'] as String? ?? 'Code $code',
      description: row['desc'] as String? ?? '',
    );
  }
}

// 执行 OCG 卡名宣言使用的逆波兰规则表达式
bool _evaluateAnnounceRpn(CardMetadata card, List<int> opcodes) {
  if (opcodes.isEmpty) return true;
  final stack = <int>[];
  for (final opcode in opcodes) {
    if (opcode < 0x40000000) {
      stack.add(opcode);
      continue;
    }
    if (stack.isEmpty) return false;
    switch (opcode) {
      case 0x40000100:
        stack.add(card.code == stack.removeLast() ? 1 : 0);
        break;
      case 0x40000101:
        final requested = stack.removeLast();
        final setType = requested & 0xfff;
        final setSubtype = requested & 0xf000;
        final matches = card.setcodes.any(
          (value) =>
              (value & 0xfff) == setType &&
              (value & 0xf000 & setSubtype) == setSubtype,
        );
        stack.add(matches ? 1 : 0);
        break;
      case 0x40000102:
        final requested = stack.removeLast();
        stack.add((card.type & requested) == requested ? 1 : 0);
        break;
      case 0x40000103:
        final requested = stack.removeLast();
        stack.add((card.race & requested) == requested ? 1 : 0);
        break;
      case 0x40000104:
        final requested = stack.removeLast();
        stack.add((card.attribute & requested) == requested ? 1 : 0);
        break;
      case 0x40000105:
        stack.add(card.level == stack.removeLast() ? 1 : 0);
        break;
      case 0x40000107:
        stack.add(card.link == stack.removeLast() ? 1 : 0);
        break;
      case 0x40000004:
        if (stack.length < 2) return false;
        final right = stack.removeLast();
        final left = stack.removeLast();
        stack.add(left != 0 && right != 0 ? 1 : 0);
        break;
      case 0x40000005:
        if (stack.length < 2) return false;
        final right = stack.removeLast();
        final left = stack.removeLast();
        stack.add(left != 0 || right != 0 ? 1 : 0);
        break;
      case 0x40000007:
        stack.add(stack.removeLast() == 0 ? 1 : 0);
        break;
      default:
        stack.add(0);
        break;
    }
  }
  return stack.isEmpty || stack.last != 0;
}

// 检查标准 YGOPro 数据表、必要列和有效记录数量
CardDatabaseInfo _inspectCardDatabase(String path) {
  final database = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final requiredDataColumns = <String>{
      'id',
      'alias',
      'setcode',
      'type',
      'atk',
      'def',
      'level',
      'race',
      'attribute',
    };
    final dataColumns = database
        .select('PRAGMA table_info(datas)')
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    final textColumns = database
        .select('PRAGMA table_info(texts)')
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    if (!dataColumns.containsAll(requiredDataColumns) ||
        !textColumns.containsAll(const <String>{'id', 'name', 'desc'})) {
      throw const FormatException('CDB 不包含标准 YGOPro datas/texts 字段');
    }
    final dataCount = (database
            .select('SELECT COUNT(*) AS value FROM datas')
            .first['value'] as num)
        .toInt();
    final textCount = (database
            .select('SELECT COUNT(*) AS value FROM texts')
            .first['value'] as num)
        .toInt();
    if (dataCount <= 0 || textCount <= 0) {
      throw const FormatException('CDB 没有可用卡片记录');
    }
    database.select(
      'SELECT d.id, t.name FROM datas d '
      'LEFT JOIN texts t ON t.id = d.id LIMIT 1',
    );
    return CardDatabaseInfo(
      path: path,
      dataCount: dataCount,
      textCount: textCount,
    );
  } on SqliteException catch (error) {
    throw FormatException('CDB SQLite 校验失败: ${error.message}');
  } finally {
    database.dispose();
  }
}
