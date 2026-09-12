// Galatea Link mobile 版本检测服务，读取受控 HTTPS 清单并跳转可信下载页

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/mobile_platform_service.dart';

const String defaultMobileUpdateManifestUrl =
    'https://galatea.noctfom.top/mobile/update.json';

class MobileUpdateManifest {
  // 保存服务端发布清单中经过边界校验的稳定版本信息
  const MobileUpdateManifest({
    required this.versionName,
    required this.versionCode,
    required this.minimumSupportedVersionCode,
    required this.downloadUrl,
    required this.releasePageUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.publishedAt,
  });

  final String versionName;
  final int versionCode;
  final int minimumSupportedVersionCode;
  final Uri downloadUrl;
  final Uri releasePageUrl;
  final String sha256;
  final String releaseNotes;
  final DateTime? publishedAt;

  // 从版本清单 JSON 恢复并验证稳定发布信息
  factory MobileUpdateManifest.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 || json['channel'] != 'stable') {
      throw const FormatException('更新清单版本或发布通道不受支持');
    }
    final versionName = json['version_name'];
    final versionCode = json['version_code'];
    final minimumCode = json['minimum_supported_version_code'] ?? 1;
    final rawDownloadUrl = json['download_url'];
    final rawReleasePageUrl = json['release_page_url'] ?? rawDownloadUrl;
    final sha256 = json['sha256'];
    if (versionName is! String ||
        versionName.isEmpty ||
        versionCode is! int ||
        versionCode < 1 ||
        minimumCode is! int ||
        minimumCode < 1 ||
        rawDownloadUrl is! String ||
        rawReleasePageUrl is! String ||
        sha256 is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw const FormatException('更新清单字段无效');
    }
    final downloadUrl = Uri.tryParse(rawDownloadUrl);
    final releasePageUrl = Uri.tryParse(rawReleasePageUrl);
    if (!_isSecureWebUrl(downloadUrl) || !_isSecureWebUrl(releasePageUrl)) {
      throw const FormatException('更新下载地址必须使用 HTTPS');
    }
    final rawNotes = json['release_notes'];
    final notes = rawNotes is String ? rawNotes.trim() : '';
    if (notes.length > 12000) throw const FormatException('更新说明过长');
    final rawPublishedAt = json['published_at'];
    return MobileUpdateManifest(
      versionName: versionName,
      versionCode: versionCode,
      minimumSupportedVersionCode: minimumCode,
      downloadUrl: downloadUrl!,
      releasePageUrl: releasePageUrl!,
      sha256: sha256.toUpperCase(),
      releaseNotes: notes,
      publishedAt: rawPublishedAt is String
          ? DateTime.tryParse(rawPublishedAt)?.toUtc()
          : null,
    );
  }

  // 判断地址是否为带主机名的 HTTPS 网页
  static bool _isSecureWebUrl(Uri? value) {
    return value != null && value.scheme == 'https' && value.host.isNotEmpty;
  }
}

class MobileUpdateCheck {
  // 保存本机版本与远端稳定版本的比较结果
  const MobileUpdateCheck({required this.current, required this.latest});

  final MobileAppInfo current;
  final MobileUpdateManifest latest;

  // 返回远端版本是否比当前安装版本更新
  bool get updateAvailable => latest.versionCode > current.versionCode;

  // 返回当前版本是否低于服务端最低支持版本
  bool get updateRequired =>
      current.versionCode < latest.minimumSupportedVersionCode;
}

class MobileUpdateService {
  // 创建支持测试客户端注入的版本检测服务
  MobileUpdateService({
    required MobilePlatformService platformService,
    http.Client? client,
  })  : _platformService = platformService,
        _client = client ?? http.Client();

  static const int _maximumManifestBytes = 256 * 1024;
  final MobilePlatformService _platformService;
  final http.Client _client;

  // 获取本机应用信息并检查远端稳定版本清单
  Future<MobileUpdateCheck> check({
    String manifestUrl = defaultMobileUpdateManifestUrl,
  }) async {
    final current = await _platformService.readAppInfo();
    if (current == null) throw StateError('当前平台无法读取应用版本');
    final uri = Uri.tryParse(manifestUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('版本清单地址必须使用 HTTPS');
    }
    final response = await _client.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'Galatea-Link-mobile-update-check',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      throw StateError('稳定版更新服务尚未发布');
    }
    if (response.statusCode != 200) {
      throw StateError('更新服务返回 HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > _maximumManifestBytes) {
      throw const FormatException('更新清单为空或超过安全限制');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const FormatException('更新清单必须是 JSON 对象');
    return MobileUpdateCheck(
      current: current,
      latest: MobileUpdateManifest.fromJson(
        Map<String, dynamic>.from(decoded),
      ),
    );
  }

  // 使用系统浏览器打开版本清单指定的发布页
  Future<void> openReleasePage(MobileUpdateCheck result) async {
    final opened = await _platformService.openExternalUrl(
      result.latest.releasePageUrl,
    );
    if (!opened) throw StateError('设备上没有可打开更新页面的应用');
  }

  // 释放版本检测使用的网络客户端
  void dispose() {
    _client.close();
  }
}
