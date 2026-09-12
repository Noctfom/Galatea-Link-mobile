// Galatea Link mobile 版本检测测试，验证清单边界和版本号比较

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:galatea_link_mobile/src/services/mobile_platform_service.dart';
import 'package:galatea_link_mobile/src/update/mobile_update_service.dart';

class FakeMobilePlatformService extends MobilePlatformService {
  // 创建提供固定应用版本的测试平台桥接
  FakeMobilePlatformService(this.info);

  final MobileAppInfo info;
  Uri? openedUrl;

  // 返回测试指定的当前应用版本
  @override
  Future<MobileAppInfo?> readAppInfo() async => info;

  // 记录测试中请求打开的更新页面
  @override
  Future<bool> openExternalUrl(Uri uri) async {
    openedUrl = uri;
    return true;
  }
}

// 创建一份符合稳定版协议的测试清单
Map<String, Object?> updateManifest() {
  return <String, Object?>{
    'schema_version': 1,
    'channel': 'stable',
    'version_name': '1.2.0',
    'version_code': 12,
    'minimum_supported_version_code': 8,
    'download_url':
        'https://github.com/Noctfom/Galatea-Link-mobile/releases/download/v1.2.0/app.apk',
    'release_page_url':
        'https://github.com/Noctfom/Galatea-Link-mobile/releases/tag/v1.2.0',
    'sha256': List<String>.filled(64, 'a').join(),
    'release_notes': '测试版本',
    'published_at': '2026-09-13T00:00:00Z',
  };
}

// 运行稳定版清单解析和更新跳转测试
void main() {
  test('compares versionCode and opens validated release page', () async {
    final platform = FakeMobilePlatformService(
      const MobileAppInfo(
        applicationId: 'com.noctfom.galatealink',
        versionName: '1.0.0',
        versionCode: 7,
      ),
    );
    final service = MobileUpdateService(
      platformService: platform,
      client: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode(updateManifest())),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.check();
    await service.openReleasePage(result);

    expect(result.updateAvailable, isTrue);
    expect(result.updateRequired, isTrue);
    expect(platform.openedUrl, result.latest.releasePageUrl);
    service.dispose();
  });

  test('rejects insecure download url', () {
    final manifest = updateManifest()
      ..['download_url'] = 'http://example.com/app.apk';

    expect(
      () => MobileUpdateManifest.fromJson(
        Map<String, dynamic>.from(manifest),
      ),
      throwsFormatException,
    );
  });
}
