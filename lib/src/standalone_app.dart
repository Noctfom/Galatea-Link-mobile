// Galatea Link mobile 独立界面，直接连接 MDPro3 并展示本地运行时状态

import 'dart:convert';

import 'package:flutter/material.dart';

import 'deck/deck_file_loader.dart';
import 'deck/deck_library_service.dart';
import 'deck/ydk_deck.dart';
import 'app_decision_settings.dart';
import 'game_chat.dart';
import 'game_connection_settings.dart';
import 'game_protocol/ygo_client.dart';
import 'local_game_controller.dart';

class StandaloneApp extends StatefulWidget {
  const StandaloneApp({super.key, required this.controller});

  final LocalGameController controller;

  @override
  State<StandaloneApp> createState() => _StandaloneAppState();
}

class _StandaloneAppState extends State<StandaloneApp> {
  // 恢复本地游戏连接设置
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  // 释放本地游戏控制器
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  // 构建独立移动端应用根节点
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        if (!widget.controller.initialized) {
          return MaterialApp(
            title: 'Galatea Link mobile',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff2f6f62),
              ),
              useMaterial3: true,
            ),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final connected = widget.controller.state == YgoClientState.connected;
        return MaterialApp(
          title: 'Galatea Link mobile',
          debugShowCheckedModeBanner: false,
          themeMode:
              widget.controller.darkTheme ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff2f6f62),
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff72b5a5),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: connected
              ? StandaloneHome(controller: widget.controller)
              : GameConnectionScreen(controller: widget.controller),
        );
      },
    );
  }
}

class GameConnectionScreen extends StatefulWidget {
  const GameConnectionScreen({super.key, required this.controller});

  final LocalGameController controller;

  @override
  State<GameConnectionScreen> createState() => _GameConnectionScreenState();
}

