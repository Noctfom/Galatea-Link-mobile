# Galatea Link mobile 独立客户端方案

Galatea Link mobile 直接连接 MDPro3/YGOPro 游戏服务器，在手机本地完成 Link 的游戏客户端能力、可见状态维护、Core V3 ONNX 推理、LLM 决策、策略控制和游戏内聊天。电脑端 Link 服务和 AstrBot 都不是运行前提

## 运行边界

```text
Flutter UI
  ├── MDPro3/YGOPro TCP 客户端
  ├── 在线可见协议解析器
  ├── GameState 与合法动作
  ├── Core V3 ONNX Runtime
  ├── LLM API 客户端
  ├── RuleBot 安全回退
  ├── 游戏聊天
  └── 设置、模型和服务器快捷入口
          │
          ├── TCP ── MDPro3/YGOPro 游戏服务器
          ├── HTTPS ── LLM 服务商
          └── 本地文件 ── ONNX GKG 模型包
```

游戏王规则仍由 MDPro3/YGOPro 服务器权威执行，移动端复现的是 Link 的 Agent 客户端和决策流程，不在手机里复制完整 YGOcore 规则引擎

## 与 PC Link 的关系

PC Link 和移动端共享协议语义，但不共享运行时状态。移动端只借鉴和复现这些稳定契约：

- MDPro3/YGOPro 在线分包和消息字段
- 在线协议不含本地 Core 幽灵字节的解析规则
- 玩家可见 GameState 和合法动作
- `galatea.llm_observation.v1` 观察结构
- 模型协议 V3 的 ONNX 输入、动作槽位和制品身份
- LLM JSON 决策、超时回退、自主调整和游戏聊天语义

移动端不导入 Python 模块、不加载 PTH 或 Torch、不请求 PC Link API。PC Link 的录包和测试 fixture 用来验证 Dart 实现的一致性

## 页面和入口

连接页面与设置页面分开

### 游戏连接

- 服务器地址和端口
- 房间密码
- 玩家名称
- 卡组选择
- 先后攻偏好
- 连接、断开、重新连接
- 已保存服务器快捷入口

移动端填写的是 MDPro3 游戏服务器地址，例如 `s1.ygo233.com:233`。Android 模拟器访问电脑本机服务时使用 `10.0.2.2` 加游戏端口

### 应用设置

- ONNX 模型和 GKG 导入
- Core greedy/deployment 与温度
- core-only、hybrid、llm-review、llm-only
- Core 置信度阈值和 LLM 时间预算
- LLM Base URL、模型、Token、温度、思考和缓存
- 自主调整总开关、允许模式、阈值护栏和 TTL
- 游戏聊天开关与自动发言策略
- 主题、日志和通知

LLM API Key 和游戏密码使用 Android Keystore 或安全存储，不进入诊断日志

### 对局页面

- 当前阶段、双方 LP、玩家视角和剩余时间
- 可见场面和连锁
- 当前合法动作
- Core 动作、置信度和采样策略
- LLM 决策耗时、结果和失败回退
- 游戏内聊天
- 事件和解析错误入口

## 本地运行时

### 游戏网络层

使用 Dart Socket 或 Android 原生网络实现 YGOPro TCP 长连接，处理长度前缀、登录、房间、座位、猜拳、先后攻、心跳、时间和断线

网络层必须和 UI、LLM、ONNX 推理解耦。模型慢或网络请求慢时仍要继续处理收包和心跳

### 在线协议解析层

使用游标读取器和消息注册表移植 PC Link 在线解析：

- 不添加本地 Core 才有的字节
- 每个 OCG 消息类型声明精确字段和长度
- 未知类型没有可靠长度时拒绝继续生成动作并记录诊断
- 解析失败不猜测状态，不提交自由字节
- 所有进入 GameState 的数据都属于服务器可见范围

### GameState 与观察层

维护双方 LP、场地、公开卡片、手牌数量、墓地、除外、连锁、阶段、当前玩家、计时和合法动作。观察构建器输出与 PC Link 同语义的 `galatea.llm_observation.v1`

对手隐藏手牌、隐藏卡组和服务器未发送的信息永远不能进入观察

### Core V3 ONNX

