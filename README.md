# Galatea Link mobile

Galatea Link 的独立 Flutter 移动客户端，直接连接 MDPro3/YGOPro 游戏服务器并在设备本地运行 Agent 流程，不依赖 PC Link API、AstrBot、Python 或 Torch

当前版本为 `0.2.0+4`，Android 应用标识为 `com.noctfom.galatealink`。Android 模拟器上的本地房间、233 在线房间、完整卡组上传和 LLM 连续操作已经打通，实体设备兼容性验证正在进行

## 当前能力

- 直接连接兼容 YGOPro 协议的游戏服务器并上传主卡组、额外卡组和副卡组
- 维护仅由在线服务器公开数据构成的对可见 GameState
- 导入 GKG V2 中的模型协议 V3 ONNX 制品并执行原生推理
- 支持 core-only、hybrid、llm-review 和 llm-only 决策模式
- 支持 Core 温度、置信度阈值、指定 LLM 时点和对局内时间预算
- 支持带人工护栏和 TTL 的 LLM 临时自主调整
- 收发游戏内聊天，并将有界聊天历史作为不可信社交上下文提供给 LLM
- 保存七天内的脱敏诊断日志并导出 JSONL
- 保存多份包含房间密码的命名连接配置并快速套用手机本机 YGOMobile 参数
- 从 YDK 文本、YDKe 卡组码和 Ourocg 分享链接导入卡组
- 识别前台启动时的卡组剪贴板内容并在确认后导入
- 注册 YDK、GKG 和 CDB Android 打开入口
- 在活动游戏连接期间通过可见通知保持后台响应
- 在设置页手动读取受控 HTTPS 清单检查稳定版更新并跳转发布页

## 开发命令

需要 Flutter stable、Android SDK 和可用的 Android 模拟器或实体设备

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

宿主工程已经生成，日常开发不需要再次执行 `flutter create`


Windows 如果在 `flutter pub get` 中看到插件需要符号链接的提示，请在系统“开发者设置”中开启开发者模式后重新执行。该设置只影响本机 Flutter 插件链接，不改变项目源码

## 安装测试包

仓库不提交 APK、GKG、ONNX、PTH、cards.cdb、日志或任何密钥。发布构建默认输出到：

```text
build/app/outputs/flutter-apk/app-release.apk
```

实体设备开启开发者模式和 USB 调试后，可以执行：

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

当前未配置私有发布密钥时会使用 Android 调试密钥签署 release 构建，可直接用于实体机测试但不应作为应用商店正式签名。完整流程见 [Android 构建与实体机测试](docs/ANDROID_RELEASE.md)

正式发布、版本清单和 GitHub Release 流程见 [发布与更新](docs/RELEASE_AND_UPDATE.md)，数据处理边界见 [隐私说明](docs/PRIVACY.md)

## 使用顺序

1. 在“应用设置”中导入 `cards.cdb`
2. 导入模型协议 V3 的 ONNX GKG，选择模型并运行原生自检
3. 配置 Core、LLM 和自主调整策略，这些设置不要求先连接游戏
4. 在连接页选择 YDK 卡组，填写 MDPro3/YGOPro 地址、端口、房间信息和玩家名称
5. 连接对局后在概览页查看决策和可见状态，在聊天页收发游戏内消息

Android 官方模拟器访问电脑本机游戏服务器时使用 `10.0.2.2`，实体设备应填写电脑的局域网地址。实体设备与电脑需要位于可互访的局域网，电脑防火墙也要允许对应 TCP 端口。LLM API Key 和房间密码保存在系统安全存储中

连接页的“保存配置”会将非敏感字段写入应用偏好，并将每份配置的房间密码单独写入系统安全存储。同名保存会覆盖原配置，保存空密码会删除旧密码。“手机本机 YGOMobile”会套用 `127.0.0.1:7911`，用于连接同一台 Android 设备上监听本机端口的游戏房间

Android 的 `INTERNET` 权限在安装时自动授予，不会显示运行时弹窗。Android 13 及以上首次成功连接时会申请通知权限，用于显示对局保活通知；拒绝通知不会改变协议内容，但部分系统会进一步限制后台运行

从文件管理器打开 YDK、GKG 或 CDB 时，应用仅获得用户所选文件的临时读取权并复制到私有缓存，不申请整个存储空间权限。不同文件管理器对自定义扩展名和 MIME 类型的识别能力不同，未出现本应用时仍可使用应用内文件选择器

## 目录职责

- `lib/src/game_protocol`：YGOPro TCP 分包、登录载荷和 OCG 在线协议解析
- `lib/src/models`：GKG、ONNX Runtime、V3 张量和语义缓存
- `lib/src/decision`：合法动作目录、Core/LLM 编排、回退和自主介入
- `lib/src/cards` 与 `lib/src/deck`：卡片资料库和 YDK 读取
- `lib/src/services`：安全设置、平台文件桥接、前台保活和脱敏诊断日志
- `lib/src/standalone_app.dart`：独立移动端连接、概览、聊天和设置界面

完整边界和阶段说明见 [docs/STANDALONE_CLIENT_PLAN.md](docs/STANDALONE_CLIENT_PLAN.md)

## 开源协议

项目使用 `GPL-3.0-only`，与 Galatea Core 当前声明保持一致。应用设置页可以查看 Flutter 与依赖组件在运行时登记的开源许可，分发 APK 时应保留仓库中的 `LICENSE` 和 [第三方组件说明](THIRD_PARTY_NOTICES.md)

## 鸿蒙分支边界

鸿蒙版本建议从当前仓库另建长期分支。`game_protocol`、`game_state`、`decision` 和大部分模型协议代码保持纯 Dart 复用；文件选择、安全存储、SQLite、ONNX Runtime 和应用外壳作为平台适配层单独实现，避免反向增加 Android 主线的运行依赖。具体迁移清单见 [鸿蒙版本迁移方案](docs/HARMONYOS_PORT.md)
