// Galatea Link mobile 连接配置测试，验证快捷配置不会明文序列化密码

import 'package:flutter_test/flutter_test.dart';
import 'package:galatea_link_mobile/src/game_connection_settings.dart';

// 运行连接快捷配置序列化与空密码恢复测试
void main() {
  test('profile json excludes password and restores explicit empty value', () {
    const settings = GameConnectionSettings(
      host: '127.0.0.1',
      port: 7911,
      password: 'secret',
      playerName: 'Galatea_AI',
      gameId: 0,
      protocolVersion: 0x1361,
      preferSecond: false,
    );

    final json = settings.toProfileJson();
    final restored = GameConnectionSettings.fromProfileJson(
      Map<String, dynamic>.from(json),
      password: '',
    );

    expect(json.containsKey('password'), isFalse);
    expect(restored.host, '127.0.0.1');
    expect(restored.port, 7911);
    expect(restored.password, isEmpty);
  });

  test('local YGOMobile preset uses phone bridge and clears password', () {
    const settings = GameConnectionSettings(
      host: 's1.ygo233.com',
      port: 233,
      password: 'old-password',
      playerName: 'Galatea_AI',
      gameId: 42,
      protocolVersion: 0x1361,
      preferSecond: true,
    );

    final local = settings.asLocalYgoMobile();

    expect(local.host, '172.19.0.1');
    expect(local.port, 7911);
    expect(local.gameId, 0);
    expect(local.password, isEmpty);
    expect(local.isLocalYgoMobile, isTrue);
    expect(local.playerName, settings.playerName);
    expect(local.protocolVersion, settings.protocolVersion);
    expect(local.preferSecond, isTrue);
  });

  test('local YGOMobile endpoint recognition ignores surrounding spaces', () {
    const settings = GameConnectionSettings(
      host: ' 172.19.0.1 ',
      port: 7911,
      password: '',
      playerName: 'Galatea_AI',
      gameId: 0,
      protocolVersion: 0x1361,
      preferSecond: false,
    );

    expect(settings.isLocalYgoMobile, isTrue);
  });
}
