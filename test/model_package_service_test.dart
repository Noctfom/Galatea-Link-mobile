// 移动端 GKG 服务测试，验证 V2 清单预检和选择性 ONNX 安装
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/models/model_package_service.dart';

// 构建包含一个 V3 ONNX 的最小 GKG 测试包
File buildTestGkg(Directory root, {String? unsafeName}) {
  const primary = 'galatea_iter_10.onnx';
  const data = 'galatea_iter_10.onnx.data';
  const artifact = 'galatea_iter_10.artifacts.json';
  final record = <String, Object?>{
    'format': 'onnx',
    'model_id': '5381b6f8-b492-43b8-9f16-6957920826fa',
    'model_prefix': 'galatea',
    'iteration': 10,
    'model_protocol_version': 3,
    'primary': primary,
    'files': <String>[primary, data],
    'external_data': <String>[data],
    'status': 'complete',
  };
  final manifest = <String, Object?>{
    'package_format_version': 2,
    'package_name': 'test-package',
    'models_included': <String>[primary],
    'model_artifacts': <Object?>[record],
    'model_files_included': <String>[primary, data, artifact],
    'includes_kb': false,
    'includes_staples': false,
    'includes_hash_mapping': false,
    'includes_code_semantics': false,
  };
  final archive = Archive()
    ..addFile(ArchiveFile.bytes(primary, <int>[1, 2, 3, 4]))
    ..addFile(ArchiveFile.bytes(data, <int>[5, 6, 7, 8]))
    ..addFile(ArchiveFile.string(artifact, jsonEncode(record)))
    ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
  if (unsafeName != null) {
    archive.addFile(ArchiveFile.bytes(unsafeName, <int>[1]));
  }
  final bytes = ZipEncoder().encodeBytes(archive);
  return File(root.path + Platform.pathSeparator + 'test.gkg')
    ..writeAsBytesSync(bytes);
}

void main() {
  // 验证合法 GKG 可以预览并只安装 ONNX 所需文件
  test('inspects and installs v3 onnx package', () async {
    final root = Directory.systemTemp.createTempSync('galatea-gkg-test-');
    try {
      final package = buildTestGkg(root);
      final support = Directory(
        root.path + Platform.pathSeparator + 'support',
      );
      final service = ModelPackageService(
        supportDirectoryProvider: () async => support,
      );

      final preview = await service.inspect(package.path);
      final installed = await service.installOnnx(
        preview,
        preview.onnxModels.single.primary,
      );

      expect(preview.packageName, 'test-package');
      expect(preview.onnxModels.single.modelProtocolVersion, 3);
      expect(File(installed.primaryPath).readAsBytesSync(), [1, 2, 3, 4]);
      expect(
        File(
          installed.directoryPath +
              Platform.pathSeparator +
              'galatea_iter_10.onnx.data',
        ).existsSync(),
        isTrue,
      );
      final installedModels = await service.listInstalled();
      expect(installedModels, hasLength(1));
      expect(installedModels.single.record.iteration, 10);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  // 验证包含路径穿越成员的包会在预检阶段拒绝
  test('rejects unsafe member path', () async {
    final root = Directory.systemTemp.createTempSync('galatea-gkg-bad-');
    try {
      final package = buildTestGkg(root, unsafeName: '../evil.onnx');
      final service = ModelPackageService(
        supportDirectoryProvider: () async => root,
      );

      await expectLater(
        service.inspect(package.path),
        throwsA(isA<FormatException>()),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
