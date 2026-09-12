// 真实 GKG 兼容测试，通过构建参数选择性验证外部稳定部署包

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/models/model_package_service.dart';

const String realGkgPath = String.fromEnvironment('REAL_GKG_PATH');
const String realGkgInstallRoot =
    String.fromEnvironment('REAL_GKG_INSTALL_ROOT');

// 在提供真实路径时执行只读流式预检
void main() {
  test(
    'inspects configured real gkg package',
    () async {
      expect(File(realGkgPath).existsSync(), isTrue);
      final preview = await ModelPackageService().inspect(realGkgPath);

      expect(preview.onnxModels, isNotEmpty);
      expect(
        preview.onnxModels.every(
          (model) =>
              model.modelProtocolVersion == supportedModelProtocolVersion,
        ),
        isTrue,
      );
    },
    skip: realGkgPath.isEmpty ? 'REAL_GKG_PATH is not configured' : false,
  );

  // 在提供输出目录时流式安装真实 ONNX 和语义制品
  test(
    'installs configured real gkg package',
    () async {
      final support = Directory(realGkgInstallRoot);
      final service = ModelPackageService(
        supportDirectoryProvider: () async => support,
      );
      final preview = await service.inspect(realGkgPath);
      final installed = await service.installOnnx(
        preview,
        preview.onnxModels.first.primary,
      );

      expect(File(installed.primaryPath).existsSync(), isTrue);
      expect(
        File(
          '${installed.directoryPath}${Platform.pathSeparator}knowledge_base.json',
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          '${installed.directoryPath}${Platform.pathSeparator}code_embeddings_idx.json',
        ).existsSync(),
        isTrue,
      );
    },
    skip: realGkgPath.isEmpty || realGkgInstallRoot.isEmpty
        ? 'REAL_GKG_PATH or REAL_GKG_INSTALL_ROOT is not configured'
        : false,
  );
}
