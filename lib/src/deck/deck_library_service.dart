// 移动端本地卡组仓库，负责持久化导入读取覆盖和删除 YDK 文件

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'ydk_deck.dart';

class StoredYdkDeck {
  // 保存应用私有目录中一份可编辑 YDK 卡组的索引信息
  const StoredYdkDeck({
    required this.fileName,
    required this.deck,
    required this.updatedAt,
  });

  final String fileName;
  final YdkDeck deck;
  final DateTime updatedAt;
}

class DeckLibraryService {
  // 创建支持测试目录注入的移动端卡组仓库
  DeckLibraryService({Future<Directory> Function()? supportDirectoryProvider})
      : _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const int _maximumYdkBytes = 512 * 1024;
  final Future<Directory> Function() _supportDirectoryProvider;

  // 扫描应用私有目录并返回所有可读取卡组
  Future<List<StoredYdkDeck>> listDecks() async {
    final directory = await _deckDirectory();
    if (!await directory.exists()) return const <StoredYdkDeck>[];
    final records = <StoredYdkDeck>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.ydk')) {
        continue;
      }
      try {
        final bytes = await entity.length();
        if (bytes <= 0 || bytes > _maximumYdkBytes) continue;
        final fileName = _basename(entity.path);
        final text = await entity.readAsString();
        final deck = YdkDeckParser.parse(
          text,
          name: fileName,
          requireDuelValid: false,
        );
        final stat = await entity.stat();
        records.add(
          StoredYdkDeck(
            fileName: fileName,
            deck: deck,
            updatedAt: stat.modified,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    records.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List<StoredYdkDeck>.unmodifiable(records);
  }

  // 将外部卡组复制到应用私有目录并自动避让同名文件
  Future<StoredYdkDeck> importDeck(YdkDeck source) async {
    if (!source.isStorageSafe) {
      throw const FormatException('卡组内容超过本地安全限制');
    }
    final directory = await _deckDirectory();
    await directory.create(recursive: true);
    final preferred = _normalizeFileName(source.name);
    var fileName = preferred;
    var suffix = 2;
    while (await File('${directory.path}${Platform.pathSeparator}$fileName')
        .exists()) {
      final stem = preferred.substring(0, preferred.length - 4);
      fileName = '$stem ($suffix).ydk';
      suffix += 1;
    }
    return _write(fileName, source.copyWith(name: fileName));
  }

  // 覆盖保存卡组编辑结果并保留原文件名
  Future<StoredYdkDeck> saveDeck(String fileName, YdkDeck deck) async {
    if (!deck.isStorageSafe) {
      throw const FormatException('主卡组不能为空且各区域不能超过本地安全限制');
    }
    final normalized = _normalizeFileName(fileName);
    return _write(normalized, deck.copyWith(name: normalized));
  }

  // 删除应用私有目录中的指定卡组
  Future<void> deleteDeck(String fileName) async {
    final normalized = _normalizeFileName(fileName);
    final directory = await _deckDirectory();
    final target = File('${directory.path}${Platform.pathSeparator}$normalized');
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('不允许删除链接卡组');
    }
    if (await target.exists()) await target.delete();
  }

  // 原子写入规范化 YDK 文本并返回最新索引
  Future<StoredYdkDeck> _write(String fileName, YdkDeck deck) async {
    final directory = await _deckDirectory();
    await directory.create(recursive: true);
    final target = File('${directory.path}${Platform.pathSeparator}$fileName');
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('不允许覆盖链接卡组');
    }
    final temporary = File('${target.path}.saving');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsString(deck.toYdkText(), flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    final stat = await target.stat();
    return StoredYdkDeck(
      fileName: fileName,
      deck: deck.copyWith(name: fileName),
      updatedAt: stat.modified,
    );
  }

  // 返回应用私有目录中的卡组子目录
  Future<Directory> _deckDirectory() async {
    final support = await _supportDirectoryProvider();
    return Directory('${support.path}${Platform.pathSeparator}decks');
  }

  // 规范化用户可见文件名并阻止目录穿越字符
  static String _normalizeFileName(String source) {
    var name = source.trim();
    if (name.toLowerCase().endsWith('.ydk')) {
      name = name.substring(0, name.length - 4).trim();
    }
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    name = name.replaceAll(RegExp(r'[. ]+$'), '').trim();
    if (name.isEmpty) name = 'Mobile Deck';
    if (name.length > 100) name = name.substring(0, 100).trim();
    return '$name.ydk';
  }

  // 从系统路径中提取最后一级文件名
  static String _basename(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }
}
