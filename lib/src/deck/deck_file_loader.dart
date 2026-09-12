// 移动端 YDK 文件选择模块，读取用户选择的本地卡组文件

import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'ydk_deck.dart';

class YdkFileLoader {
  // 打开系统文件选择器并解析单个 YDK 文件
  static Future<YdkDeck?> pickDeck() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.single;
    if (!file.name.toLowerCase().endsWith('.ydk')) {
      throw const FormatException('请选择 .ydk 卡组文件');
    }
    final bytes = file.bytes;
    if (bytes == null) {
      throw const FormatException('无法读取所选 YDK 文件内容');
    }
    return YdkDeckParser.parse(utf8.decode(bytes, allowMalformed: true),
        name: file.name);
  }
}
