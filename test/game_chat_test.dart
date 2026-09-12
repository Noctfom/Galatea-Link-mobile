// 移动端游戏聊天测试，验证协议编解码、角色识别、回声去重和 LLM 上下文边界

import 'package:flutter_test/flutter_test.dart';

import 'package:galatea_link_mobile/src/game_chat.dart';

// 运行移动端游戏聊天模块的协议和历史测试
void main() {
  // 验证服务端玩家类型与含代理项的 UTF-16LE 文本可以往返
  test('decodes server utf16 chat payload', () {
    final encoded = encodeClientGameChat('你好 🙂');
    final decoded = decodeServerGameChat(<int>[1, 0, ...encoded]);

    expect(decoded.playerType, 1);
    expect(decoded.text, '你好 🙂');
    expect(classifyGameChatRole(1, 0), 'opponent');
    expect(classifyGameChatRole(0, 0), 'agent');
    expect(classifyGameChatRole(7, 0), 'observer');
    expect(classifyGameChatRole(9, 0), 'system');
  });

  // 验证损坏长度、缺失空结尾和孤立代理项都会被拒绝
  test('rejects malformed server chat payloads', () {
    expect(
      () => decodeServerGameChat(const <int>[0, 0, 65]),
      throwsFormatException,
    );
    expect(
      () => decodeServerGameChat(const <int>[0, 0, 65, 0]),
      throwsFormatException,
    );
    expect(
      () => decodeServerGameChat(const <int>[0, 0, 0x00, 0xD8, 0, 0]),
      throwsFormatException,
    );
  });

  // 验证自动聊天按 UTF-16 单元安全截断且不会切断代理项
  test('normalizes and safely truncates outbound chat', () {
    expect(normalizeGameChatText('  你好\n 世界  '), '你好 世界');
    expect(
      normalizeGameChatText('甲🙂乙', maxUtf16Units: 3, truncate: true),
      '甲🙂',
    );
    expect(
      () => normalizeGameChatText('甲🙂乙', maxUtf16Units: 3),
      throwsFormatException,
    );
  });

  // 验证本客户端回声不会重复显示且提示上下文明示不可信社交内容
  test('deduplicates echoes and bounds llm context', () {
    final history = MobileGameChatHistory(
      maxSavedMessages: 3,
      maxSavedCharacters: 8,
    );
    final now = DateTime.utc(2026, 9, 12, 12);
    history.appendOutbound('你好', source: 'mobile.user', createdAt: now);
    final echo = history.appendInbound(
      playerType: 0,
      agentPlayerId: 0,
      text: '你好',
      createdAt: now.add(const Duration(seconds: 1)),
    );
    history.appendInbound(
      playerType: 1,
      agentPlayerId: 0,
      text: '开始吧',
      createdAt: now.add(const Duration(seconds: 2)),
    );

    expect(echo, isNull);
    expect(history.messages.length, 2);
    expect(history.messages.last.role, 'opponent');
    final context = history.toPromptContext(maxMessages: 1)!;
    expect(context['trust'], 'untrusted_social_context');
    expect(context['messages'], hasLength(1));
  });
}
