// Galatea Link 移动端功能页面，展示决策控制、聊天、观察和事件

import 'package:flutter/material.dart';

import '../controllers/link_controller.dart';
import '../models/link_models.dart';

// 返回功能页面统一内边距
EdgeInsets mobilePagePadding(BuildContext context) {
  return const EdgeInsets.fromLTRB(16, 18, 16, 24);
}

class DecisionPage extends StatefulWidget {
  const DecisionPage({super.key, required this.controller});

  final LinkController controller;

  @override
  State<DecisionPage> createState() => _DecisionPageState();
}

class _DecisionPageState extends State<DecisionPage> {
  late String _mode;
  late String _policy;
  late double _threshold;
  late double _temperature;
  late bool _autonomyEnabled;

  // 初始化决策表单并读取服务当前设置
  @override
  void initState() {
    super.initState();
    _syncFromController();
  }

  // 从最新控制快照同步表单值
  void _syncFromController() {
    final intervention = widget.controller.controls?.baselineIntervention ?? {};
    final autonomy = widget.controller.controls?.autonomy ?? {};
    _mode = intervention['mode'] as String? ?? 'core_only';
    _policy = intervention['core_policy_mode'] as String? ?? 'greedy';
    _threshold =
        (intervention['core_confidence_threshold'] as num?)?.toDouble() ?? 0.65;
    _temperature =
        (intervention['core_temperature'] as num?)?.toDouble() ?? 0.8;
    _autonomyEnabled = autonomy['enabled'] as bool? ?? false;
  }

  // 保存移动端决策表单中的策略设置
  Future<void> _save() async {
    try {
      await widget.controller.updateControls({
        'intervention': {
          'mode': _mode,
          'core_policy_mode': _policy,
          'core_temperature': _temperature,
          'core_confidence_threshold': _threshold,
        },
        'autonomy': {'enabled': _autonomyEnabled},
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('决策策略已更新')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.errorMessage ?? '保存失败')));
      _syncFromController();
      setState(() {});
    }
  }

  // 构建移动端决策控制页面
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: mobilePagePadding(context),
      children: [
        Text('决策策略', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text('这些设置通过 Link 统一控制面生效，修改使用 revision 防止覆盖其他客户端'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _mode,
                  decoration: const InputDecoration(labelText: '运行模式'),
                  items: const [
                    DropdownMenuItem(value: 'core_only', child: Text('仅 Core')),
                    DropdownMenuItem(value: 'hybrid', child: Text('置信度混合')),
                    DropdownMenuItem(
                        value: 'llm_review', child: Text('LLM 全程复核')),
                    DropdownMenuItem(value: 'llm_only', child: Text('仅 LLM')),
                  ],
                  onChanged: (value) => setState(() => _mode = value ?? _mode),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _policy,
                  decoration: const InputDecoration(labelText: 'Core 动作策略'),
                  items: const [
                    DropdownMenuItem(
                        value: 'greedy', child: Text('Greedy 最高分')),
                    DropdownMenuItem(
                        value: 'deployment', child: Text('Deployment 温度采样')),
                  ],
                  onChanged: (value) =>
                      setState(() => _policy = value ?? _policy),
                ),
                const SizedBox(height: 12),
                Text('Core 温度 ${_temperature.toStringAsFixed(2)}'),
                Slider(
                  value: _temperature,
                  min: 0.05,
                  max: 5,
                  divisions: 99,
                  label: _temperature.toStringAsFixed(2),
                  onChanged: (value) => setState(() => _temperature = value),
                ),
                Text('Hybrid 置信度阈值 ${_threshold.toStringAsFixed(2)}'),
                Slider(
                  value: _threshold,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  label: _threshold.toStringAsFixed(2),
                  onChanged: (value) => setState(() => _threshold = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许 LLM 自主调整'),
                  subtitle: const Text('LLM 可在人工护栏内临时调整后续策略'),
                  value: _autonomyEnabled,
                  onChanged: (value) =>
                      setState(() => _autonomyEnabled = value),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                    onPressed: widget.controller.isBusy ? null : _save,
                    icon: const Icon(Icons.save),
                    label: const Text('保存策略')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller});

  final LinkController controller;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _textController = TextEditingController();

  // 释放聊天输入控制器
  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // 发送游戏内聊天并清空输入框
  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    try {
      await widget.controller.sendChat(text);
      _textController.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.controller.errorMessage ?? '发送失败')));
    }
  }

  // 构建游戏内聊天页面
  @override
  Widget build(BuildContext context) {
    final messages =
        widget.controller.chatMessages.reversed.toList(growable: false);
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const Center(child: Text('暂无游戏内聊天'))
              : ListView.builder(
                  padding: mobilePagePadding(context),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      ChatBubble(message: messages[index]),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _textController,
                        enabled: widget.controller.status.running,
                        decoration:
                            const InputDecoration(hintText: '发送到游戏内聊天'))),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: widget.controller.status.running &&
                            !widget.controller.isBusy
                        ? _send
                        : null,
                    icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final LinkChatMessage message;

  // 构建单条聊天消息气泡
  @override
  Widget build(BuildContext context) {
    final outbound = message.direction == 'outbound';
    return Align(
      alignment: outbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        color: outbound ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.role),
                const SizedBox(height: 4),
                Text(message.text)
              ]),
        ),
      ),
    );
  }
}

class ObservationPage extends StatelessWidget {
  const ObservationPage({super.key, required this.controller});

  final LinkController controller;

  // 构建最近一次 LLM 可见观察页面
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: mobilePagePadding(context),
        children: [
          Text('LLM 观察', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text('这里只展示 Link 已过滤后的玩家可见数据'),
          const SizedBox(height: 16),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(14),
              child: SelectableText(formatJsonValue(
                  controller.observation ?? {'message': '尚未收到观察事件'})),
            ),
          ),
        ],
      ),
    );
  }
}

class EventsPage extends StatelessWidget {
  const EventsPage({super.key, required this.controller});

  final LinkController controller;

  // 构建实时事件列表和连接诊断页面
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: mobilePagePadding(context),
      children: [
        Text('事件与诊断', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
            '${controller.events.length} / 300 条事件 · ${controller.connectionState.name}'),
        const SizedBox(height: 12),
        if (controller.errorMessage != null)
          Card(
              child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('最近错误'),
                  subtitle: Text(controller.errorMessage!))),
        ...controller.events.take(100).map(
              (event) => Card(
                child: ExpansionTile(
                  title: Text(event.eventType),
                  subtitle: Text('#${event.sequence}'),
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child:
                                SelectableText(formatJsonValue(event.payload))))
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
