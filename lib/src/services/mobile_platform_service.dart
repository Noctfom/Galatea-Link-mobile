// Galatea Link mobile 原生平台桥接，管理共享文件和连接期间前台保活

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MobileSharedFile {
  // 保存原生侧复制到应用缓存的共享文件信息
  const MobileSharedFile({
    required this.name,
    required this.path,
    required this.mimeType,
  });

  final String name;
  final String path;
  final String mimeType;
}

class MobileAppInfo {
  // 保存原生安装包提供的稳定版本标识
  const MobileAppInfo({
    required this.applicationId,
    required this.versionName,
    required this.versionCode,
  });

  final String applicationId;
  final String versionName;
  final int versionCode;
}

class MobilePlatformService {
  // 创建移动端平台能力桥接服务
  MobilePlatformService();

  static const MethodChannel _channel = MethodChannel(
    'galatea_link_mobile/platform',
  );
  Future<void> Function(MobileSharedFile file)? _onSharedFile;

  // 注册原生事件并消费用于启动应用的共享文件
  Future<void> initialize({
    required Future<void> Function(MobileSharedFile file) onSharedFile,
  }) async {
    _onSharedFile = onSharedFile;
    _channel.setMethodCallHandler(_handleMethodCall);
    await _consumePendingSharedFile();
  }

  // 启动连接期间的 Android 前台保活服务
  Future<void> startKeepAlive() async {
    try {
      await _channel.invokeMethod<void>('startKeepAlive');
    } on MissingPluginException {
      if (kDebugMode) debugPrint('当前平台不支持前台保活');
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('启动前台保活失败: ${error.message}');
    }
  }

  // 停止 Android 前台保活服务
  Future<void> stopKeepAlive() async {
    try {
      await _channel.invokeMethod<void>('stopKeepAlive');
    } on MissingPluginException {
      if (kDebugMode) debugPrint('当前平台不支持前台保活');
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('停止前台保活失败: ${error.message}');
    }
  }

  // 读取当前安装包的应用标识和版本号
  Future<MobileAppInfo?> readAppInfo() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getAppInfo');
      if (raw == null ||
          raw['application_id'] is! String ||
          raw['version_name'] is! String ||
          raw['version_code'] is! int) {
        return null;
      }
      return MobileAppInfo(
        applicationId: raw['application_id'] as String,
        versionName: raw['version_name'] as String,
        versionCode: raw['version_code'] as int,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  // 使用系统浏览器打开经过校验的 HTTPS 地址
  Future<bool> openExternalUrl(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openExternalUrl',
            <String, String>{'url': uri.toString()},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  // 接收原生侧通知的新共享文件事件
  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method == 'sharedFileAvailable') {
      await _consumePendingSharedFile();
    }
    return null;
  }

  // 从原生缓存取出一个待处理共享文件
  Future<void> _consumePendingSharedFile() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getPendingSharedFile',
      );
      if (raw == null) return;
      final name = raw['name'];
      final path = raw['path'];
      if (name is! String || path is! String) return;
      await _onSharedFile?.call(
        MobileSharedFile(
          name: name,
          path: path,
          mimeType:
              raw['mime_type'] is String ? raw['mime_type'] as String : '',
        ),
      );
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('读取共享文件失败: ${error.message}');
    }
  }

  // 移除平台事件回调
  void dispose() {
    _onSharedFile = null;
    _channel.setMethodCallHandler(null);
  }
}