class _GameConnectionScreenState extends State<GameConnectionScreen> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _passwordController;
  late final TextEditingController _nameController;
  late final TextEditingController _gameIdController;
  bool _preferSecond = false;
  String _deckLabel = '尚未选择 YDK 卡组';

  // 初始化游戏服务器连接表单
  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _hostController = TextEditingController(text: settings.host);
    _portController = TextEditingController(text: settings.port.toString());
    _passwordController = TextEditingController(text: settings.password);
    _nameController = TextEditingController(text: settings.playerName);
    _gameIdController = TextEditingController(text: settings.gameId.toString());
    _preferSecond = settings.preferSecond;
    final deck = widget.controller.deck;
    if (deck != null) {
      _deckLabel =
          '${deck.name} · 主卡组 ${deck.main.length} · 额外 ${deck.extra.length}';
    }
  }

  // 释放游戏连接表单控制器
  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _gameIdController.dispose();
    super.dispose();
  }

  // 解析整数输入并显示表单错误
  int? _parseInt(String value, String label) {
    final result = int.tryParse(value.trim());
    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label 必须是整数')));
    }
    return result;
  }

  // 提交 MDPro3 直接连接请求
  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final port = _parseInt(_portController.text, '端口');
    final gameId = _parseInt(_gameIdController.text, '房间编号');
    if (port == null || gameId == null) return;
    if (widget.controller.deck == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择有效的 YDK 卡组')));
      return;
    }
    try {
      await widget.controller.connect(
        GameConnectionSettings(
          host: _hostController.text,
          port: port,
          password: _passwordController.text,
          playerName: _nameController.text,
          gameId: gameId,
          protocolVersion: widget.controller.settings.protocolVersion,
          preferSecond: _preferSecond,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.errorMessage ?? '游戏服务器连接失败')),
      );
    }
  }

  // 打开独立卡组库并刷新当前选择摘要
  Future<void> _pickDeck() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalDeckLibraryPage(controller: widget.controller),
      ),
    );
    if (!mounted) return;
    final deck = widget.controller.deck;
    setState(() {
      _deckLabel = deck == null
          ? '尚未选择 YDK 卡组'
          : '${deck.name} · 主卡组 ${deck.main.length} · 额外 ${deck.extra.length} · 副卡组 ${deck.side.length}';
    });
  }

  // 构建直接连接 MDPro3 的页面
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接游戏服务器'),
        actions: [
          IconButton(
            tooltip: '卡组库',
            onPressed: _pickDeck,
            icon: const Icon(Icons.style_outlined),
          ),
          IconButton(
            tooltip: '诊断日志',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalDiagnosticLogPage(controller: controller),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: '应用设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalSettingsPage(controller: controller),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: controller.darkTheme ? '切换浅色主题' : '切换深色主题',
            onPressed: () => controller.setDarkTheme(!controller.darkTheme),
            icon: Icon(
              controller.darkTheme ? Icons.light_mode : Icons.dark_mode,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.sports_esports, size: 50),
                      const SizedBox(height: 12),
                      Text(
                        'Galatea Link mobile',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      const Text('直接连接 MDPro3/YGOPro，电脑端 Link 和 AstrBot 不需要运行'),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: '游戏服务器地址',
                          hintText: 's1.ygo233.com',
                          prefixIcon: Icon(Icons.dns),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '端口',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _gameIdController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '房间编号',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '房间密码',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: '玩家名称',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: controller.isBusy ? null : _pickDeck,
                        icon: const Icon(Icons.style_outlined),
                        label: const Text('选择与管理卡组'),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _deckLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('偏好后攻'),
                        subtitle: const Text('关闭时猜拳获胜后优先选择自己先攻'),
                        value: _preferSecond,
                        onChanged: (value) =>
                            setState(() => _preferSecond = value),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: controller.isBusy ||
                                controller.deck == null ||
                                !controller.deck!.isValid
                            ? null
                            : _connect,
                        icon: controller.isBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(
                          controller.isBusy
                              ? '连接中'
                              : controller.deck == null ||
                                      !controller.deck!.isValid
                                  ? '请先选择卡组'
                                  : '连接游戏',
                        ),
                      ),
                      if (controller.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          controller.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Text(
                        '密码只写入本机安全存储。Android 模拟器连接电脑本机服务时，地址使用 10.0.2.2',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StandaloneHome extends StatefulWidget {
  const StandaloneHome({super.key, required this.controller});

  final LocalGameController controller;

  @override
  State<StandaloneHome> createState() => _StandaloneHomeState();
}

class _StandaloneHomeState extends State<StandaloneHome> {
  int _index = 0;

  // 构建本地对局导航页面
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pages = <Widget>[
      LocalOverviewPage(controller: controller),
      LocalChatPage(controller: controller),
      LocalSettingsPage(controller: controller, embedded: true),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _index == 0
              ? '对局概览'
              : _index == 1
                  ? '游戏聊天'
                  : '应用设置',
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalDeckLibraryPage(controller: controller),
              ),
            ),
            icon: const Icon(Icons.style_outlined),
            tooltip: '卡组库',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalDiagnosticLogPage(controller: controller),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: '诊断日志',
          ),
          IconButton(
            onPressed: () => controller.setDarkTheme(!controller.darkTheme),
            icon: Icon(
              controller.darkTheme ? Icons.light_mode : Icons.dark_mode,
            ),
          ),
          IconButton(
            onPressed: controller.isBusy ? null : controller.disconnect,
            icon: const Icon(Icons.logout),
            tooltip: '断开游戏',
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '概览',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: '聊天',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class LocalOverviewPage extends StatelessWidget {
  const LocalOverviewPage({super.key, required this.controller});

  final LocalGameController controller;

  // 构建本地 TCP 对局概览和协议诊断
  @override
  Widget build(BuildContext context) {
    final effectiveSettings = controller.effectiveDecisionSettings;
    final activeOverride = controller.activeAutonomousOverride;
    final readyPlayers = controller.roomReady.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .join(', ');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${controller.settings.host}:${controller.settings.port}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text('TCP 状态：${controller.state.name} · 房间阶段：${controller.roomPhase}'),
        Text(
          '大厅身份：${controller.isRoomHost ? '房主' : '参与者'} · 模式 ${controller.roomDuelMode == 2 ? '双打' : '单打'} · 已准备 ${readyPlayers.isEmpty ? '-' : readyPlayers}',
        ),
        Text(
          'Core 玩家：${controller.gameState.playerId} · 计时玩家：${controller.timePlayer ?? '-'} · 剩余：${controller.timeLeft ?? '-'} 秒',
        ),
        if (controller.deck != null) ...[
          const SizedBox(height: 6),
          Text(
            '卡组：${controller.deck!.name} · 主卡组 ${controller.deck!.main.length} · 额外 ${controller.deck!.extra.length} · 座位 ${controller.assignedPlayer ?? '-'}',
          ),
        ],
        if (effectiveSettings.mode != 'llm_only' &&
            controller.selectedModel == null) ...[
          const SizedBox(height: 10),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const ListTile(
              leading: Icon(Icons.warning_amber_outlined),
              title: Text('尚未安装本地模型'),
              subtitle: Text('当前 Core 或混合模式只能使用安全规则回退，请在设置中导入 GKG'),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StateMetric(label: '回合', value: '${controller.gameState.turn}'),
            _StateMetric(
              label: '阶段',
              value: phaseName(controller.gameState.phase),
            ),
            _StateMetric(
              label: '我方 LP',
              value:
                  '${controller.gameState.playerId == 0 ? controller.gameState.lp0 : controller.gameState.lp1}',
            ),
            _StateMetric(
              label: '对方 LP',
              value:
                  '${controller.gameState.playerId == 0 ? controller.gameState.lp1 : controller.gameState.lp0}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('可见状态', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '我方手牌 ${controller.gameState.playerId == 0 ? controller.gameState.hand0Count : controller.gameState.hand1Count} · 对方手牌 ${controller.gameState.playerId == 0 ? controller.gameState.hand1Count : controller.gameState.hand0Count}',
                ),
                Text(
                  '我方墓地 ${controller.gameState.playerId == 0 ? controller.gameState.grave0Count : controller.gameState.grave1Count} · 对方墓地 ${controller.gameState.playerId == 0 ? controller.gameState.grave1Count : controller.gameState.grave0Count}',
                ),
                Text(
                  '我方额外 ${controller.gameState.playerId == 0 ? controller.gameState.extra0Count : controller.gameState.extra1Count} · 对方额外 ${controller.gameState.playerId == 0 ? controller.gameState.extra1Count : controller.gameState.extra0Count}',
                ),
                Text(
                  '场上可见实体 ${controller.gameState.cards.length} · 连锁 ${controller.gameState.chain.length}',
                ),
                Text(
                  '最近决策 ${controller.lastDecisionSource ?? '-'} · ${controller.lastDecisionDescription ?? '无'}',
                ),
                Text(
                  '最近响应 ${controller.lastResponsePayload == null ? '-' : formatPayload(controller.lastResponsePayload!)} · 重试 ${controller.retryCount}',
                ),
                Text(
                  '当前策略 ${effectiveSettings.mode} · Core 阈值 ${effectiveSettings.coreConfidenceThreshold.toStringAsFixed(2)}${activeOverride == null ? '' : ' · 临时覆盖剩余 ${activeOverride.remainingDecisions} 次'}',
                ),
                if (controller.isDeciding) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  const Text('LLM 正在异步决策'),
                ],
                if (controller.lastDecisionElapsed != null)
                  Text(
                    '耗时 ${controller.lastDecisionElapsed!.inMilliseconds} ms · Prompt ${controller.lastPromptTokens ?? '-'} · Completion ${controller.lastCompletionTokens ?? '-'} · 缓存 Token ${controller.lastCachedTokens ?? '-'}',
                  ),
                if (controller.lastCoreConfidence != null)
                  Text(
                    'Core 置信度 ${(controller.lastCoreConfidence! * 100).toStringAsFixed(1)}% · 局面价值 ${controller.lastCoreValue?.toStringAsFixed(3) ?? '-'}',
                  ),
              ],
            ),
          ),
        ),
        if (controller.lastLlmRawContent != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.data_object),
              title: const Text('最近 LLM 原始返回'),
              subtitle: const Text('用于排查超时和无效 JSON'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SelectableText(controller.lastLlmRawContent!),
                ),
              ],
            ),
          ),
        ],
        if (controller.gameState.pendingAction != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.touch_app_outlined),
              title: Text(
                '等待动作 Type ${controller.gameState.pendingAction!.type}',
              ),
              subtitle: Text(
                '玩家 ${controller.gameState.pendingAction!.player} · 可选 ${controller.gameState.pendingAction!.options.length}',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('最近服务器帧', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (controller.messages.isEmpty)
                  const Text('尚未收到服务器帧')
                else
                  ...controller.messages.take(20).map(
                        (message) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'STOC 0x${message.type.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                          ),
                          subtitle: Text(
                            '${message.payload.length} bytes · ${formatPayload(message.payload)}',
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
        if (controller.errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('最近错误'),
              subtitle: Text(controller.errors.first.toString()),
            ),
          ),
        ],
      ],
    );
  }
}

