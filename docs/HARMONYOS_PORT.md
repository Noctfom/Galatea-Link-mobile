# 鸿蒙版本迁移方案

## 推荐仓库策略

Android 稳定后，从同一仓库创建长期分支 `platform/harmonyos` 或单独仓库，不要在 Android 发布分支中直接替换平台插件。先验证目标是 OpenHarmony 兼容设备还是 HarmonyOS NEXT，两者的 SDK、商店发布和 Flutter 适配链路需要分别确认

鸿蒙应用标识建议继续使用：

```text
com.noctfom.galatealink
```

平台商店允许且不会与现有产品冲突时保持同一逻辑标识，便于下载页、更新清单和文档统一。签名证书仍按鸿蒙平台单独管理

## 可以直接复用的纯 Dart 层

- `game_protocol` 中的 YGOPro TCP 分帧、房间握手和 OCG 消息解析
- `game_state` 中仅依赖可见数据的对局状态
- `decision` 中的合法动作、Core/LLM 编排、回退和自主介入
- YDK 文本、YDKe 卡组码、GKG 容器和模型协议 V3 元数据解析
- 更新清单、日志格式和大部分单元测试

## 必须重新适配的平台边界

- 文件选择与 YDK、GKG、CDB 文件关联
- 安全保存房间密码与 LLM API Key
- 应用私有目录、SQLite 动态库与数据库生命周期
- 剪贴板读取提示、浏览器跳转、通知和后台保活
- ONNX Runtime 原生库、ABI 打包与模型会话桥接
- 应用版本读取、签名、安装包和商店更新

ONNX Runtime 是风险最高的部分，应作为第一个技术验证点。若目标平台没有可维护的 Flutter 插件，可保留 Dart 决策层并为鸿蒙原生 ONNX Runtime 编写独立 FFI 或平台通道适配，不应把 Android AAR 带入鸿蒙构建

## 分阶段落地

1. 使用 DevEco Studio 创建可签名的最小应用并验证 Flutter/OpenHarmony 工具链
2. 迁移纯 Dart 协议测试，保证消息分帧、卡组和 GameState 测试结果与 Android 一致
3. 实现 TCP、文件、安全存储、SQLite 和日志平台服务
4. 打通本地 YGOMobile 房间登录、自动准备、房主开局和聊天
5. 验证 ONNX Runtime 与模型协议 V3，再接入 Core/Hybrid 策略
6. 接入 LLM、后台策略和鸿蒙专用更新发布流程
7. 在模拟器与至少两种实体设备上执行长局、切后台、锁屏、弱网和大模型包测试

每完成一层都应保留平台无关测试，不要先复制 Android UI 再逐个处理编译错误。这样可以把鸿蒙差异限制在清晰的平台服务接口内
