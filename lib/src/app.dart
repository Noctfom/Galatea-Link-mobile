// Galatea Link 移动端界面，提供连接、概览、决策、聊天、观察和事件页面

import 'package:flutter/material.dart';

import 'controllers/link_controller.dart';
import 'models/link_models.dart';
import 'screens/link_pages.dart';

class GalateaLinkApp extends StatefulWidget {
  const GalateaLinkApp({super.key, required this.controller});

  final LinkController controller;

  @override
  State<GalateaLinkApp> createState() => _GalateaLinkAppState();
}

class _GalateaLinkAppState extends State<GalateaLinkApp> {
  // 初始化本地连接配置
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  // 释放移动端状态控制器
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  // 构建主题随用户偏好切换的应用根节点
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return MaterialApp(
          title: 'Galatea Link',
          debugShowCheckedModeBanner: false,
          themeMode:
              widget.controller.darkTheme ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xff2f6f62)),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff72b5a5),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home:
              widget.controller.connectionState == LinkConnectionState.connected
                  ? LinkHomeScreen(controller: widget.controller)
                  : ConnectionScreen(controller: widget.controller),
        );
      },
    );
  }
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.controller});

  final LinkController controller;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;

  // 初始化连接表单并读取保存的地址
  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.controller.baseUrl);
    _tokenController = TextEditingController(text: widget.controller.token);
  }

  // 释放连接表单控制器
  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  // 提交连接表单并显示失败原因
  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    try {
      await widget.controller.connect(
        url: _urlController.text,
        apiToken: _tokenController.text,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.errorMessage ?? '连接失败')),
      );
    }
  }

  // 构建移动端连接页
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.sports_esports, size: 54),
                      const SizedBox(height: 16),
                      Text('Galatea Link',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      const Text('连接 Link 服务后管理远程游戏王对局'),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Link 服务地址',
                          hintText: 'http://192.168.1.20:8765',
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _tokenController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '访问令牌',
                          hintText: '可留空',
                          prefixIcon: Icon(Icons.key),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: controller.isBusy ? null : _connect,
                        icon: controller.isBusy
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login),
                        label: Text(controller.isBusy ? '连接中' : '连接控制台'),
                      ),
                      if (controller.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Text(controller.errorMessage!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        '令牌只保存在系统安全存储中。移动端不会加载 Core、Torch 或模型文件',
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

class LinkHomeScreen extends StatefulWidget {
  const LinkHomeScreen({super.key, required this.controller});

  final LinkController controller;

  @override
  State<LinkHomeScreen> createState() => _LinkHomeScreenState();
}

class _LinkHomeScreenState extends State<LinkHomeScreen> {
  int _selectedIndex = 0;

  // 返回当前选中的移动端页面
  Widget _page() {
    final pages = <Widget>[
      OverviewPage(controller: widget.controller),
      DecisionPage(controller: widget.controller),
      ChatPage(controller: widget.controller),
      ObservationPage(controller: widget.controller),
      EventsPage(controller: widget.controller),
    ];
    return pages[_selectedIndex];
  }

  // 构建带底部导航的远程控制台
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galatea Link'),
        actions: [
          IconButton(
            tooltip: controller.darkTheme ? '切换浅色主题' : '切换深色主题',
            onPressed: () => controller.setDarkTheme(!controller.darkTheme),
            icon:
                Icon(controller.darkTheme ? Icons.light_mode : Icons.dark_mode),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: controller.isBusy ? null : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'disconnect') controller.disconnect();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'disconnect', child: Text('断开移动端连接')),
            ],
          ),
        ],
      ),
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) =>
            setState(() => _selectedIndex = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: '概览'),
          NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: '决策'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat),
              label: '聊天'),
          NavigationDestination(
              icon: Icon(Icons.visibility_outlined),
              selectedIcon: Icon(Icons.visibility),
              label: '观察'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: '事件'),
        ],
      ),
    );
  }
}

// 构建统一页面内边距
EdgeInsets pagePadding(BuildContext context) {
  return const EdgeInsets.fromLTRB(16, 18, 16, 24);
}

// 返回状态标签颜色
Color statusColor(BuildContext context, bool active) {
  return active
      ? Theme.of(context).colorScheme.primary
      : Theme.of(context).colorScheme.outline;
}

// 读取运行时决策摘要中的嵌套字段
dynamic runtimeField(LinkStatus status, String key) {
  return status.runtime?[key];
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.controller});

  final LinkController controller;

  // 构建对局概览和启动停止操作
  @override
  Widget build(BuildContext context) {
    final runtime = controller.status.runtime;
    final runtimeMap = runtime ?? <String, dynamic>{};
    final decision = runtimeMap['decision'] as Map?;
    final model = runtimeMap['core_model'] as Map?;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: pagePadding(context),
        children: [
          Text('运行概览', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(controller.connectionState.name,
              style: TextStyle(
                  color: statusColor(
                      context,
                      controller.connectionState ==
                          LinkConnectionState.connected))),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SummaryCard(
                  label: '会话',
                  value: controller.status.running ? '运行中' : '已停止'),
              SummaryCard(
                  label: '游戏连接',
                  value: runtime?['connected'] == true ? '已连接' : '未连接'),
              SummaryCard(
                  label: '对局',
                  value: runtime?['duel_active'] == true ? '进行中' : '未开始'),
              SummaryCard(
                  label: 'Core',
                  value: model?['available'] == true ? '可用' : '不可用'),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('会话控制', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                      '第 ${controller.status.generation} 代 · 最近事件 ${controller.status.lastEventType ?? '无'}'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: FilledButton.icon(
                              onPressed:
                                  controller.status.running || controller.isBusy
                                      ? null
                                      : controller.startSession,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('启动 Link'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: !controller.status.running ||
                                      controller.isBusy
                                  ? null
                                  : controller.stopSession,
                              icon: const Icon(Icons.stop),
                              label: const Text('停止会话'))),
                    ],
                  ),
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(controller.errorMessage!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('最近决策'),
              subtitle: Text(
                  '来源 ${decision?['last_source'] ?? '无'} · 选择 ${decision?['last_choice_id'] ?? '无'}'),
              trailing:
                  Text('阈值 ${decision?['core_confidence_threshold'] ?? '-'}'),
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  // 构建概览统计卡片
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge)
          ]),
        ),
      ),
    );
  }
}
