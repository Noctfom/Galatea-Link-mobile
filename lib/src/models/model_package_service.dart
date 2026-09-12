// 移动端 GKG V2 模型包服务，负责流式预检和只提取 ONNX 所需制品
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

const int supportedGkgFormatVersion = 2;
const int supportedModelProtocolVersion = 3;

class GkgModelRecord {
  const GkgModelRecord({
    required this.primary,
    required this.files,
    required this.externalData,
    required this.modelId,
    required this.modelPrefix,
    required this.iteration,
    required this.modelProtocolVersion,
  });

  final String primary;
  final List<String> files;
  final List<String> externalData;
  final String modelId;
  final String modelPrefix;
  final int iteration;
  final int modelProtocolVersion;

  // 转换为移动端安装清单对象
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'format': 'onnx',
      'status': 'complete',
      'primary': primary,
      'files': files,
      'external_data': externalData,
      'model_id': modelId,
      'model_prefix': modelPrefix,
      'iteration': iteration,
      'model_protocol_version': modelProtocolVersion,
    };
  }
}

class GkgPackagePreview {
  const GkgPackagePreview({
    required this.sourcePath,
    required this.packageName,
    required this.packageBytes,
    required this.expandedBytes,
    required this.memberNames,
    required this.onnxModels,
    required this.includesKnowledgeBase,
    required this.includesStaples,
    required this.includesHashMapping,
    required this.includesCodeSemantics,
  });

  final String sourcePath;
  final String packageName;
  final int packageBytes;
  final int expandedBytes;
  final List<String> memberNames;
  final List<GkgModelRecord> onnxModels;
  final bool includesKnowledgeBase;
  final bool includesStaples;
  final bool includesHashMapping;
  final bool includesCodeSemantics;
}

class InstalledOnnxModel {
  const InstalledOnnxModel({
    required this.directoryPath,
    required this.primaryPath,
    required this.record,
  });

  final String directoryPath;
  final String primaryPath;
  final GkgModelRecord record;
}

