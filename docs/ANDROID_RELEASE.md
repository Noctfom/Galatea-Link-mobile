# Android 构建与实体机测试

本文用于生成 Galatea Link mobile 的实体机测试包。模型、卡片数据库、API Key 和房间密码均由安装后的应用自行导入或配置，不进入 APK

## 环境检查

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
```

## 生成启动器图标

源图保存在 `docs/logo.png`，修改源图后执行：

```bash
dart run flutter_launcher_icons
```

生成的 Android 与 Web 图标应当提交到仓库，确保其他开发环境构建结果一致

## 构建通用测试 APK

```bash
flutter build apk --release
```

产物路径：

```text
build/app/outputs/flutter-apk/app-release.apk
```

该通用包同时包含 Android 支持的多个 ABI，适合第一次实体机验证。需要减小体积时再执行 `flutter build apk --release --split-per-abi`

## 安装与升级

连接已开启 USB 调试的设备后执行：

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

如果旧安装包使用不同签名，Android 会拒绝覆盖安装。这种情况下先从应用内导出需要保留的诊断日志和配置，再卸载旧版本后安装

## 签名边界

仓库默认在缺少 `android/key.properties` 时使用调试密钥签署 release 包，便于本地和实体机测试。正式分发前应创建独立发布密钥并配置 `android/key.properties`

`android/key.properties`、JKS、Keystore 和密码不得提交到 Git。可使用以下字段创建本机配置：

```properties
storePassword=本机发布密钥密码
keyPassword=本机发布密钥密码
keyAlias=上传密钥别名
storeFile=密钥文件绝对路径
```

## 实体机首轮检查

1. 启动图标、应用名和浅色深色主题显示正常
2. 从文件选择器导入 `cards.cdb`、YDK 和模型协议 V3 GKG
3. 本地 ONNX 自检通过且重新启动后仍能加载模型
4. 使用电脑局域网地址连接 MDPro3，不能填写模拟器专用的 `10.0.2.2`
5. 验证加入房间、自动准备、房主开局、先后攻、连续决策和游戏内聊天
6. 切到后台再返回，确认网络与迟到 LLM 响应不会提交到过期时点
7. 对局完成后导出诊断日志，检查日志不包含 API Key 或房间密码