移动端只接受经过验证的 V3 ONNX 制品。GKG 导入后按模型 UUID 隔离主图、外置权重、知识库、代码向量和索引。运行时使用 ONNX Runtime Mobile，输入编码在 Dart 或原生层实现

Core 推理需要在独立 isolate 或原生线程执行。greedy 使用最高分动作，deployment 使用 Core 温度采样。模型缺失、输入不完整、推理超时或身份不匹配时进入 RuleBot

### LLM 与决策协调

LLM 调用直接访问 OpenAI Compatible 接口，输入只有当前玩家可见观察、合法动作、可选 Core 建议和不可信聊天上下文。每个决策绑定递增 request id，旧请求即使迟到也不能提交

支持 Core、LLM、hybrid 和 LLM review 介入模式。LLM 超时、网络失败、无效 JSON、非法 choice id 和决策过期都必须快速回退，不阻塞游戏网络线程

### RuleBot

移动端至少实现确认、Yes/No、单动作、结束和取消等基础安全回退。复杂选择必须依据合法动作候选和协议打包器，不允许通过随机字节碰运气

## 本地模型包和资源

当前 Core GKG 包可能接近 1 GB。导入页需要显示进度、临时空间、剩余空间、模型 UUID、协议版本和失败原因。只接受部署包格式 2、检查点格式 2、模型协议 V3 的 ONNX 制品

PTH 文件可以保留在 GKG 中作为发布记录，但移动端不加载它；用户选择模型时必须明确选择 ONNX 制品

卡片数据库和语义资产放在应用私有目录。应用卸载或用户删除模型时才清理这些文件，不把大文件放进 APK

## 开发阶段

截至 `0.1.0+1`，M0 至 M4 的实现和自动化测试已经完成，M5 已完成 Android 模拟器和真实在线房间验证，剩余重点是实体设备、长时间运行和正式签名

### M0 工程和协议回放 已完成

- 保留 Flutter 工程作为独立项目
- 增加 Dart 二进制游标、分包器和消息注册表
- 从 PC Link 整理脱敏的 MDPro3 消息 fixture
- 用模拟器和实体机验证直接 TCP 建连

### M1 直接连接和聊天 已完成

- 实现登录、房间、座位、猜拳和先后攻
- 实现游戏内聊天收发
- 实现游戏连接页、设置页和服务器快捷入口
- 电脑端 Link 关闭时仍能进入测试房间

### M2 GameState 与最小 Agent 已完成

- 移植可见 GameState 和合法动作
- 实现基础 RuleBot
- 输出 LLM 观察结构
- 通过一局 LLM-only 或基础回退对局

### M3 Core ONNX 已完成

- 选择并验证 ONNX Runtime Mobile 绑定
- 移植 V3 编码器和语义资产读取
- 导入 GKG、选择模型、运行 greedy/deployment
- 与 PC Link 比较相同 fixture 的张量、动作和置信度

### M4 混合决策和自主调整 已完成

- 接入 LLM、JSON 校验、缓存和超时
- 支持 hybrid、LLM review 和 Core 建议
- 加入自主调整开关、阈值护栏、强制时点和 TTL
- 验证断网、切后台和迟到响应不会卡住对局

### M5 实机对局 进行中

- Android 模拟器公开服务器测试
- Android 实体机局域网测试
- 真实 MDPro3 对局、聊天和长时间运行
- APK 签名、更新和大模型包导入体验

## 鸿蒙分支原则

鸿蒙版本和 Android 版本共享协议及 Agent 语义，不共享平台插件实现。以下目录优先保持跨平台纯 Dart：

- `lib/src/game_protocol`
- `lib/src/game_state.dart`
- `lib/src/decision`
- 模型协议 V3 张量规格和不依赖原生库的编码逻辑

文件选择、安全存储、数据库、ONNX Runtime、网络权限、应用生命周期和安装更新由鸿蒙分支提供独立适配。两条平台分支向外维持相同的模型协议和 LLM 观察结构，避免平台差异进入决策层

## 第一轮测试条件

- MDPro3/YGOPro 测试服务器地址、端口和房间密码
- 一份可重复的测试卡组
- Core 模型协议 V3 的 ONNX GKG 包
- Android 模拟器或实体设备
- LLM API 配置和密钥

第一轮不需要启动 PC Link。移动端连接页填写游戏服务器地址，设置页填写 LLM 和模型信息