class LocalChatPage extends StatefulWidget {
  const LocalChatPage({super.key, required this.controller});

  final LocalGameController controller;

  @override
  State<LocalChatPage> createState() => _LocalChatPageState();
}

class _LocalChatPageState extends State<LocalChatPage> {
  final _textController = TextEditingController();

  // 释放游戏聊天输入控制器
  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // 发送当前游戏内聊天文本
  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    try {
      await widget.controller.sendChat(text);
      _textController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  // 构建单条带来源和时间的游戏内聊天气泡
  Widget _buildMessage(BuildContext context, MobileGameChatMessage message) {
    final isAgent = message.role == 'agent';
    final roleLabel = switch (message.role) {
      'agent' => message.automatic ? 'AI' : '我',
      'opponent' => '对手',
      'observer' => '观战者',
      _ => '系统',
    };
    final localTime = message.createdAt.toLocal();
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isAgent ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          color: isAgent ? colors.primaryContainer : colors.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$roleLabel  $hour:$minute',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                SelectableText(message.text),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建实时游戏聊天历史和发送输入区
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final messages = widget.controller.chatMessages;
        return Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? const Center(child: Text('尚未收到游戏内聊天'))
                  : ListView.separated(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      itemCount: messages.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 4),
                      itemBuilder: (context, index) => _buildMessage(
                        context,
                        messages[messages.length - 1 - index],
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(hintText: '发送游戏内聊天'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: widget.controller.isBusy ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class LocalDiagnosticLogPage extends StatelessWidget {
  const LocalDiagnosticLogPage({super.key, required this.controller});

  final LocalGameController controller;

  // 调用系统保存面板导出当前近期日志
  Future<void> _export(BuildContext context) async {
    try {
      final result = await controller.exportDiagnosticLogs();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result == null ? '已取消日志导出' : '诊断日志已导出')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('日志导出失败：$error')));
    }
  }

  // 确认后清空设备上的近期日志
  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空诊断日志'),
        content: const Text('此操作会删除设备上保存的近期诊断记录'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.clearDiagnosticLogs();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('诊断日志已清空')));
  }

