// 移动端卡片数据库测试，验证 CDB 导入检查和 Core V3 静态字段转换

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galatea_link_mobile/src/cards/card_database_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  // 验证标准 YGOPro 数据库可以安装并解析通常怪兽字段
  test('imports and reads standard card database', () async {
    final directory = await Directory.systemTemp.createTemp('galatea_cdb_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File.fromUri(directory.uri.resolve('source.cdb'));
    _writeFixture(source.path);
    final support = Directory.fromUri(directory.uri.resolve('support/'));
    final service = CardDatabaseService(
      supportDirectoryProvider: () async => support,
    );
    addTearDown(service.close);

    final info = await service.installFrom(source.path);
    final metadata = service.lookup(12345);

    expect(info.dataCount, 2);
    expect(info.textCount, 2);
    expect(metadata?.name, '测试龙');
    expect(metadata?.description, '抽一张卡');
    expect(metadata?.attack, 1800);
    expect(metadata?.defense, 1200);
    expect(metadata?.level, 4);
    expect(metadata?.setcodes.take(2), <int>[0x1234, 0x5678]);
  });

  // 验证连接与灵摆字段会按 Core V3 规则拆分
  test('decodes link and pendulum packed fields', () async {
    final directory = await Directory.systemTemp.createTemp('galatea_cdb_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File.fromUri(directory.uri.resolve('source.cdb'));
    _writeFixture(source.path);
    final service = CardDatabaseService(
      supportDirectoryProvider: () async => directory,
    );
    addTearDown(service.close);
    await service.installFrom(source.path);

    final metadata = service.lookup(54321);

    expect(metadata?.link, 3);
    expect(metadata?.linkMarker, 0x45);
    expect(metadata?.defense, 0);
    expect(metadata?.leftScale, 5);
    expect(metadata?.rightScale, 7);
  });

  // 验证卡名宣言 RPN 会按种族和纯白名单筛选真实卡号
  test('filters announce card expressions', () async {
    final directory = await Directory.systemTemp.createTemp('galatea_cdb_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File.fromUri(directory.uri.resolve('source.cdb'));
    _writeFixture(source.path);
    final service = CardDatabaseService(
      supportDirectoryProvider: () async => directory,
    );
    addTearDown(service.close);
    await service.installFrom(source.path);

    final dragon = service.findAnnounceCandidates(
      const <int>[0x2000, 0x40000103],
      const <int>[54321],
    );
    final whitelist = service.findAnnounceCandidates(
      const <int>[54321],
      const <int>[],
    );

    expect(dragon.map((card) => card.code), <int>[12345]);
    expect(whitelist.map((card) => card.code), <int>[54321]);
  });

  // 在显式提供路径时验证真实稳定版卡片数据库
  test('imports real card database when configured', () async {
    final realPath = Platform.environment['REAL_CDB_PATH'];
    if (realPath == null || realPath.isEmpty) return;
    final directory = await Directory.systemTemp.createTemp('galatea_cdb_');
    addTearDown(() => directory.delete(recursive: true));
    final service = CardDatabaseService(
      supportDirectoryProvider: () async => directory,
    );
    addTearDown(service.close);

    final info = await service.installFrom(realPath);
    final stopwatch = Stopwatch()..start();
    final candidates = service.findAnnounceCandidates(
      const <int>[0x1, 0x40000102],
      const <int>[],
    );
    stopwatch.stop();

    expect(info.dataCount, greaterThan(10000));
    expect(info.textCount, greaterThan(10000));
    expect(candidates, isNotEmpty);
    expect(candidates.length, lessThanOrEqualTo(120));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

// 创建包含普通卡与连接灵摆组合字段的最小标准数据库
void _writeFixture(String path) {
  final database = sqlite3.open(path);
  try {
    database.execute(
      'CREATE TABLE datas (id INTEGER PRIMARY KEY, ot INTEGER, alias INTEGER, '
      'setcode INTEGER, type INTEGER, atk INTEGER, def INTEGER, level INTEGER, '
      'race INTEGER, attribute INTEGER, category INTEGER)',
    );
    database.execute(
      'CREATE TABLE texts (id INTEGER PRIMARY KEY, name TEXT, desc TEXT)',
    );
    database.execute(
      'INSERT INTO datas VALUES (?, 0, 0, ?, ?, ?, ?, ?, ?, ?, 0)',
      <Object?>[
        12345,
        0x56781234,
        0x21,
        1800,
        1200,
        4,
        0x2000,
        0x20,
      ],
    );
    database.execute(
      'INSERT INTO texts VALUES (?, ?, ?)',
      <Object?>[12345, '测试龙', '抽一张卡'],
    );
    database.execute(
      'INSERT INTO datas VALUES (?, 0, 0, 0, ?, 2500, ?, ?, 1, 16, 0)',
      <Object?>[
        54321,
        0x4000000 | 0x1000000,
        0x45,
        (5 << 24) | (7 << 16) | 3,
      ],
    );
    database.execute(
      'INSERT INTO texts VALUES (?, ?, ?)',
      <Object?>[54321, '测试连接卡', '连接效果'],
    );
  } finally {
    database.dispose();
  }
}
