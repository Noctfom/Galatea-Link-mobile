// 移动端卡组仓库测试，验证导入覆盖读取和删除均限制在应用目录

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/deck/deck_library_service.dart';
import 'package:galatea_link_mobile/src/deck/ydk_deck.dart';

void main() {
  late Directory temporary;
  late DeckLibraryService service;

  // 为每个用例创建隔离的临时应用目录
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('galatea_mobile_decks_');
    service = DeckLibraryService(
      supportDirectoryProvider: () async => temporary,
    );
  });

  // 清理测试创建的临时卡组目录
  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  // 验证同名导入自动避让且编辑内容可重新读取
  test('imports edits and lists decks', () async {
    final original = YdkDeck(
      name: '测试卡组.ydk',
      main: List<int>.filled(40, 100001),
      extra: const <int>[100002],
      side: const <int>[],
    );
    final first = await service.importDeck(original);
    final second = await service.importDeck(original);
    await service.saveDeck(
      first.fileName,
      first.deck.copyWith(extra: const <int>[100002, 100003]),
    );

    final records = await service.listDecks();

    expect(first.fileName, '测试卡组.ydk');
    expect(second.fileName, '测试卡组 (2).ydk');
    expect(records, hasLength(2));
    expect(
      records.singleWhere((item) => item.fileName == first.fileName).deck.extra,
      <int>[100002, 100003],
    );
  });

  // 验证删除只移除指定卡组文件
  test('deletes one stored deck', () async {
    final record = await service.importDeck(
      YdkDeck(
        name: '删除测试.ydk',
        main: List<int>.filled(40, 100001),
        extra: const <int>[],
        side: const <int>[],
      ),
    );

    await service.deleteDeck(record.fileName);

    expect(await service.listDecks(), isEmpty);
  });
}