  // 构建可查看导出和清空的近期日志页面
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('诊断日志')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final entries = controller.diagnosticLogs;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('日志自动保留 7 天，最多 400 条且不超过约 500 KB'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _export(context),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('导出 JSONL'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed:
                              entries.isEmpty ? null : () => _clear(context),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清空'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('暂无诊断日志'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final isError = entry.level == 'error';
                          final isWarning = entry.level == 'warning';
                          return Card(
                            child: ExpansionTile(
                              leading: Icon(
                                isError
                                    ? Icons.error_outline
                                    : isWarning
                                        ? Icons.warning_amber_outlined
                                        : Icons.info_outline,
                                color: isError
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                              title: Text(entry.event),
                              subtitle: Text(
                                '${_formatLogTime(entry.createdAt)} · ${entry.level}',
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: SelectableText(
                                      const JsonEncoder.withIndent(
                                        '  ',
                                      ).convert(entry.data),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LocalDeckLibraryPage extends StatefulWidget {
  // 创建独立于游戏连接的本地卡组库页面
  const LocalDeckLibraryPage({super.key, required this.controller});

  final LocalGameController controller;

  @override
  // 创建本地卡组库页面状态
  State<LocalDeckLibraryPage> createState() => _LocalDeckLibraryPageState();
}

class _LocalDeckLibraryPageState extends State<LocalDeckLibraryPage> {
  // 返回当前卡组库是否允许执行写入操作
  bool get _editable =>
      widget.controller.state != YgoClientState.connected &&
      !widget.controller.isBusy;

  // 从系统文件选择器导入卡组到应用私有仓库
  Future<void> _importDeck() async {
    try {
      final deck = await YdkFileLoader.pickDeck();
      if (deck == null) return;
      final record = await widget.controller.importDeck(deck);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入并选择 ${record.fileName}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卡组导入失败：$error')));
    }
  }

  // 选择指定本地卡组供下一次连接使用
  Future<void> _selectDeck(StoredYdkDeck record) async {
    try {
      await widget.controller.selectStoredDeck(record);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            record.deck.isValid
                ? '已选择 ${record.fileName}'
                : '已选择 ${record.fileName}，请先调整到合法数量再连接',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卡组选择失败：$error')));
    }
  }

  // 打开按单卡编辑页面
  Future<void> _editDeck(StoredYdkDeck record) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LocalDeckEditorPage(controller: widget.controller, record: record),
      ),
    );
  }

  // 二次确认后删除指定本地卡组
  Future<void> _deleteDeck(StoredYdkDeck record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除卡组'),
        content: Text('确定删除 ${record.fileName} 吗'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.deleteStoredDeck(record.fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 ${record.fileName}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卡组删除失败：$error')));
    }
  }

  // 构建独立于游戏连接的本地卡组管理页
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final controller = widget.controller;
        final records = controller.storedDecks;
        return Scaffold(
          appBar: AppBar(
            title: const Text('本地卡组库'),
            actions: [
              IconButton(
                tooltip: '导入 YDK',
                onPressed: _editable ? _importDeck : null,
                icon: const Icon(Icons.file_open_outlined),
              ),
            ],
          ),
          body: records.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('尚未导入卡组\n点击右上角从设备选择 YDK 文件'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: records.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            _editable
                                ? '卡组保存在应用私有目录，可选择、删除并精确调整单卡'
                                : '当前正在连接游戏，卡组只读，断开后可以调整',
                          ),
                        ),
                      );
                    }
                    final record = records[index - 1];
                    final selected =
                        controller.selectedDeckFileName == record.fileName;
                    return Card(
                      child: ListTile(
                        onTap: _editable ? () => _selectDeck(record) : null,
                        leading: Icon(
                          selected ? Icons.check_circle : Icons.style_outlined,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(record.fileName),
                        subtitle: Text(
                          '主 ${record.deck.main.length} · 额外 ${record.deck.extra.length} · 副 ${record.deck.side.length}'
                          '${record.deck.isValid ? '' : ' · 数量不合法'}',
                        ),
                        trailing: Wrap(
                          spacing: 0,
                          children: [
                            IconButton(
                              tooltip: '逐卡编辑',
                              onPressed:
                                  _editable ? () => _editDeck(record) : null,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: '删除',
                              onPressed:
                                  _editable ? () => _deleteDeck(record) : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: _editable
              ? FloatingActionButton.extended(
                  onPressed: _importDeck,
                  icon: const Icon(Icons.add),
                  label: const Text('导入 YDK'),
                )
              : null,
        );
      },
    );
  }
}

class LocalDeckEditorPage extends StatefulWidget {
  // 创建指定本地卡组的逐卡编辑页面
  const LocalDeckEditorPage({
    super.key,
    required this.controller,
    required this.record,
  });

  final LocalGameController controller;
  final StoredYdkDeck record;

  @override
  // 创建逐卡编辑页面状态
  State<LocalDeckEditorPage> createState() => _LocalDeckEditorPageState();
}

class _LocalDeckEditorPageState extends State<LocalDeckEditorPage> {
  late List<int> _main;
  late List<int> _extra;
  late List<int> _side;
  bool _saving = false;

  // 复制原卡组内容作为可撤销的页面草稿
  @override
  void initState() {
    super.initState();
    _main = List<int>.of(widget.record.deck.main);
    _extra = List<int>.of(widget.record.deck.extra);
    _side = List<int>.of(widget.record.deck.side);
  }

  // 返回指定卡组区域对应的可变草稿列表
  List<int> _section(String section) {
    return switch (section) {
      'main' => _main,
      'extra' => _extra,
      'side' => _side,
      _ => throw ArgumentError.value(section, 'section'),
    };
  }

  // 从指定区域删除一张同卡密卡片
  void _removeOne(String section, int code) {
    setState(() => _section(section).remove(code));
  }

  // 从指定区域删除全部同卡密卡片
  void _removeAll(String section, int code) {
    setState(() => _section(section).removeWhere((value) => value == code));
  }

  // 将一张卡从当前区域移动到目标区域
  void _moveOne(String section, String target, int code) {
    setState(() {
      if (_section(section).remove(code)) _section(target).add(code);
    });
  }

  // 打开单卡新增对话框并写入所选区域
  Future<void> _addCard() async {
    var codeText = '';
    var section = 'main';
    final result = await showDialog<({int code, String section})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加单卡'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(labelText: '卡片编号'),
                onChanged: (value) => codeText = value,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: section,
                decoration: const InputDecoration(labelText: '目标区域'),
                items: const [
                  DropdownMenuItem(value: 'main', child: Text('主卡组')),
                  DropdownMenuItem(value: 'extra', child: Text('额外卡组')),
                  DropdownMenuItem(value: 'side', child: Text('副卡组')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => section = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final code = int.tryParse(codeText.trim());
                if (code == null || code <= 0 || code > 0xFFFFFFFF) return;
                Navigator.of(context).pop((code: code, section: section));
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() => _section(result.section).add(result.code));
  }

  // 保存当前三段卡组草稿到应用私有目录
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await widget.controller.saveStoredDeck(
        widget.record.fileName,
        YdkDeck(
          name: widget.record.fileName,
          main: List<int>.unmodifiable(_main),
          extra: List<int>.unmodifiable(_extra),
          side: List<int>.unmodifiable(_side),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved.deck.isValid ? '卡组已保存并可用于连接' : '草稿已保存，但数量不满足对局要求',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卡组保存失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // 处理单卡菜单中的删除和跨区域移动操作
  void _applyCardAction(String action, String section, int code) {
    if (action == 'remove_one') {
      _removeOne(section, code);
      return;
    }
    if (action == 'remove_all') {
      _removeAll(section, code);
      return;
    }
    if (action.startsWith('move_')) {
      _moveOne(section, action.substring(5), code);
    }
  }

  // 构建一个卡组区域内按卡密合并的单卡清单
  Widget _buildSection(String section, String label, List<int> cards) {
    final counts = <int, int>{};
    for (final code in cards) {
      counts[code] = (counts[code] ?? 0) + 1;
    }
    final otherSections = const <String, String>{
      'main': '主卡组',
      'extra': '额外卡组',
      'side': '副卡组',
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text('$label ${cards.length} 张 · ${counts.length} 种'),
          ),
        ),
        if (counts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: Text('当前区域为空')),
          ),
        ...counts.entries.map(
          (entry) => Card(
            child: ListTile(
              title: Text(widget.controller.cardDisplayName(entry.key)),
              subtitle: Text('卡片编号 ${entry.key}'),
              leading: CircleAvatar(child: Text('×${entry.value}')),
              trailing: PopupMenuButton<String>(
                tooltip: '单卡操作',
                onSelected: (action) =>
                    _applyCardAction(action, section, entry.key),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'remove_one', child: Text('删除一张')),
                  const PopupMenuItem(
                    value: 'remove_all',
                    child: Text('删除全部同名卡'),
                  ),
                  ...otherSections.entries
                      .where((item) => item.key != section)
                      .map(
                        (item) => PopupMenuItem(
                          value: 'move_${item.key}',
                          child: Text('移动一张到${item.value}'),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 构建支持主额外副卡组逐卡调整的编辑页面
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.record.fileName),
          bottom: const TabBar(tabs: [Text('主卡组'), Text('额外'), Text('副卡组')]),
          actions: [
            IconButton(
              tooltip: '添加单卡',
              onPressed: _saving ? null : _addCard,
              icon: const Icon(Icons.add_card_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  _buildSection('main', '主卡组', _main),
                  _buildSection('extra', '额外卡组', _extra),
                  _buildSection('side', '副卡组', _side),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? '保存中' : '保存卡组'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LocalSettingsPage extends StatefulWidget {
  const LocalSettingsPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });

  final LocalGameController controller;
  final bool embedded;

  @override
  State<LocalSettingsPage> createState() => _LocalSettingsPageState();
}

class _LocalSettingsPageState extends State<LocalSettingsPage> {
  late String _mode;
  late String _policy;
  late double _coreTemperature;
  late double _threshold;
  late bool _llmEnabled;
  late bool _autonomyEnabled;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _apiKeyController;
  late TextEditingController _timeoutController;
  late TextEditingController _forceTypesController;
  late TextEditingController _timeBudgetController;
  late TextEditingController _autonomyTtlController;
  late TextEditingController _autonomyForceLimitController;
  late double _llmTemperature;
  late bool _llmGameChatEnabled;
  late bool _includeCoreSuggestion;
  late Set<String> _autonomyAllowedModes;
  late double _autonomyConfidenceMin;
  late double _autonomyConfidenceMax;

  // 初始化独立 Agent 设置表单
  @override
  void initState() {
    super.initState();
    final settings = widget.controller.decisionSettings;
    _mode = settings.mode;
    _policy = settings.corePolicyMode;
    _coreTemperature = settings.coreTemperature;
    _threshold = settings.coreConfidenceThreshold;
    _llmEnabled = settings.llmEnabled;
    _autonomyEnabled = settings.autonomyEnabled;
    _baseUrlController = TextEditingController(text: settings.llmBaseUrl);
    _modelController = TextEditingController(text: settings.llmModel);
    _apiKeyController = TextEditingController(
      text: widget.controller.llmApiKey,
    );
    _timeoutController = TextEditingController(
      text: settings.llmTimeout.toString(),
    );
    _forceTypesController = TextEditingController(
      text: settings.forceLlmMessageTypes.join(', '),
    );
    _timeBudgetController = TextEditingController(
      text: settings.llmTimeBudget.toString(),
    );
    _autonomyTtlController = TextEditingController(
      text: settings.autonomyMaxTtlDecisions.toString(),
    );
    _autonomyForceLimitController = TextEditingController(
      text: settings.autonomyMaxForceMessageTypes.toString(),
    );
    _llmTemperature = settings.llmTemperature;
    _llmGameChatEnabled = settings.llmGameChatEnabled;
    _includeCoreSuggestion = settings.includeCoreSuggestion;
    _autonomyAllowedModes = settings.autonomyAllowedModes.toSet();
    _autonomyConfidenceMin = settings.autonomyCoreConfidenceMin;
    _autonomyConfidenceMax = settings.autonomyCoreConfidenceMax;
  }

  // 释放 Agent 设置表单控制器
  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    _timeoutController.dispose();
    _forceTypesController.dispose();
    _timeBudgetController.dispose();
    _autonomyTtlController.dispose();
    _autonomyForceLimitController.dispose();
    super.dispose();
  }

  // 保存独立 Agent 设置而不要求连接游戏
  Future<void> _save() async {
    final timeout = double.tryParse(_timeoutController.text.trim());
    final timeBudget = double.tryParse(_timeBudgetController.text.trim());
    final maximumTtl = int.tryParse(_autonomyTtlController.text.trim());
    final maximumForceTypes = int.tryParse(
      _autonomyForceLimitController.text.trim(),
    );
    final forceTypes = _parseMessageTypes(_forceTypesController.text);
    if (timeout == null ||
        timeout <= 0 ||
        timeBudget == null ||
        timeBudget <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('LLM 超时和对局预算必须是正数')));
      return;
    }
    if (forceTypes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('强制时点请填写 0 到 255 的整数并用逗号分隔')),
      );
      return;
    }
    if (_autonomyAllowedModes.isEmpty ||
        maximumTtl == null ||
        maximumTtl < 1 ||
        maximumForceTypes == null ||
        maximumForceTypes < 0 ||
        _autonomyConfidenceMin > _autonomyConfidenceMax) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请检查自主调整护栏设置')));
      return;
    }
    await widget.controller.saveDecisionSettings(
      MobileDecisionSettings(
        mode: _mode,
        corePolicyMode: _policy,
        coreTemperature: _coreTemperature,
        coreConfidenceThreshold: _threshold,
        llmEnabled: _llmEnabled,
        llmBaseUrl: _baseUrlController.text.trim(),
        llmModel: _modelController.text.trim(),
        llmTemperature: _llmTemperature,
        llmTimeout: timeout,
        llmGameChatEnabled: _llmGameChatEnabled,
        autonomyEnabled: _autonomyEnabled,
        forceLlmMessageTypes: forceTypes,
        includeCoreSuggestion: _includeCoreSuggestion,
        llmTimeBudget: timeBudget,
        autonomyAllowedModes: _autonomyAllowedModes.toList(growable: false),
        autonomyCoreConfidenceMin: _autonomyConfidenceMin,
        autonomyCoreConfidenceMax: _autonomyConfidenceMax,
        autonomyMaxTtlDecisions: maximumTtl,
        autonomyMaxForceMessageTypes: maximumForceTypes,
      ),
      _apiKeyController.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('应用设置已保存')));
  }

  // 解析用户填写的逗号分隔 OCG 消息编号
  static List<int>? _parseMessageTypes(String source) {
    if (source.trim().isEmpty) return const <int>[];
    final result = <int>{};
    for (final part in source.split(RegExp(r'[,，\s]+'))) {
      if (part.isEmpty) continue;
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      result.add(value);
    }
    return result.toList(growable: false);
  }

  // 显示高级决策设置的简短说明
  Future<void> _showHelp(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // 构建带问号说明入口的设置标题
  Widget _helpLabel(String title, String body) {
    return Row(
      children: [
        Expanded(child: Text(title)),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '查看说明',
          onPressed: () => _showHelp(title, body),
          icon: const Icon(Icons.help_outline, size: 19),
        ),
      ],
    );
  }

  // 选择并预检本地 GKG 部署包
  Future<void> _pickModelPackage() async {
    try {
      final preview = await widget.controller.pickModelPackage();
      if (!mounted || preview == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已通过预检：${preview.packageName}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('GKG 预检失败：$error')));
    }
  }

  // 选择并导入本地 YGOPro 卡片数据库
  Future<void> _pickCardDatabase() async {
    try {
      final info = await widget.controller.pickAndInstallCardDatabase();
      if (!mounted || info == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卡片数据库已导入：${info.dataCount} 张')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卡片数据库导入失败：$error')));
    }
  }

  // 安装预检包中选定的 ONNX 模型
  Future<void> _installModel(String primary) async {
    try {
      final installed = await widget.controller.installPreviewModel(primary);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模型已安装：${installed.record.primary}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('模型安装失败：$error')));
    }
  }

  // 加载当前所选 ONNX 模型并显示原生运行时校验结果
  Future<void> _loadSelectedModel() async {
    try {
      final health = await widget.controller.loadSelectedModel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '模型已加载并完成原生推理自检：V${health.modelProtocolVersion} · ${health.inputNames.length} 个输入 · 语义 ${widget.controller.modelSemanticCardCount ?? 0} 张',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('模型加载失败：$error')));
    }
  }