class ModelPackageService {
  ModelPackageService({
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const int _maximumPackageBytes = 8 * 1024 * 1024 * 1024;
  static const int _maximumMemberBytes = 4 * 1024 * 1024 * 1024;
  static const int _maximumExpandedBytes = 8 * 1024 * 1024 * 1024;
  static const int _maximumMembers = 256;
  static const int _maximumManifestBytes = 2 * 1024 * 1024;
  static const int _maximumCompressionRatio = 1000;
  static const Set<String> _semanticFiles = <String>{
    'knowledge_base.json',
    'hash_mapping_report.json',
    'code_embeddings.npy',
    'code_embeddings_idx.json',
    'meta_staples.json',
  };

  final Future<Directory> Function() _supportDirectoryProvider;

  // 在后台 Isolate 中检查 GKG 清单和全部归档边界
  Future<GkgPackagePreview> inspect(String sourcePath) {
    return Isolate.run(() => _inspectSync(sourcePath));
  }

  // 在应用私有目录中流式安装指定 ONNX 及其语义资产
  Future<InstalledOnnxModel> installOnnx(
    GkgPackagePreview preview,
    String primary,
  ) async {
    final support = await _supportDirectoryProvider();
    final root = support.path + Platform.pathSeparator + 'galatea_models';
    return Isolate.run(() => _installSync(preview.sourcePath, primary, root));
  }

  // 扫描应用私有目录并返回安装完成的 ONNX 模型
  Future<List<InstalledOnnxModel>> listInstalled() async {
    final support = await _supportDirectoryProvider();
    final root = Directory(
      support.path + Platform.pathSeparator + 'galatea_models',
    );
    if (!await root.exists()) return const <InstalledOnnxModel>[];
    final result = <InstalledOnnxModel>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final marker = File(
        entity.path + Platform.pathSeparator + 'mobile_install.json',
      );
      if (!await marker.exists()) continue;
      try {
        final decoded = jsonDecode(await marker.readAsString());
        if (decoded is! Map || decoded['model'] is! Map) continue;
        final record = _parseOnnxRecord(decoded['model'] as Map);
        if (record.modelProtocolVersion != supportedModelProtocolVersion) {
          continue;
        }
        final primaryPath =
            entity.path + Platform.pathSeparator + record.primary;
        if (!await File(primaryPath).exists()) continue;
        if (record.externalData.any((name) =>
            !File(entity.path + Platform.pathSeparator + name).existsSync())) {
          continue;
        }
        result.add(
          InstalledOnnxModel(
            directoryPath: entity.path,
            primaryPath: primaryPath,
            record: record,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    result.sort(
      (left, right) => right.record.iteration.compareTo(left.record.iteration),
    );
    return List<InstalledOnnxModel>.unmodifiable(result);
  }

  // 同步流式检查包文件并返回经过交叉验证的预览
  static GkgPackagePreview _inspectSync(String sourcePath) {
    final source = File(sourcePath);
    if (!source.existsSync() || !sourcePath.toLowerCase().endsWith('.gkg')) {
      throw const FormatException('请选择存在的 .gkg 部署包');
    }
    final packageBytes = source.lengthSync();
    if (packageBytes <= 0 || packageBytes > _maximumPackageBytes) {
      throw const FormatException('GKG 文件大小超出移动端安全范围');
    }
    final input = InputFileStream(sourcePath);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
      if (archive.isEmpty || archive.length > _maximumMembers) {
        throw const FormatException('GKG 成员数量超出安全范围');
      }
      final names = <String>{};
      var expandedBytes = 0;
      ArchiveFile? manifestFile;
      for (final member in archive) {
        if (!member.isFile || member.isSymbolicLink) {
          throw FormatException(
            'GKG 只允许根目录普通文件: ' + member.name,
          );
        }
        final name = _validateSafeFilename(member.name);
        if (!names.add(name)) {
          throw FormatException('GKG 包含重复成员: ' + name);
        }
        if (!_isAllowedRootFile(name)) {
          throw FormatException('GKG 包含不支持的文件: ' + name);
        }
        if (member.size < 0 || member.size > _maximumMemberBytes) {
          throw FormatException('GKG 成员过大: ' + name);
        }
        expandedBytes += member.size;
        if (expandedBytes > _maximumExpandedBytes) {
          throw const FormatException('GKG 展开总量超出移动端安全范围');
        }
        final compressedBytes = member.rawContent?.length ?? 0;
        if (member.size > 0 &&
            (compressedBytes <= 0 ||
                member.size ~/ compressedBytes > _maximumCompressionRatio)) {
          throw FormatException('GKG 成员压缩比异常: ' + name);
        }
        if (name == 'manifest.json') manifestFile = member;
      }
      if (manifestFile == null ||
          manifestFile.size <= 0 ||
          manifestFile.size > _maximumManifestBytes) {
        throw const FormatException('GKG 缺少有效 manifest.json');
      }
      final manifestBytes = manifestFile.readBytes();
      if (manifestBytes == null) {
        throw const FormatException('无法读取 GKG manifest.json');
      }
      final decoded = jsonDecode(utf8.decode(manifestBytes));
      if (decoded is! Map) {
        throw const FormatException('GKG manifest 必须是 JSON 对象');
      }
      final manifest = Map<String, dynamic>.from(decoded);
      if (manifest['package_format_version'] != supportedGkgFormatVersion) {
        throw FormatException(
          'GKG 协议版本不兼容: ' + manifest['package_format_version'].toString(),
        );
      }
      final packageName = manifest['package_name'];
      if (packageName is! String) {
        throw const FormatException('GKG package_name 无效');
      }
      _validateSafeLabel(packageName);
      _validateDeclaredFiles(manifest, names);
      final rawRecords = manifest['model_artifacts'];
      if (rawRecords is! List) {
        throw const FormatException('GKG model_artifacts 无效');
      }
      final onnxModels = <GkgModelRecord>[];
      for (final rawRecord in rawRecords) {
        if (rawRecord is! Map || rawRecord['format'] != 'onnx') continue;
        final record = _parseOnnxRecord(rawRecord);
        if (record.modelProtocolVersion != supportedModelProtocolVersion) {
          throw FormatException(
            '模型协议不兼容: ' + record.modelProtocolVersion.toString(),
          );
        }
        if (!names.containsAll(record.files)) {
          throw FormatException('ONNX 制品不完整: ' + record.primary);
        }
        onnxModels.add(record);
      }
      if (onnxModels.isEmpty) {
        throw const FormatException('GKG 不包含可用于移动端的 V3 ONNX');
      }
      final includesKb = names.contains('knowledge_base.json');
      final includesVectors = names.contains('code_embeddings.npy') &&
          names.contains('code_embeddings_idx.json');
      if (includesKb != includesVectors) {
        throw const FormatException('GKG 运行时语义资产不完整');
      }
      return GkgPackagePreview(
        sourcePath: sourcePath,
        packageName: packageName,
        packageBytes: packageBytes,
        expandedBytes: expandedBytes,
        memberNames: List<String>.unmodifiable(names.toList()..sort()),
        onnxModels: List<GkgModelRecord>.unmodifiable(onnxModels),
        includesKnowledgeBase: includesKb,
        includesStaples: names.contains('meta_staples.json'),
        includesHashMapping: names.contains('hash_mapping_report.json'),
        includesCodeSemantics: includesVectors,
      );
    } finally {
      archive?.clearSync();
      input.closeSync();
    }
  }

  // 重新预检来源后将选定制品安全写入唯一私有目录
  static InstalledOnnxModel _installSync(
    String sourcePath,
    String primary,
    String modelsRootPath,
  ) {
    final preview = _inspectSync(sourcePath);
    GkgModelRecord? record;
    for (final item in preview.onnxModels) {
      if (item.primary == primary) record = item;
    }
    if (record == null) {
      throw FormatException('GKG 中不存在选定模型: ' + primary);
    }
    final selected = record;
    final safeStem = selected.primary.substring(0, selected.primary.length - 5);
    final root = Directory(modelsRootPath)..createSync(recursive: true);
    final baseName = selected.modelId + '-' + safeStem;
    var target = Directory(root.path + Platform.pathSeparator + baseName);
    var suffix = 1;
    while (target.existsSync()) {
      target = Directory(
        root.path + Platform.pathSeparator + baseName + '-' + suffix.toString(),
      );
      suffix += 1;
    }
    final temporary = Directory(
      target.path + '.tmp-' + DateTime.now().millisecondsSinceEpoch.toString(),
    )..createSync(recursive: true);
    final wanted = <String>{
      ...selected.files,
      safeStem + '.artifacts.json',
      ...preview.memberNames.where(_semanticFiles.contains),
    };
    final input = InputFileStream(sourcePath);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
      final extracted = <String>{};
      for (final member in archive) {
        if (!wanted.contains(member.name)) continue;
        _validateSafeFilename(member.name);
        final outputPath =
            temporary.path + Platform.pathSeparator + member.name;
        final output = OutputFileStream(outputPath);
        try {
          member.writeContent(output);
        } finally {
          output.closeSync();
        }
        if (File(outputPath).lengthSync() != member.size) {
          throw FormatException(
            'GKG 成员写入长度不一致: ' + member.name,
          );
        }
        extracted.add(member.name);
      }
      if (!extracted.containsAll(wanted)) {
        throw FormatException(
          'GKG 安装缺少文件: ' + wanted.difference(extracted).join(', '),
        );
      }
      final marker = <String, Object?>{
        'schema': 'galatea.mobile.model_install.v1',
        'installed_at': DateTime.now().toUtc().toIso8601String(),
        'source_package': preview.packageName,
        'model': selected.toJson(),
        'files': wanted.toList()..sort(),
      };
      File(temporary.path + Platform.pathSeparator + 'mobile_install.json')
          .writeAsStringSync(jsonEncode(marker), flush: true);
      temporary.renameSync(target.path);
      return InstalledOnnxModel(
        directoryPath: target.path,
        primaryPath: target.path + Platform.pathSeparator + selected.primary,
        record: selected,
      );
    } catch (_) {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      rethrow;
    } finally {
      archive?.clearSync();
      input.closeSync();
    }
  }

  // 解析并严格验证清单中的 ONNX 身份记录
  static GkgModelRecord _parseOnnxRecord(Map source) {
    final record = Map<String, dynamic>.from(source);
    if (record['format'] != 'onnx' || record['status'] != 'complete') {
      throw const FormatException('ONNX 制品状态不是 complete');
    }
    final primary = record['primary'];
    final modelId = record['model_id'];
    final modelPrefix = record['model_prefix'];
    final iteration = record['iteration'];
    final protocol = record['model_protocol_version'];
    if (primary is! String ||
        modelId is! String ||
        modelPrefix is! String ||
        iteration is! int ||
        iteration < 0 ||
        protocol is! int) {
      throw const FormatException('ONNX 身份字段无效');
    }
    _validateSafeFilename(primary, suffixes: const <String>['.onnx']);
    _validateModelId(modelId);
    _validateSafeLabel(modelPrefix);
    final files = _stringList(record['files'], 'ONNX files');
    final externalData = _stringList(
      record['external_data'] ?? const <Object>[],
      'ONNX external_data',
    );
    for (final name in files) {
      _validateSafeFilename(
        name,
        suffixes: const <String>['.onnx', '.onnx.data'],
      );
    }
    if (!files.contains(primary) ||
        !files.toSet().containsAll(externalData) ||
        externalData.any((name) => !name.endsWith('.onnx.data'))) {
      throw const FormatException('ONNX files 与 external_data 不一致');
    }
    return GkgModelRecord(
      primary: primary,
      files: List<String>.unmodifiable(files),
      externalData: List<String>.unmodifiable(externalData),
      modelId: modelId,
      modelPrefix: modelPrefix,
      iteration: iteration,
      modelProtocolVersion: protocol,
    );
  }

  // 交叉验证清单声明的模型文件与归档实际成员
  static void _validateDeclaredFiles(
    Map<String, dynamic> manifest,
    Set<String> actualNames,
  ) {
    final declaredPrimary =
        _stringList(manifest['models_included'], 'models_included');
    final actualPrimary = actualNames
        .where((name) => name.endsWith('.onnx') || name.endsWith('.pth'))
        .toSet();
    if (declaredPrimary.toSet().length != declaredPrimary.length ||
        declaredPrimary.toSet().difference(actualPrimary).isNotEmpty ||
        actualPrimary.difference(declaredPrimary.toSet()).isNotEmpty) {
      throw const FormatException('GKG 主模型声明与实际文件不一致');
    }
    final declaredFiles =
        _stringList(manifest['model_files_included'], 'model_files_included');
    final actualModelFiles =
        actualNames.where(_isModelArtifactFilename).toSet();
    if (declaredFiles.toSet().length != declaredFiles.length ||
        declaredFiles.toSet().difference(actualModelFiles).isNotEmpty ||
        actualModelFiles.difference(declaredFiles.toSet()).isNotEmpty) {
      throw const FormatException('GKG 模型制品声明与实际文件不一致');
    }
    final flags = <String, bool>{
      'includes_kb': actualNames.contains('knowledge_base.json'),
      'includes_staples': actualNames.contains('meta_staples.json'),
      'includes_hash_mapping': actualNames.contains('hash_mapping_report.json'),
      'includes_code_semantics': actualNames.contains('code_embeddings.npy') &&
          actualNames.contains('code_embeddings_idx.json'),
    };
    for (final entry in flags.entries) {
      if (manifest[entry.key] != entry.value) {
        throw FormatException(
          'GKG ' + entry.key + ' 与实际文件不一致',
        );
      }
    }
  }

  // 将清单列表转换为字符串列表
  static List<String> _stringList(Object? source, String field) {
    if (source is! List || source.any((value) => value is! String)) {
      throw FormatException('GKG ' + field + ' 必须是字符串列表');
    }
    return source.cast<String>().toList(growable: false);
  }

  // 校验根目录成员名和可选后缀
  static String _validateSafeFilename(
    String name, {
    List<String>? suffixes,
  }) {
    final safePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,159}$');
    if (!safePattern.hasMatch(name) ||
        name.contains('..') ||
        name.contains('/') ||
        name.contains('\\') ||
        utf8.encode(name).length > 200) {
      throw FormatException('GKG 文件名不安全: ' + name);
    }
    final deviceName = name.split('.').first.toUpperCase();
    final reserved = <String>{
      'CON',
      'PRN',
      'AUX',
      'NUL',
      ...List<String>.generate(9, (index) => 'COM' + (index + 1).toString()),
      ...List<String>.generate(9, (index) => 'LPT' + (index + 1).toString()),
    };
    if (reserved.contains(deviceName)) {
      throw FormatException('GKG 使用系统保留文件名: ' + name);
    }
    if (suffixes != null &&
        !suffixes.any((suffix) => name.toLowerCase().endsWith(suffix))) {
      throw FormatException('GKG 文件后缀不受支持: ' + name);
    }
    return name;
  }

  // 校验包名或模型前缀可以安全用于私有目录
  static void _validateSafeLabel(String name) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(name) ||
        name.contains('..')) {
      throw FormatException('GKG 包名或模型前缀不安全: ' + name);
    }
  }

  // 校验模型身份为标准 UUID 文本
  static void _validateModelId(String modelId) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(modelId)) {
      throw FormatException('GKG model_id 不是有效 UUID: ' + modelId);
    }
  }

  // 判断根目录文件是否属于允许的部署资产
  static bool _isAllowedRootFile(String name) {
    return name == 'manifest.json' ||
        _semanticFiles.contains(name) ||
        _isModelArtifactFilename(name);
  }

  // 判断文件名是否属于模型主图权重或轮次清单
  static bool _isModelArtifactFilename(String name) {
    return const <String>[
      '.artifacts.json',
      '.onnx.data',
      '.onnx',
      '.pth',
    ].any(name.toLowerCase().endsWith);
  }
}
