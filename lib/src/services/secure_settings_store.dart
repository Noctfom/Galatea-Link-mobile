// Galatea Link 移动端安全设置存储，只保存地址和令牌等客户端配置

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game_connection_settings.dart';
import '../app_decision_settings.dart';

class SecureSettingsStore {
  SecureSettingsStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _baseUrlKey = 'galatea_link_base_url';
  static const _tokenKey = 'galatea_link_api_token';
  static const _themeKey = 'galatea_link_theme';
  static const _gameHostKey = 'galatea_game_host';
  static const _gamePortKey = 'galatea_game_port';
  static const _gamePasswordKey = 'galatea_game_password';
  static const _playerNameKey = 'galatea_player_name';
  static const _gameIdKey = 'galatea_game_id';
  static const _protocolVersionKey = 'galatea_protocol_version';
  static const _preferSecondKey = 'galatea_prefer_second';
  static const _decisionModeKey = 'galatea_decision_mode';
  static const _corePolicyKey = 'galatea_core_policy';
  static const _coreTemperatureKey = 'galatea_core_temperature';
  static const _coreThresholdKey = 'galatea_core_threshold';
  static const _llmEnabledKey = 'galatea_llm_enabled';
  static const _llmBaseUrlKey = 'galatea_llm_base_url';
  static const _llmModelKey = 'galatea_llm_model';
  static const _llmTemperatureKey = 'galatea_llm_temperature';
  static const _llmTimeoutKey = 'galatea_llm_timeout';
  static const _llmGameChatEnabledKey = 'galatea_llm_game_chat_enabled';
  static const _autonomyEnabledKey = 'galatea_autonomy_enabled';
  static const _forceLlmTypesKey = 'galatea_force_llm_types';
  static const _includeCoreSuggestionKey = 'galatea_include_core_suggestion';
  static const _llmTimeBudgetKey = 'galatea_llm_time_budget';
  static const _autonomyAllowedModesKey = 'galatea_autonomy_allowed_modes';
  static const _autonomyConfidenceMinKey = 'galatea_autonomy_confidence_min';
  static const _autonomyConfidenceMaxKey = 'galatea_autonomy_confidence_max';
  static const _autonomyMaxTtlKey = 'galatea_autonomy_max_ttl';
  static const _autonomyMaxForceTypesKey = 'galatea_autonomy_max_force_types';
  static const _llmApiKeyKey = 'galatea_llm_api_key';
  static const _selectedModelPathKey = 'galatea_selected_model_path';
  static const _selectedDeckFileKey = 'galatea_selected_deck_file';
  static const _connectionProfilesKey = 'galatea_connection_profiles';
  static const _connectionProfilePasswordPrefix =
      'galatea_connection_profile_password_';
  final FlutterSecureStorage _secureStorage;