  // 卸载当前原生 ONNX 会话并保留模型文件
  Future<void> _unloadSelectedModel() async {
    await widget.controller.unloadSelectedModel();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('本地模型已卸载')));
  }

  // 构建 GKG 预检安装和本地模型选择区域
  Widget _buildModelCard(BuildContext context) {
    final controller = widget.controller;
    final preview = controller.modelPackagePreview;
    final selected = controller.selectedModel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('本地模型资产', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              selected == null
                  ? '尚未选择本地 ONNX 模型'
                  : '当前：${selected.record.primary} · 协议 V${selected.record.modelProtocolVersion} · 迭代 ${selected.record.iteration}',
            ),
            if (selected != null) ...[
              const SizedBox(height: 6),
              Text(
                controller.isSelectedModelLoaded
                    ? '运行时：已通过 V3 原生推理自检 · ${controller.modelProbe?.elapsed.inMilliseconds ?? 0} ms · 语义 ${controller.modelSemanticCardCount ?? 0} 张'
                    : '运行时：尚未加载，仅完成本地安装',
                style: TextStyle(
                  color: controller.isSelectedModelLoaded
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: controller.isModelBusy
                    ? null
                    : controller.isSelectedModelLoaded
                        ? _unloadSelectedModel
                        : _loadSelectedModel,
                icon: Icon(
                  controller.isSelectedModelLoaded
                      ? Icons.stop_circle_outlined
                      : Icons.memory_outlined,
                ),
                label: Text(
                  controller.isSelectedModelLoaded ? '卸载推理会话' : '加载并运行自检',
                ),
              ),
            ],
            if (controller.installedModels.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('已安装模型'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: controller.installedModels
                    .map(
                      (model) => ChoiceChip(
                        label: Text(
                          '${model.record.modelPrefix} t${model.record.iteration}',
                        ),
                        selected: selected?.primaryPath == model.primaryPath,
                        onSelected: controller.isModelBusy
                            ? null
                            : (_) async {
                                await controller.selectInstalledModel(model);
                              },
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.isModelBusy ? null : _pickModelPackage,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('选择并预检 GKG'),
            ),
            if (controller.isModelBusy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              const Text('正在后台校验或解包大型模型'),
            ],
            if (preview != null) ...[
              const SizedBox(height: 10),
              Text(
                '包：${preview.packageName} · 文件 ${_formatBytes(preview.packageBytes)} · 展开 ${_formatBytes(preview.expandedBytes)}',
              ),
              Text(
                '知识库 ${preview.includesKnowledgeBase ? '有' : '无'} · 语义向量 ${preview.includesCodeSemantics ? '完整' : '无'}',
              ),
              ...preview.onnxModels.map(
                (model) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(model.primary),
                  subtitle: Text(
                    '协议 V${model.modelProtocolVersion} · 迭代 ${model.iteration} · ${model.modelId}',
                  ),
                  trailing: FilledButton(
                    onPressed: controller.isModelBusy
                        ? null
                        : () => _installModel(model.primary),
                    child: const Text('安装'),
                  ),
                ),
              ),
            ],
            if (controller.modelError != null)
              Text(
                controller.modelError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 6),
            const Text(
              '移动端只安装 ONNX 与语义制品，不复制 PTH；首次加载会把知识库编译为紧凑缓存，随后本地推理直接接收可见盘面、己方牌组、连锁和合法动作；大型 GKG 需要预留源包和展开文件两份临时空间',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // 构建独立于模型和游戏连接的卡片资料库区域
  Widget _buildCardDatabaseCard(BuildContext context) {
    final controller = widget.controller;
    final info = controller.cardDatabaseInfo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('卡片资料库', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              info == null
                  ? '尚未导入 cards.cdb，LLM 只能看到卡密和协议公开数值'
                  : '已加载 ${info.dataCount} 张规则数据与 ${info.textCount} 条卡名效果文本',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed:
                  controller.isCardDatabaseBusy ? null : _pickCardDatabase,
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(info == null ? '导入 cards.cdb' : '更新 cards.cdb'),
            ),
            if (controller.isCardDatabaseBusy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (controller.cardDatabaseError != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.cardDatabaseError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              '可使用 MDPro3 或 YGOPro 的标准卡片数据库；文件会复制到应用私有目录并以只读方式使用',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // 构建独立客户端应用设置页面
  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildModelCard(context),
        _buildCardDatabaseCard(context),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Core V3 策略',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _mode,
                  decoration: const InputDecoration(labelText: '介入模式'),
                  items: const [
                    DropdownMenuItem(value: 'core_only', child: Text('仅 Core')),
                    DropdownMenuItem(value: 'hybrid', child: Text('混合')),
                    DropdownMenuItem(
                      value: 'llm_review',
                      child: Text('LLM 复核'),
                    ),
                    DropdownMenuItem(value: 'llm_only', child: Text('仅 LLM')),
                  ],
                  onChanged: (value) => setState(() => _mode = value ?? _mode),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _policy,
                  decoration: const InputDecoration(labelText: 'Core 动作策略'),
                  items: const [
                    DropdownMenuItem(value: 'greedy', child: Text('Greedy')),
                    DropdownMenuItem(
                      value: 'deployment',
                      child: Text('Deployment 温度采样'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _policy = value ?? _policy),
                ),
                Text('Core 温度 ${_coreTemperature.toStringAsFixed(2)}'),
                Slider(
                  value: _coreTemperature,
                  min: 0.05,
                  max: 5,
                  divisions: 99,
                  onChanged: (value) =>
                      setState(() => _coreTemperature = value),
                ),
                _helpLabel(
                  'Core 置信度阈值 ${_threshold.toStringAsFixed(2)}',
                  '混合模式中，Core 最高动作概率低于该值时才调用 LLM。它不是胜率，调高会增加 LLM 调用次数',
                ),
                Slider(
                  value: _threshold,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  onChanged: (value) => setState(() => _threshold = value),
                ),
                _helpLabel(
                  '强制 LLM 时点',
                  '填写 OCG 消息编号，例如 16 表示连锁选择。命中后即使 Core 置信度较高，混合模式也会调用 LLM',
                ),
                TextField(
                  controller: _forceTypesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '例如 16, 23, 26；留空表示不强制',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('向 LLM 提供 Core 建议'),
                  subtitle: const Text('包含候选编号、置信度、局面价值和当前策略'),
                  value: _includeCoreSuggestion,
                  onChanged: (value) =>
                      setState(() => _includeCoreSuggestion = value),
                ),
                _helpLabel(
                  '对局内 LLM 时间预算',
                  '单次决策实际等待时间取 API 请求超时与此预算中的较小值，避免常规接口设置过长拖延对局',
                ),
                TextField(
                  controller: _timeBudgetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(suffixText: '秒'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: _helpLabel(
                    '允许 LLM 自主调整',
                    'LLM 可以随一次正常动作建议临时修改后续介入模式、Core 阈值或强制时点。调整受人工护栏限制，到期自动恢复，不会写回人工设置',
                  ),
                  subtitle: const Text('关闭时仍可由你手动调整上面的全部策略'),
                  value: _autonomyEnabled,
                  onChanged: (value) =>
                      setState(() => _autonomyEnabled = value),
                ),
                if (widget.controller.activeAutonomousOverride != null)
                  Text(
                    '当前临时覆盖还剩 ${widget.controller.activeAutonomousOverride!.remainingDecisions} 次动作',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('自主调整护栏（高级）'),
                  subtitle: const Text('一般保持默认即可'),
                  children: [
                    _helpLabel(
                      '允许临时切换的模式',
                      '只勾选你愿意让 LLM 临时切入的模式。至少保留一种，取消仅 LLM 可避免临时完全绕过 Core',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: const <String, String>{
                        'core_only': '仅 Core',
                        'hybrid': '混合',
                        'llm_review': 'LLM 复核',
                        'llm_only': '仅 LLM',
                      }.entries.map((entry) {
                        return FilterChip(
                          label: Text(entry.value),
                          selected: _autonomyAllowedModes.contains(
                            entry.key,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _autonomyAllowedModes.add(entry.key);
                              } else {
                                _autonomyAllowedModes.remove(entry.key);
                              }
                            });
                          },
                        );
                      }).toList(growable: false),
                    ),
                    _helpLabel(
                      '最低置信度 ${_autonomyConfidenceMin.toStringAsFixed(2)}',
                      'LLM 临时设置的 Core 阈值不得低于此值，避免它让 Core 过度接管',
                    ),
                    Slider(
                      value: _autonomyConfidenceMin,
                      min: 0,
                      max: 1,
                      divisions: 100,
                      onChanged: (value) => setState(() {
                        _autonomyConfidenceMin = value;
                        if (_autonomyConfidenceMax < value) {
                          _autonomyConfidenceMax = value;
                        }
                      }),
                    ),
                    _helpLabel(
                      '最高置信度 ${_autonomyConfidenceMax.toStringAsFixed(2)}',
                      'LLM 临时设置的 Core 阈值不得高于此值，避免几乎每个混合时点都调用 LLM',
                    ),
                    Slider(
                      value: _autonomyConfidenceMax,
                      min: 0,
                      max: 1,
                      divisions: 100,
                      onChanged: (value) => setState(() {
                        _autonomyConfidenceMax = value;
                        if (_autonomyConfidenceMin > value) {
                          _autonomyConfidenceMin = value;
                        }
                      }),
                    ),
                    _helpLabel(
                      '最长持续决策数',
                      '一次自主建议最多影响多少个后续合法动作。每成功提交一次响应减一，不按回合或秒数计算',
                    ),
                    TextField(
                      controller: _autonomyTtlController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(suffixText: '次动作'),
                    ),
                    const SizedBox(height: 8),
                    _helpLabel(
                      '最多强制时点数',
                      '限制一次自主建议能临时加入多少个强制 LLM 的 OCG 消息编号。设为 0 会禁止临时增加强制时点',
                    ),
                    TextField(
                      controller: _autonomyForceLimitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(suffixText: '个'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('LLM API', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用 LLM'),
                  value: _llmEnabled,
                  onChanged: (value) => setState(() => _llmEnabled = value),
                ),
                TextField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(labelText: '模型名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _timeoutController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '请求超时（秒）'),
                ),
                Text('LLM 温度 ${_llmTemperature.toStringAsFixed(2)}'),
                Slider(
                  value: _llmTemperature,
                  min: 0,
                  max: 2,
                  divisions: 40,
                  onChanged: (value) => setState(() => _llmTemperature = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许 LLM 发送游戏内聊天'),
                  subtitle: const Text('仅在 LLM 决策明确返回聊天内容时发送'),
                  value: _llmGameChatEnabled,
                  onChanged: (value) =>
                      setState(() => _llmGameChatEnabled = value),
                ),
              ],
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('保存应用设置'),
        ),
        const SizedBox(height: 10),
        const Text(
          '应用设置独立于游戏连接，断开状态也可以修改。API Key 和房间密码使用系统安全存储',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('应用设置')),
      body: content,
    );
  }
}

class _StateMetric extends StatelessWidget {
  const _StateMetric({required this.label, required this.value});

  final String label;
  final String value;

  // 构建单个对局状态指标
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

// 将日志时间转换为本地短日期时间
String _formatLogTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute:$second';
}

// 将字节数量转换为便于查看的容量文本
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
  final mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';
  return '${(mib / 1024).toStringAsFixed(2)} GiB';
}

// 将 OCG 阶段编号转换为界面名称
String phaseName(int phase) {
  return const <int, String>{
        1: '抽卡',
        2: '准备',
        4: '主要1',
        8: '战斗开始',
        16: '战斗步骤',
        32: '伤害',
        64: '伤害计算',
        128: '战斗',
        256: '主要2',
        512: '结束',
      }[phase] ??
      '未知';
}

// 将服务器帧载荷格式化为短十六进制文本
String formatPayload(List<int> payload) {
  final visible = payload
      .take(24)
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join(' ');
  return payload.length > 24 ? '$visible …' : visible;
}
