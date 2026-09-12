// 移动端 MDPro3 连接设置模型，保存服务器登录和先后攻偏好

class GameConnectionSettings {
  const GameConnectionSettings({
    required this.host,
    required this.port,
    required this.password,
    required this.playerName,
    required this.gameId,
    required this.protocolVersion,
    required this.preferSecond,
  });

  final String host;
  final int port;
  final String password;
  final String playerName;
  final int gameId;
  final int protocolVersion;
  final bool preferSecond;

  // 返回默认移动端游戏连接设置
  factory GameConnectionSettings.defaults() {
    return const GameConnectionSettings(
      host: '',
      port: 7911,
      password: '',
      playerName: 'Galatea_AI',
      gameId: 0,
      protocolVersion: 0x1361,
      preferSecond: false,
    );
  }
}
