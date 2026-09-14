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

正式发布时复制并重命名为：

```text
build/release/Galatea-Link-mobile-v0.2.2-universal.apk
```

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

构建后应使用 Android SDK 中最新的 `apksigner` 验证签名，并记录公开证书指纹：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\当前版本\apksigner.bat" verify --verbose --print-certs .\build\release\Galatea-Link-mobile-v0.2.2-universal.apk
```

0.2.2 正式签名证书 SHA-256 为 `aadcaf435d58231092c5ca0b597039f06a52dc546a6d673f18843dc45dcacf45`。以后每次正式构建都应与该值比较，发现变化时不要发布或覆盖安装

## 实体机首轮检查

1. 启动图标、应用名和浅色深色主题显示正常
2. 从文件选择器导入 `cards.cdb`、YDK 和模型协议 V3 GKG
3. 本地 ONNX 自检通过且重新启动后仍能加载模型
4. 使用电脑局域网地址连接 MDPro3，不能填写模拟器专用的 `10.0.2.2`
5. 验证加入房间、自动准备、房主开局、先后攻、连续决策和游戏内聊天
6. 切到后台再返回，确认网络与迟到 LLM 响应不会提交到过期时点
7. 对局完成后导出诊断日志，检查日志不包含 API Key 或房间密码

## 网络权限与排查

release 主清单必须包含 `android.permission.INTERNET`。这是安装时自动授予的普通权限，不会出现运行时授权弹窗

遇到 `Failed host lookup` 时依次检查：

1. 确认安装的是最新 release APK，而不是修复前的同版本文件
2. 暂停实体机 VPN 或代理并临时关闭私人 DNS 后重试
3. 用浏览器确认实体机自身可以解析目标域名
4. 连接局域网 MDPro3 时填写电脑局域网 IP，不要使用 `127.0.0.1` 或模拟器专用的 `10.0.2.2`
5. 确认手机与电脑网络允许互访，并放行电脑防火墙中的 MDPro3 TCP 端口

同一台实体设备上的 YGOMobile 本地房间使用 `172.19.0.1:7911`，可直接点击连接页的“手机本机 YGOMobile”快捷入口。应用会先进入概览并每 5 秒重试一次，最长等待 5 分钟，因此可以随后切换到 YGOMobile 创建房间

## 后台运行与文件打开

进入本机等待流程或普通服务器确认房间后，应用会启动前台服务并显示“游戏连接运行中”通知，主动断开或远端关闭后服务随即停止。普通服务器 TCP 已连接但十二秒内未确认房间时会返回连接页并显示错误。Android 13 及以上会在首次连接时请求通知权限

应用声明了 YDK、GKG 和 CDB 的打开入口。文件管理器通过 `content://` 授予的单文件读取权会由原生层复制为短期缓存，再交给 Flutter 层的原有校验流程。无需申请整个存储空间权限

部分 Android 文件管理器会把未知扩展名标为通用二进制或不提供“打开方式”。这种情况下使用应用内导入入口即可，不属于卡组解析故障