  // 读取上一次使用的 Link 地址
  Future<String?> readBaseUrl() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_baseUrlKey);
  }

  // 保存 Link 地址到普通本地偏好
  Future<void> writeBaseUrl(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_baseUrlKey, value);
  }

  // 读取系统安全存储中的访问令牌
  Future<String?> readToken() {
    return _secureStorage.read(key: _tokenKey);
  }

  // 保存访问令牌到系统安全存储
  Future<void> writeToken(String value) {
    return _secureStorage.write(key: _tokenKey, value: value);
  }

  // 清除移动端保存的访问令牌
  Future<void> clearToken() {
    return _secureStorage.delete(key: _tokenKey);
  }

  // 读取用户选择的界面主题
  Future<bool?> readDarkTheme() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_themeKey);
  }

  // 保存用户选择的界面主题
  Future<void> writeDarkTheme(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_themeKey, value);
  }

  // 读取上一次使用的 MDPro3 游戏连接设置
  Future<GameConnectionSettings> readGameConnectionSettings() async {
    final preferences = await SharedPreferences.getInstance();
    return GameConnectionSettings(
      host: preferences.getString(_gameHostKey) ?? '',
      port: preferences.getInt(_gamePortKey) ?? 7911,
      password: await _secureStorage.read(key: _gamePasswordKey) ?? '',
      playerName: preferences.getString(_playerNameKey) ?? 'Galatea_AI',
      gameId: preferences.getInt(_gameIdKey) ?? 0,
      protocolVersion: preferences.getInt(_protocolVersionKey) ?? 0x1361,
      preferSecond: preferences.getBool(_preferSecondKey) ?? false,
    );
  }

  // 保存 MDPro3 游戏连接设置并将密码写入安全存储
  Future<void> writeGameConnectionSettings(
    GameConnectionSettings settings,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_gameHostKey, settings.host);
    await preferences.setInt(_gamePortKey, settings.port);
    await preferences.setString(_playerNameKey, settings.playerName);
    await preferences.setInt(_gameIdKey, settings.gameId);
    await preferences.setInt(_protocolVersionKey, settings.protocolVersion);
    await preferences.setBool(_preferSecondKey, settings.preferSecond);
    if (settings.password.isEmpty) {
      await _secureStorage.delete(key: _gamePasswordKey);
    } else {
      await _secureStorage.write(
        key: _gamePasswordKey,
        value: settings.password,
      );
    }
  }

  // 读取用户保存的游戏连接快捷配置
  Future<List<GameConnectionProfile>> readGameConnectionProfiles() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_connectionProfilesKey);
    if (encoded == null || encoded.isEmpty) {
      return const <GameConnectionProfile>[];
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const <GameConnectionProfile>[];
      final profiles = <GameConnectionProfile>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final json = Map<String, dynamic>.from(raw);
        final id = json['id'];
        final name = json['name'];
        final rawSettings = json['settings'];
        if (id is! String ||
            id.isEmpty ||
            name is! String ||
            name.isEmpty ||
            rawSettings is! Map) {
          continue;
        }
        final password = await _secureStorage.read(
              key: '$_connectionProfilePasswordPrefix$id',
            ) ??
            '';
        profiles.add(
          GameConnectionProfile(
            id: id,
            name: name,
            settings: GameConnectionSettings.fromProfileJson(
              Map<String, dynamic>.from(rawSettings),
              password: password,
            ),
          ),
        );
      }
      return List<GameConnectionProfile>.unmodifiable(profiles);
    } catch (_) {
      return const <GameConnectionProfile>[];
    }
  }

  // 保存用户连接快捷配置并将各配置密码写入安全存储
  Future<void> writeGameConnectionProfiles(
    List<GameConnectionProfile> profiles,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final existing = await readGameConnectionProfiles();
    final retainedIds = profiles.map((profile) => profile.id).toSet();
    for (final removed in existing.where(
      (profile) => !retainedIds.contains(profile.id),
    )) {
      await _secureStorage.delete(
        key: '$_connectionProfilePasswordPrefix${removed.id}',
      );
    }
    for (final profile in profiles) {
      final passwordKey = '$_connectionProfilePasswordPrefix${profile.id}';
      if (profile.settings.password.isEmpty) {
        await _secureStorage.delete(key: passwordKey);
      } else {
        await _secureStorage.write(
          key: passwordKey,
          value: profile.settings.password,
        );
      }
    }
    await preferences.setString(
      _connectionProfilesKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );
  }

  // 读取独立于连接状态的 Agent 设置
  Future<MobileDecisionSettings> readDecisionSettings() async {
    final preferences = await SharedPreferences.getInstance();
    return MobileDecisionSettings(
      mode: preferences.getString(_decisionModeKey) ?? 'core_only',
      corePolicyMode: preferences.getString(_corePolicyKey) ?? 'greedy',
      coreTemperature: preferences.getDouble(_coreTemperatureKey) ?? 0.8,
      coreConfidenceThreshold: preferences.getDouble(_coreThresholdKey) ?? 0.65,
      llmEnabled: preferences.getBool(_llmEnabledKey) ?? false,
      llmBaseUrl:
          preferences.getString(_llmBaseUrlKey) ?? 'https://api.openai.com/v1',
      llmModel: preferences.getString(_llmModelKey) ?? '',
      llmTemperature: preferences.getDouble(_llmTemperatureKey) ?? 0.1,
      llmTimeout: preferences.getDouble(_llmTimeoutKey) ?? 30,
      llmGameChatEnabled: preferences.getBool(_llmGameChatEnabledKey) ?? false,
      autonomyEnabled: preferences.getBool(_autonomyEnabledKey) ?? false,
      forceLlmMessageTypes: _readIntegerList(preferences, _forceLlmTypesKey),
      includeCoreSuggestion:
          preferences.getBool(_includeCoreSuggestionKey) ?? true,
      llmTimeBudget: preferences.getDouble(_llmTimeBudgetKey) ?? 12,
      autonomyAllowedModes:
          preferences.getStringList(_autonomyAllowedModesKey) ??
              const <String>['core_only', 'hybrid', 'llm_review', 'llm_only'],
      autonomyCoreConfidenceMin:
          preferences.getDouble(_autonomyConfidenceMinKey) ?? 0.2,
      autonomyCoreConfidenceMax:
          preferences.getDouble(_autonomyConfidenceMaxKey) ?? 0.9,
      autonomyMaxTtlDecisions: preferences.getInt(_autonomyMaxTtlKey) ?? 3,
      autonomyMaxForceMessageTypes:
          preferences.getInt(_autonomyMaxForceTypesKey) ?? 8,
    );
  }

  // 保存独立于连接状态的 Agent 设置和 LLM 密钥
  Future<void> writeDecisionSettings(
    MobileDecisionSettings settings, {
    required String llmApiKey,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_decisionModeKey, settings.mode);
    await preferences.setString(_corePolicyKey, settings.corePolicyMode);
    await preferences.setDouble(_coreTemperatureKey, settings.coreTemperature);
    await preferences.setDouble(
      _coreThresholdKey,
      settings.coreConfidenceThreshold,
    );
    await preferences.setBool(_llmEnabledKey, settings.llmEnabled);
    await preferences.setString(_llmBaseUrlKey, settings.llmBaseUrl);
    await preferences.setString(_llmModelKey, settings.llmModel);
    await preferences.setDouble(_llmTemperatureKey, settings.llmTemperature);
    await preferences.setDouble(_llmTimeoutKey, settings.llmTimeout);
    await preferences.setBool(
      _llmGameChatEnabledKey,
      settings.llmGameChatEnabled,
    );
    await preferences.setBool(_autonomyEnabledKey, settings.autonomyEnabled);
    await preferences.setStringList(
      _forceLlmTypesKey,
      settings.forceLlmMessageTypes.map((value) => value.toString()).toList(),
    );
    await preferences.setBool(
      _includeCoreSuggestionKey,
      settings.includeCoreSuggestion,
    );
    await preferences.setDouble(_llmTimeBudgetKey, settings.llmTimeBudget);
    await preferences.setStringList(
      _autonomyAllowedModesKey,
      settings.autonomyAllowedModes,
    );
    await preferences.setDouble(
      _autonomyConfidenceMinKey,
      settings.autonomyCoreConfidenceMin,
    );
    await preferences.setDouble(
      _autonomyConfidenceMaxKey,
      settings.autonomyCoreConfidenceMax,
    );
    await preferences.setInt(
      _autonomyMaxTtlKey,
      settings.autonomyMaxTtlDecisions,
    );
    await preferences.setInt(
      _autonomyMaxForceTypesKey,
      settings.autonomyMaxForceMessageTypes,
    );
    await _secureStorage.write(key: _llmApiKeyKey, value: llmApiKey);
  }

  // 读取系统安全存储中的 LLM API Key
  Future<String> readLlmApiKey() async {
    return await _secureStorage.read(key: _llmApiKeyKey) ?? '';
  }

  // 读取上一次选择的本地 ONNX 主图路径
  Future<String?> readSelectedModelPath() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_selectedModelPathKey);
  }

  // 保存当前选择的本地 ONNX 主图路径
  Future<void> writeSelectedModelPath(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectedModelPathKey, value);
  }

  // 读取上一次选择的本地卡组文件名
  Future<String?> readSelectedDeckFileName() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_selectedDeckFileKey);
  }

  // 保存或清除当前选择的本地卡组文件名
  Future<void> writeSelectedDeckFileName(String? value) async {
    final preferences = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await preferences.remove(_selectedDeckFileKey);
    } else {
      await preferences.setString(_selectedDeckFileKey, value);
    }
  }

  // 从字符串列表恢复去重后的 OCG 消息编号
  static List<int> _readIntegerList(SharedPreferences preferences, String key) {
    return (preferences.getStringList(key) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where((value) => value >= 0 && value <= 255)
        .toSet()
        .toList(growable: false);
  }
}
