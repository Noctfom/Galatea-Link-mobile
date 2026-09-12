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

  // 创建只替换指定连接字段的新配置
  GameConnectionSettings copyWith({
    String? host,
    int? port,
    String? password,
    String? playerName,
    int? gameId,
    int? protocolVersion,
    bool? preferSecond,
  }) {
    return GameConnectionSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      playerName: playerName ?? this.playerName,
      gameId: gameId ?? this.gameId,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      preferSecond: preferSecond ?? this.preferSecond,
    );
  }

  // 转换为不包含密码的本地配置数据
  Map<String, Object?> toProfileJson() {
    return <String, Object?>{
      'host': host,
      'port': port,
      'player_name': playerName,
      'game_id': gameId,
      'protocol_version': protocolVersion,
      'prefer_second': preferSecond,
    };
  }

  // 从本地配置数据恢复游戏连接字段
  factory GameConnectionSettings.fromProfileJson(
    Map<String, dynamic> json, {
    String password = '',
  }) {
    return GameConnectionSettings(
      host: json['host'] is String ? json['host'] as String : '',
      port: json['port'] is int ? json['port'] as int : 7911,
      password: password,
      playerName: json['player_name'] is String
          ? json['player_name'] as String
          : 'Galatea_AI',
      gameId: json['game_id'] is int ? json['game_id'] as int : 0,
      protocolVersion: json['protocol_version'] is int
          ? json['protocol_version'] as int
          : 0x1361,
      preferSecond:
          json['prefer_second'] is bool ? json['prefer_second'] as bool : false,
    );
  }

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

// 保存一份命名的游戏服务器快捷连接配置
class GameConnectionProfile {
  // 创建包含安全存储密码引用的连接配置
  const GameConnectionProfile({
    required this.id,
    required this.name,
    required this.settings,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final GameConnectionSettings settings;
  final bool isBuiltIn;

  // 转换为不包含密码的配置索引数据
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'settings': settings.toProfileJson(),
    };
  }
}
