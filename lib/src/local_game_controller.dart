// Galatea Link 移动端本地对局控制器，直接管理 YGOPro 连接和可见服务器帧

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import 'deck/ydk_deck.dart';
import 'deck/deck_library_service.dart';
import 'app_decision_settings.dart';
import 'cards/card_database_service.dart';
import 'decision/mobile_decision_engine.dart';
import 'decision/decision_catalog.dart';
import 'decision/autonomous_intervention.dart';
import 'game_chat.dart';
import 'game_state.dart';
import 'game_protocol/byte_cursor.dart';
import 'game_protocol/ocg_parser.dart';
import 'game_protocol/ygo_client.dart';
import 'game_protocol/ygo_constants.dart';
import 'game_protocol/ygo_payloads.dart';
import 'game_connection_settings.dart';
import 'models/model_package_service.dart';
import 'models/onnx_runtime_service.dart';
import 'services/secure_settings_store.dart';
import 'services/diagnostic_log_store.dart';

class LocalGameController extends ChangeNotifier {
  // 创建共享同一 ONNX 会话的本地游戏与决策控制器
  LocalGameController({required SecureSettingsStore store}) : _store = store {
    _decisionEngine = MobileDecisionEngine(
      onnxRuntimeService: _onnxRuntimeService,
      cardDatabase: _cardDatabaseService,
    );
  }

  final SecureSettingsStore _store;
  final DiagnosticLogStore _diagnosticLogStore = DiagnosticLogStore();
  final DeckLibraryService _deckLibraryService = DeckLibraryService();
  final ModelPackageService _modelPackageService = ModelPackageService();
  final OnnxRuntimeService _onnxRuntimeService = OnnxRuntimeService();
  final CardDatabaseService _cardDatabaseService = CardDatabaseService();
  final MobileGameChatHistory _gameChatHistory = MobileGameChatHistory();
  final MobileInterventionRuntime _interventionRuntime =
      MobileInterventionRuntime();
  GameConnectionSettings settings = GameConnectionSettings.defaults();
  YgoClientState state = YgoClientState.disconnected;
  List<YgoServerMessage> messages = const <YgoServerMessage>[];
  List<Object> errors = const <Object>[];
  String? errorMessage;
  bool isBusy = false;
  bool darkTheme = false;
  bool initialized = false;
  YdkDeck? deck;
  List<StoredYdkDeck> storedDecks = const <StoredYdkDeck>[];
  String? selectedDeckFileName;
  String roomPhase = 'disconnected';
  int? assignedPlayer;
  int roomDuelMode = 0;
  bool isRoomHost = false;
  Map<int, bool> roomReady = <int, bool>{
    0: false,
    1: false,
    2: false,
    3: false,
  };
  int? timePlayer;
  int? timeLeft;
  final MobileGameState gameState = MobileGameState();
  MobileDecisionSettings decisionSettings = MobileDecisionSettings.defaults();
  String llmApiKey = '';
  String? lastDecisionSource;
  String? lastDecisionDescription;
  String? lastLlmRawContent;
  Duration? lastDecisionElapsed;
  int? lastPromptTokens;
  int? lastCompletionTokens;
  int? lastCachedTokens;
  double? lastCoreConfidence;
  double? lastCoreValue;
  List<int>? lastResponsePayload;
  int retryCount = 0;
  int protocolVersionRetryCount = 0;
  int? negotiatedProtocolVersion;
  bool isDeciding = false;
  bool isModelBusy = false;
  String? modelError;
  GkgPackagePreview? modelPackagePreview;
  List<InstalledOnnxModel> installedModels = const <InstalledOnnxModel>[];
  InstalledOnnxModel? selectedModel;
  CardDatabaseInfo? cardDatabaseInfo;
  bool isCardDatabaseBusy = false;
  String? cardDatabaseError;
  late final MobileDecisionEngine _decisionEngine;
  YgoTcpClient? _client;
  StreamSubscription<YgoServerMessage>? _messageSubscription;
  StreamSubscription<Object>? _errorSubscription;
  StreamSubscription<void>? _closedSubscription;
  int _connectionGeneration = 0;
  int _decisionGeneration = 0;
  int _responseSequence = 0;
  DateTime? _lastResponseAt;
  int? _lastResponseActionType;
  Timer? _responseWatchdog;
  String? _lastSentResponseKey;
  final Set<String> _rejectedResponseKeys = <String>{};
  DateTime? _lastAutomaticChatAt;
  String? _lastAutomaticChatText;
  final Set<int> _attemptedProtocolVersions = <int>{};
  bool _protocolRetryInProgress = false;
  int? _readySeat;
  bool _startRequested = false;
  Future<void> _deckUpload = Future<void>.value();

  // 返回从新到旧排列的近期脱敏诊断日志
  List<DiagnosticLogEntry> get diagnosticLogs => _diagnosticLogStore.recent;

  // 返回按时间正序排列的当前对局聊天记录
  List<MobileGameChatMessage> get chatMessages => _gameChatHistory.messages;

  // 返回当前通过原生运行时校验的模型健康信息
  OnnxModelHealth? get modelHealth => _onnxRuntimeService.health;

  // 返回当前模型最近一次原生推理自检结果
  OnnxInferenceProbe? get modelProbe => _onnxRuntimeService.probe;

  // 返回当前模型语义缓存包含的卡片记录数量
  int? get modelSemanticCardCount =>
      _onnxRuntimeService.semanticStore?.recordCount;

  // 返回当前模型紧凑语义缓存的内存字节数
  int? get modelSemanticCacheBytes =>
      _onnxRuntimeService.semanticStore?.byteLength;

  // 返回当前实际生效的决策设置
  MobileDecisionSettings get effectiveDecisionSettings =>
      _interventionRuntime.effective;

  // 返回当前 LLM 临时覆盖状态
  MobileAutonomousOverride? get activeAutonomousOverride =>
      _interventionRuntime.activeOverride;

  // 返回当前所选模型是否已经载入原生推理会话
  bool get isSelectedModelLoaded =>
      _onnxRuntimeService.isLoaded &&
      _onnxRuntimeService.loadedModel?.primaryPath ==
          selectedModel?.primaryPath;

  // 恢复本地游戏连接设置和主题偏好
  Future<void> initialize() async {
    await _diagnosticLogStore.initialize();
    settings = await _store.readGameConnectionSettings();
    storedDecks = await _deckLibraryService.listDecks();
    selectedDeckFileName = await _store.readSelectedDeckFileName();
    final selectedDeckRecord = storedDecks
        .where((record) => record.fileName == selectedDeckFileName)
        .firstOrNull;
    final initialDeck = selectedDeckRecord ??
        storedDecks.where((record) => record.deck.isValid).firstOrNull;
    if (initialDeck != null) {
      selectedDeckFileName = initialDeck.fileName;
      deck = initialDeck.deck;
      await _store.writeSelectedDeckFileName(initialDeck.fileName);
    }
    decisionSettings = await _store.readDecisionSettings();
    _interventionRuntime.setBaseline(decisionSettings);
    llmApiKey = await _store.readLlmApiKey();
    cardDatabaseInfo = await _cardDatabaseService.initialize();
    installedModels = await _modelPackageService.listInstalled();
    final selectedModelPath = await _store.readSelectedModelPath();
    selectedModel = installedModels
        .where((model) => model.primaryPath == selectedModelPath)
        .firstOrNull;
    selectedModel ??= installedModels.firstOrNull;
    final initialModel = selectedModel;
    if (initialModel != null) {
      await _onnxRuntimeService.prepareModelAssets(initialModel);
    }
    darkTheme = await _store.readDarkTheme() ?? false;
    initialized = true;
    _recordLog(
      'app.initialized',
      data: <String, Object?>{
        'decision_mode': decisionSettings.mode,
        'llm_enabled': decisionSettings.llmEnabled,
        'card_database_count': cardDatabaseInfo?.dataCount,
      },
    );
    notifyListeners();
  }

  // 通过系统文件选择器导出近期脱敏 JSONL 日志
  Future<String?> exportDiagnosticLogs() async {
    final content = await _diagnosticLogStore.exportJsonLines();
    return FilePicker.platform.saveFile(
      dialogTitle: '导出 Galatea Mobile 诊断日志',
      fileName: _diagnosticLogStore.exportFileName(),
      type: FileType.any,
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
  }

  // 清空设备上保存的全部近期诊断日志
  Future<void> clearDiagnosticLogs() async {
    await _diagnosticLogStore.clear();
    notifyListeners();
  }

  // 打开文件选择器并导入标准 YGOPro cards.cdb
  Future<CardDatabaseInfo?> pickAndInstallCardDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    if (selected.path == null ||
        !selected.name.toLowerCase().endsWith('.cdb')) {
      throw const FormatException('请选择可读取的 cards.cdb 文件');
    }
    isCardDatabaseBusy = true;
    cardDatabaseError = null;
    notifyListeners();
    try {
      final installed = await _cardDatabaseService.installFrom(selected.path!);
      cardDatabaseInfo = installed;
      _recordLog(
        'cards.database.installed',
        data: <String, Object?>{
          'data_count': installed.dataCount,
          'text_count': installed.textCount,
        },
      );
      return installed;
    } catch (error) {
      cardDatabaseError = error.toString();
      _recordLog(
        'cards.database.install_failed',
        level: 'error',
        data: <String, Object?>{'error': error.toString()},
      );
      rethrow;
    } finally {
      isCardDatabaseBusy = false;
      notifyListeners();
    }
  }

  // 打开系统文件选择器并在后台预检 GKG V2 部署包
  Future<GkgPackagePreview?> pickModelPackage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    if (!selected.name.toLowerCase().endsWith('.gkg') ||
        selected.path == null) {
      throw const FormatException('请选择可读取的 .gkg 部署包');
    }
    isModelBusy = true;
    modelError = null;
    notifyListeners();
    try {
      final preview = await _modelPackageService.inspect(selected.path!);
      modelPackagePreview = preview;
      _recordLog(
        'model.package.inspected',
        data: <String, Object?>{
          'package_name': preview.packageName,
          'package_bytes': preview.packageBytes,
          'expanded_bytes': preview.expandedBytes,
          'onnx_models':
              preview.onnxModels.map((item) => item.primary).toList(),
        },
      );
      return preview;
    } catch (error) {
      modelError = error.toString();
      _recordLog(
        'model.package.rejected',
        level: 'error',
        data: <String, Object?>{
          'file_name': selected.name,
          'error': error.toString(),
        },
      );
      rethrow;
    } finally {
      isModelBusy = false;
      notifyListeners();
    }
  }

  // 将预检包中的指定 ONNX 和语义资产安装到应用私有目录
  Future<InstalledOnnxModel> installPreviewModel(String primary) async {
    final preview = modelPackagePreview;
    if (preview == null) throw StateError('请先选择并预检 GKG 包');
    isModelBusy = true;
    modelError = null;
    notifyListeners();
    try {
      final installed = await _modelPackageService.installOnnx(
        preview,
        primary,
      );
      installedModels = await _modelPackageService.listInstalled();
      selectedModel = installedModels
          .where((model) => model.primaryPath == installed.primaryPath)
          .firstOrNull;
      selectedModel ??= installed;
      await _onnxRuntimeService.close();
      await _onnxRuntimeService.prepareModelAssets(installed);
      await _store.writeSelectedModelPath(installed.primaryPath);
      _recordLog(
        'model.onnx.installed',
        data: <String, Object?>{
          'primary': installed.record.primary,
          'model_id': installed.record.modelId,
          'iteration': installed.record.iteration,
          'model_protocol_version': installed.record.modelProtocolVersion,
        },
      );
      return installed;
    } catch (error) {
      modelError = error.toString();
      _recordLog(
        'model.onnx.install_failed',
        level: 'error',
        data: <String, Object?>{'primary': primary, 'error': error.toString()},
      );
      rethrow;
    } finally {
      isModelBusy = false;
      notifyListeners();
    }
  }

  // 选择已经安装且协议兼容的本地 ONNX 模型
  Future<void> selectInstalledModel(InstalledOnnxModel model) async {
    if (!installedModels.any((item) => item.primaryPath == model.primaryPath)) {
      throw const FormatException('选定模型不在已安装模型列表中');
    }
    if (selectedModel?.primaryPath != model.primaryPath) {
      await _onnxRuntimeService.close();
      selectedModel = model;
    }
    await _onnxRuntimeService.prepareModelAssets(model);
    await _store.writeSelectedModelPath(model.primaryPath);
    _recordLog(
      'model.selected',
      data: <String, Object?>{
        'primary': model.record.primary,
        'model_id': model.record.modelId,
        'iteration': model.record.iteration,
      },
    );
    notifyListeners();
  }

  // 将当前所选 ONNX 模型载入原生 CPU 推理会话并核验 V3 张量签名
  Future<OnnxModelHealth> loadSelectedModel() async {
    final model = selectedModel;
    if (model == null) throw StateError('请先安装并选择本地 ONNX 模型');
    isModelBusy = true;
    modelError = null;
    notifyListeners();
    try {
      final health = await _onnxRuntimeService.load(model);
      final probe = await _onnxRuntimeService.runCompatibilityProbe();
      _recordLog(
        'model.onnx.loaded',
        data: <String, Object?>{
          'primary': model.record.primary,
          'model_id': health.modelId,
          'iteration': health.iteration,
          'model_protocol_version': health.modelProtocolVersion,
          'input_count': health.inputNames.length,
          'output_names': health.outputNames,
          'probe_elapsed_ms': probe.elapsed.inMilliseconds,
          'probe_action_logit': probe.actionLogit,
          'probe_value': probe.value,
          'semantic_card_count': modelSemanticCardCount,
          'semantic_cache_bytes': modelSemanticCacheBytes,
          'semantic_status':
              modelSemanticCardCount == null ? 'absent' : 'ready',
        },
      );
      return health;
    } catch (error) {
      await _onnxRuntimeService.close();
      modelError = error.toString();
      _recordLog(
        'model.onnx.load_failed',
        level: 'error',
        data: <String, Object?>{
          'primary': model.record.primary,
          'error': error.toString(),
        },
      );
      rethrow;
    } finally {
      isModelBusy = false;
      notifyListeners();
    }
  }

  // 释放当前本地 ONNX 推理会话但保留已安装模型
  Future<void> unloadSelectedModel() async {
    await _onnxRuntimeService.close();
    _recordLog('model.onnx.unloaded');
    notifyListeners();
  }

  // 保存独立于游戏连接的 Agent 设置
  Future<void> saveDecisionSettings(
    MobileDecisionSettings value,
    String apiKey,
  ) async {
    decisionSettings = value;
    _interventionRuntime.setBaseline(value);
    llmApiKey = apiKey;
    await _store.writeDecisionSettings(value, llmApiKey: apiKey);
    _recordLog(
      'settings.decision.saved',
      data: <String, Object?>{
        'mode': value.mode,
        'llm_enabled': value.llmEnabled,
        'llm_model': value.llmModel,
        'llm_game_chat_enabled': value.llmGameChatEnabled,
      },
    );
    notifyListeners();
  }

  // 启动一次允许服务器版本协商的游戏连接流程
  Future<void> connect(GameConnectionSettings nextSettings) async {
    if (isBusy || state == YgoClientState.connected) {
      return;
    }
    _attemptedProtocolVersions.clear();
    protocolVersionRetryCount = 0;
    negotiatedProtocolVersion = null;
    await _connect(nextSettings);
  }

  // 直接连接 MDPro3 游戏服务器并发送玩家登录信息
  Future<void> _connect(GameConnectionSettings nextSettings) async {
    if (isBusy || state == YgoClientState.connected) {
      return;
    }
    if (deck == null || !deck!.isValid) {
      throw const YgoProtocolException('请先选择有效的 YDK 卡组');
    }
    final normalizedHost = nextSettings.host.trim();
    if (normalizedHost.isEmpty) {
      throw const YgoProtocolException('请输入 MDPro3 游戏服务器地址');
    }
    if (!(nextSettings.port >= 1 && nextSettings.port <= 65535)) {
      throw const YgoProtocolException('游戏服务器端口必须位于 1 到 65535');
    }
    if (decisionSettings.mode != 'llm_only' &&
        selectedModel != null &&
        !isSelectedModelLoaded) {
      try {
        await loadSelectedModel();
      } catch (error) {
        _recordLog(
          'model.onnx.autoload_fallback',
          level: 'warning',
          data: <String, Object?>{'error': error.toString()},
        );
      }
    }
    gameState.reset();
    _gameChatHistory.clear();
    _lastAutomaticChatAt = null;
    _lastAutomaticChatText = null;
    _interventionRuntime.setBaseline(decisionSettings);
    final selectedDeck = deck;
    if (selectedDeck != null) {
      gameState.setOwnDeck(selectedDeck.main, selectedDeck.extra);
    }
    timePlayer = null;
    timeLeft = null;
    lastResponsePayload = null;
    retryCount = 0;
    _responseWatchdog?.cancel();
    _lastResponseAt = null;
    _lastResponseActionType = null;
    _responseSequence = 0;
    _lastSentResponseKey = null;
    _rejectedResponseKeys.clear();
    roomDuelMode = 0;
    isRoomHost = false;
    roomReady = <int, bool>{0: false, 1: false, 2: false, 3: false};
    _readySeat = null;
    _startRequested = false;
    _deckUpload = Future<void>.value();
    _recordLog(
      'connection.requested',
      data: <String, Object?>{
        'host': normalizedHost,
        'port': nextSettings.port,
        'game_id': nextSettings.gameId,
        'protocol_version': nextSettings.protocolVersion,
      },
    );
    isBusy = true;
    errorMessage = null;
    state = YgoClientState.connecting;
    settings = GameConnectionSettings(
      host: normalizedHost,
      port: nextSettings.port,
      password: nextSettings.password,
      playerName: nextSettings.playerName.trim(),
      gameId: nextSettings.gameId,
      protocolVersion: nextSettings.protocolVersion,
      preferSecond: nextSettings.preferSecond,
    );
    _attemptedProtocolVersions.add(settings.protocolVersion);
    notifyListeners();
    final client = YgoTcpClient(
      host: settings.host,
      port: settings.port,
      protocolVersion: settings.protocolVersion,
      gameId: settings.gameId,
    );
    final generation = ++_connectionGeneration;
    _client = client;
    _messageSubscription = client.messages.listen((message) {
      if (generation == _connectionGeneration) {
        _handleMessage(message);
      }
    });
    _errorSubscription = client.errors.listen((error) {
      if (generation == _connectionGeneration) {
        _handleError(error);
      }
    });
    _closedSubscription = client.closed.listen((_) {
      if (generation == _connectionGeneration) {
        _handleRemoteClosed(generation);
      }
    });
    try {
      await client.connect();
      state = YgoClientState.connected;
      roomPhase = 'joining';
      await _store.writeGameConnectionSettings(settings);
      await client.sendPlayerInfo(settings.playerName);
      await client.sendJoinGame(password: settings.password);
      _recordLog('connection.established');
    } catch (error) {
      errorMessage = error.toString();
      state = YgoClientState.failed;
      await _closeTransport(
        finalRoomPhase: 'disconnected',
        preserveProtocolRetry: _protocolRetryInProgress,
      );
      rethrow;
    } finally {
      if (generation == _connectionGeneration) {
        isBusy = false;
        notifyListeners();
      }
    }
  }

  // 主动断开 MDPro3 游戏服务器连接
  Future<void> disconnect() async {
    _protocolRetryInProgress = false;
    await _closeTransport(finalRoomPhase: 'disconnected');
  }

  // 统一释放网络订阅和 Socket 并让旧决策全部失效
  Future<void> _closeTransport({
    required String finalRoomPhase,
    bool preserveProtocolRetry = false,
  }) async {
    _connectionGeneration += 1;
    _decisionGeneration += 1;
    isBusy = false;
    isDeciding = false;
    _responseWatchdog?.cancel();
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _closedSubscription?.cancel();
    _messageSubscription = null;
    _errorSubscription = null;
    _closedSubscription = null;
    final client = _client;
    _client = null;
    await client?.dispose();
    state = YgoClientState.disconnected;
    roomPhase = finalRoomPhase;
    assignedPlayer = null;
    roomDuelMode = 0;
    isRoomHost = false;
    roomReady = <int, bool>{0: false, 1: false, 2: false, 3: false};
    _readySeat = null;
    _startRequested = false;
    _deckUpload = Future<void>.value();
    timePlayer = null;
    timeLeft = null;
    _lastSentResponseKey = null;
    _lastResponseAt = null;
    _lastResponseActionType = null;
    _rejectedResponseKeys.clear();
    gameState.playerId = 0;
    if (!preserveProtocolRetry) _protocolRetryInProgress = false;
    _recordLog(
      finalRoomPhase == 'duel_ended'
          ? 'connection.closed_after_duel'
          : 'connection.disconnected',
      data: <String, Object?>{'room_phase': finalRoomPhase},
    );
    notifyListeners();
  }

  // 发送当前玩家偏好的先后攻选择
  Future<void> sendFirstSecondChoice() async {
    await _client?.sendTpResult(preferSecond: settings.preferSecond);
  }

  // 规范化并发送指定游戏聊天文本后写入当前对局历史
  Future<void> sendChat(
    String text, {
    String source = 'mobile.user',
    bool automatic = false,
  }) async {
    final client = _client;
    if (client == null || !client.isConnected) {
      throw const YgoProtocolException('尚未连接 YGOPro 游戏服务器');
    }
    final normalized = normalizeGameChatText(
      text,
      maxUtf16Units: automatic ? 120 : ygoChatMaxUtf16Units,
      truncate: automatic,
    );
    await client.sendChat(normalized);
    _gameChatHistory.appendOutbound(
      normalized,
      source: source,
      automatic: automatic,
    );
    _recordLog(
      'chat.sent',
      data: <String, Object?>{
        'characters': normalized.runes.length,
        'utf16_units': normalized.codeUnits.length,
        'source': source,
        'automatic': automatic,
      },
    );
    notifyListeners();
  }

  // 设置当前对局使用的 YDK 卡组
  void setDeck(YdkDeck value) {
    deck = value;
    _recordLog(
      'deck.selected',
      data: <String, Object?>{
        'name': value.name,
        'main_count': value.main.length,
        'extra_count': value.extra.length,
        'side_count': value.side.length,
      },
    );
    notifyListeners();
  }

  // 将外部 YDK 导入本地卡组库并设为当前对局卡组
  Future<StoredYdkDeck> importDeck(YdkDeck value) async {
    if (state == YgoClientState.connected) {
      throw const YgoProtocolException('对局连接期间不能修改卡组库');
    }
    final record = await _deckLibraryService.importDeck(value);
    storedDecks = await _deckLibraryService.listDecks();
    selectedDeckFileName = record.fileName;
    setDeck(record.deck);
    await _store.writeSelectedDeckFileName(record.fileName);
    _recordLog(
      'deck.imported',
      data: <String, Object?>{
        'file_name': record.fileName,
        'main_count': record.deck.main.length,
        'extra_count': record.deck.extra.length,
        'side_count': record.deck.side.length,
      },
    );
    return record;
  }

  // 选择本地卡组库中的一份卡组用于下次连接
  Future<void> selectStoredDeck(StoredYdkDeck record) async {
    if (state == YgoClientState.connected) {
      throw const YgoProtocolException('对局连接期间不能切换卡组');
    }
    selectedDeckFileName = record.fileName;
    setDeck(record.deck);
    await _store.writeSelectedDeckFileName(record.fileName);
  }

  // 保存按单卡修改后的本地卡组并同步当前选择
  Future<StoredYdkDeck> saveStoredDeck(
    String fileName,
    YdkDeck value,
  ) async {
    if (state == YgoClientState.connected) {
      throw const YgoProtocolException('对局连接期间不能编辑卡组');
    }
    final record = await _deckLibraryService.saveDeck(fileName, value);
    storedDecks = await _deckLibraryService.listDecks();
    if (selectedDeckFileName == fileName) deck = record.deck;
    _recordLog(
      'deck.edited',
      data: <String, Object?>{
        'file_name': fileName,
        'main_count': record.deck.main.length,
        'extra_count': record.deck.extra.length,
        'side_count': record.deck.side.length,
        'duel_valid': record.deck.isValid,
      },
    );
    notifyListeners();
    return record;
  }

  // 删除本地卡组并在必要时清除当前选择
  Future<void> deleteStoredDeck(String fileName) async {
    if (state == YgoClientState.connected) {
      throw const YgoProtocolException('对局连接期间不能删除卡组');
    }
    await _deckLibraryService.deleteDeck(fileName);
    storedDecks = await _deckLibraryService.listDecks();
    if (selectedDeckFileName == fileName) {
      final replacement =
          storedDecks.where((record) => record.deck.isValid).firstOrNull;
      selectedDeckFileName = replacement?.fileName;
      deck = replacement?.deck;
      await _store.writeSelectedDeckFileName(replacement?.fileName);
    }
    _recordLog(
      'deck.deleted',
      data: <String, Object?>{'file_name': fileName},
    );
    notifyListeners();
  }

  // 返回卡片数据库中的名称或卡片编号占位文本
  String cardDisplayName(int code) {
    return _cardDatabaseService.lookup(code)?.name ?? '卡片 $code';
  }

  // 保存主题偏好
  Future<void> setDarkTheme(bool value) async {
    darkTheme = value;
    await _store.writeDarkTheme(value);
    notifyListeners();
  }

  // 释放本地对局控制器资源
  @override
  void dispose() {
    _responseWatchdog?.cancel();
    _messageSubscription?.cancel();
    _errorSubscription?.cancel();
    _closedSubscription?.cancel();
    _client?.dispose();
    _decisionEngine.close();
    unawaited(_onnxRuntimeService.close());
    unawaited(_cardDatabaseService.close());
    super.dispose();
  }

  // 保存最近服务器帧供诊断页面查看
  void _handleMessage(YgoServerMessage message) {
    messages = <YgoServerMessage>[
      message,
      ...messages,
    ].take(100).toList(growable: false);
    errorMessage = null;
    _recordLog(
      'network.stoc',
      data: <String, Object?>{
        'type': message.type,
        'payload_size': message.payload.length,
        'payload_hex': message.type == stocChat
            ? '<chat redacted>'
            : message.payload
                .take(256)
                .map((value) => value.toRadixString(16).padLeft(2, '0'))
                .join(' '),
        'truncated': message.payload.length > 256,
        'milliseconds_since_last_response': _lastResponseAt == null
            ? null
            : DateTime.now().difference(_lastResponseAt!).inMilliseconds,
        'last_response_action_type': _lastResponseActionType,
        'last_response_sequence':
            _responseSequence == 0 ? null : _responseSequence,
      },
    );
    if (message.type == stocSelectTp) {
      unawaited(sendFirstSecondChoice());
    }
    if (message.type == stocSelectHand) {
      unawaited(_sendHandChoice());
    }
    if (message.type == stocChat) {
      _handleGameChat(message.payload);
    }
    if (message.type == stocErrorMsg) {
      _handleServerError(message.payload);
    }
    if (message.type == stocJoinGame) {
      roomPhase = 'room_joined';
      roomDuelMode = parseRoomDuelMode(message.payload);
      roomReady = <int, bool>{0: false, 1: false, 2: false, 3: false};
      _readySeat = null;
      _startRequested = false;
      final currentDeck = deck;
      if (currentDeck == null) {
        errorMessage = '已加入房间但尚未选择 YDK 卡组';
      } else {
        _deckUpload = _sendDeck(currentDeck);
      }
      _recordLog(
        'room.joined',
        data: <String, Object?>{'duel_mode': roomDuelMode},
      );
    }
    if (message.type == stocTypeChange) {
      roomPhase = 'seat_assigned';
      if (message.payload.isNotEmpty) {
        final role = parseLobbyRolePayload(message.payload);
        final previousPlayer = assignedPlayer;
        assignedPlayer = role.player;
        isRoomHost = role.isHost;
        if (previousPlayer != assignedPlayer) _readySeat = null;
        _recordLog(
          'room.role.updated',
          data: <String, Object?>{
            'player_id': assignedPlayer,
            'is_host': isRoomHost,
          },
        );
      }
      final seat = assignedPlayer;
      if (seat != null && seat >= 0 && seat <= 3 && _readySeat != seat) {
        _readySeat = seat;
        unawaited(_sendReady());
      }
      unawaited(_startDuelIfHostReady());
    }
    if (message.type == stocHsPlayerChange) {
      try {
        final update = parseLobbyPlayerChangePayload(message.payload);
        if (update.state < playerChangeObserve) {
          roomReady[update.player] = false;
          roomReady[update.state] = false;
          _startRequested = false;
        } else if (update.state == playerChangeReady) {
          roomReady[update.player] = true;
        } else if (update.state == playerChangeObserve ||
            update.state == playerChangeNotReady ||
            update.state == playerChangeLeave) {
          roomReady[update.player] = false;
          _startRequested = false;
        }
        _recordLog(
          'room.player.updated',
          data: <String, Object?>{
            'player_id': update.player,
            'state': update.state,
            'ready': roomReady[update.player],
            'ready_players': roomReady.entries
                .where((entry) => entry.value)
                .map((entry) => entry.key)
                .toList(growable: false),
          },
        );
        unawaited(_startDuelIfHostReady());
      } catch (error) {
        _handleProtocolError(error);
      }
    }
    if (message.type == stocDuelStart) {
      roomPhase = 'duel_started';
      _gameChatHistory.clear();
      _lastAutomaticChatAt = null;
      _lastAutomaticChatText = null;
    }
    if (message.type == stocDuelEnd ||
        (message.type == stocHsPlayerExit && message.payload.isEmpty)) {
      roomPhase = 'duel_ended';
      _recordLog(
        'duel.ended',
        data: <String, Object?>{'server_message_type': message.type},
      );
      unawaited(_finishDuelSession());
      notifyListeners();
      return;
    }
    if (message.type == stocTimeLimit) {
      _handleTimeLimit(message.payload);
    }
    if (message.type == stocGameMsg) {
      _responseWatchdog?.cancel();
      final decisionGeneration = ++_decisionGeneration;
      isDeciding = false;
      try {
        gameState.applyBatch(
          message.payload,
          effectSlotResolver:
              _onnxRuntimeService.semanticStore?.resolveEffectSlot,
        );
        final pendingAction = gameState.pendingAction;
        if (pendingAction != null &&
            assignedPlayer != null &&
            (pendingAction.player == 0 || pendingAction.player == 1)) {
          final previousPlayer = gameState.playerId;
          gameState.assignPlayerPerspective(pendingAction.player);
          if (previousPlayer != pendingAction.player) {
            _recordLog(
              'duel.player_perspective.synchronized',
              data: <String, Object?>{
                'previous_core_player': previousPlayer,
                'core_player': pendingAction.player,
                'source': 'interaction_${pendingAction.type}',
              },
            );
          }
        }
        _recordLog(
          'duel.ocg.batch',
          data: <String, Object?>{
            'types': gameState.lastBatchTypes,
            'pending_action_type': gameState.pendingAction?.type,
            'pending_action_player': gameState.pendingAction?.player,
            'assigned_player': assignedPlayer,
            'milliseconds_since_last_response': _lastResponseAt == null
                ? null
                : DateTime.now().difference(_lastResponseAt!).inMilliseconds,
            'last_response_sequence':
                _responseSequence == 0 ? null : _responseSequence,
          },
        );
        if (gameState.retryRequested) {
          retryCount += 1;
          final rejected = _lastSentResponseKey;
          if (rejected != null) _rejectedResponseKeys.add(rejected);
          _recordLog(
            'duel.response.retried',
            level: 'warning',
            data: <String, Object?>{
              'retry_count': retryCount,
              'rejected_response_key': rejected,
            },
          );
        } else if (gameState.lastBatchTypes.any(ocgInteractionTypes.contains)) {
          _rejectedResponseKeys.clear();
        }
        unawaited(_handlePendingAction(decisionGeneration));
      } catch (error) {
        _handleProtocolError(error);
      }
    }
    notifyListeners();
  }

  // 保存网络或协议错误并切换失败状态
  void _handleError(Object error) {
    errors = <Object>[error, ...errors].take(30).toList(growable: false);
    errorMessage = error.toString();
    state = YgoClientState.failed;
    _recordLog(
      'network.failed',
      level: 'error',
      data: <String, Object?>{'error': error.toString()},
    );
    notifyListeners();
  }

  // 解析服务器错误并在版本过低时自动协商重连一次
  void _handleServerError(List<int> payload) {
    try {
      final parsed = parseServerErrorPayload(payload);
      final requiredVersion = parsed.code;
      if (parsed.errorType == 4 && requiredVersion != null) {
        final currentVersion = settings.protocolVersion;
        final canRetry = requiredVersion > 0 &&
            requiredVersion <= 0xFFFFFFFF &&
            !_attemptedProtocolVersions.contains(requiredVersion) &&
            protocolVersionRetryCount < 1 &&
            !_protocolRetryInProgress;
        errorMessage = canRetry
            ? '服务器要求协议版本 0x${requiredVersion.toRadixString(16).toUpperCase()}，正在自动重连'
            : '服务器拒绝协议版本 0x${currentVersion.toRadixString(16).toUpperCase()}，要求 0x${requiredVersion.toRadixString(16).toUpperCase()}';
        _recordLog(
          'connection.protocol_version_rejected',
          level: canRetry ? 'warning' : 'error',
          data: <String, Object?>{
            'active_version': currentVersion,
            'required_version': requiredVersion,
            'auto_retry': canRetry,
            'retry_count': protocolVersionRetryCount,
          },
        );
        if (canRetry) {
          _protocolRetryInProgress = true;
          unawaited(_retryProtocolVersion(requiredVersion));
        } else {
          state = YgoClientState.failed;
        }
      } else {
        errorMessage = parsed.errorType == 2 && parsed.code != null
            ? '服务器拒绝卡组，违规卡片代码 ${parsed.code}'
            : '游戏服务器返回错误 ${parsed.errorType}${parsed.code == null ? '' : '，代码 ${parsed.code}'}';
        state = YgoClientState.failed;
        _recordLog(
          'server.error',
          level: 'error',
          data: <String, Object?>{
            'error_type': parsed.errorType,
            'error_code': parsed.code,
          },
        );
      }
      notifyListeners();
    } catch (error) {
      _handleProtocolError(error);
    }
  }

  // 使用服务器要求的协议版本关闭旧连接并保留卡组重新加入
  Future<void> _retryProtocolVersion(int requiredVersion) async {
    final previousVersion = settings.protocolVersion;
    protocolVersionRetryCount += 1;
    negotiatedProtocolVersion = requiredVersion;
    final retrySettings = GameConnectionSettings(
      host: settings.host,
      port: settings.port,
      password: settings.password,
      playerName: settings.playerName,
      gameId: settings.gameId,
      protocolVersion: requiredVersion,
      preferSecond: settings.preferSecond,
    );
    try {
      await _closeTransport(
        finalRoomPhase: 'version_retry',
        preserveProtocolRetry: true,
      );
      _recordLog(
        'connection.protocol_version_retrying',
        data: <String, Object?>{
          'previous_version': previousVersion,
          'required_version': requiredVersion,
          'retry': protocolVersionRetryCount,
        },
      );
      await _connect(retrySettings);
    } catch (error) {
      errorMessage = '协议版本自动重连失败：$error';
      state = YgoClientState.failed;
      _recordLog(
        'connection.protocol_version_retry_failed',
        level: 'error',
        data: <String, Object?>{'error': error.toString()},
      );
      notifyListeners();
    } finally {
      _protocolRetryInProgress = false;
    }
  }

  // 在服务器主动关闭后同步页面状态并释放旧客户端资源
  void _handleRemoteClosed(int generation) {
    if (generation != _connectionGeneration || _protocolRetryInProgress) return;
    final finalPhase =
        roomPhase == 'duel_ended' ? 'duel_ended' : 'connection_closed';
    _recordLog(
      'connection.remote_closed',
      data: <String, Object?>{'room_phase': roomPhase},
    );
    unawaited(_closeTransport(finalRoomPhase: finalPhase));
  }

  // 对局结束后主动归还本地监听端口并保留对局日志
  Future<void> _finishDuelSession() async {
    await Future<void>.delayed(Duration.zero);
    if (state == YgoClientState.disconnected) return;
    await _closeTransport(finalRoomPhase: 'duel_ended');
  }

  // 保存协议解析错误但保留仍然有效的 TCP 连接
  void _handleProtocolError(Object error) {
    errors = <Object>[error, ...errors].take(30).toList(growable: false);
    errorMessage = error.toString();
    _recordLog(
      'protocol.failed',
      level: 'error',
      data: <String, Object?>{
        'error': error.toString(),
        'last_ocg_types': gameState.lastBatchTypes,
      },
    );
    notifyListeners();
  }

  // 上传已校验卡组并等待服务器座位确认
  Future<void> _sendDeck(YdkDeck currentDeck) async {
    try {
      await _client?.sendDeck(
        currentDeck.main,
        currentDeck.extra,
        currentDeck.side,
      );
      roomPhase = 'deck_sent';
      _recordLog(
        'deck.sent',
        data: <String, Object?>{
          'main_count': currentDeck.main.length,
          'extra_count': currentDeck.extra.length,
          'side_count': currentDeck.side.length,
        },
      );
      notifyListeners();
    } catch (error) {
      _handleError(error);
    }
  }

  // 收到座位分配后发送准备信号
  Future<void> _sendReady() async {
    try {
      await _deckUpload;
      await _client?.sendReady();
      roomPhase = 'ready_sent';
      _recordLog(
        'room.ready.sent',
        data: <String, Object?>{'player_id': assignedPlayer},
      );
      notifyListeners();
    } catch (error) {
      _readySeat = null;
      _handleError(error);
    }
  }

  // 在全部决斗座位准备后由房主自动请求开始对局
  Future<void> _startDuelIfHostReady() async {
    if (!isRoomHost || roomPhase == 'duel_started' || _startRequested) return;
    final requiredPlayers = roomDuelMode == 2
        ? const <int>[0, 1, 2, 3]
        : const <int>[0, 1];
    if (!requiredPlayers.every((player) => roomReady[player] ?? false)) return;
    _startRequested = true;
    try {
      await _client?.sendStartDuel();
      roomPhase = 'start_requested';
      _recordLog(
        'room.start.requested',
        data: <String, Object?>{
          'duel_mode': roomDuelMode,
          'ready_players': requiredPlayers,
        },
      );
      notifyListeners();
    } catch (error) {
      _startRequested = false;
      _handleError(error);
    }
  }

  // 选择一个合法的初始手牌结果
  Future<void> _sendHandChoice() async {
    try {
      await _client?.sendHandResult(Random().nextInt(3) + 1);
      _recordLog('duel.hand_choice.sent');
    } catch (error) {
      _handleError(error);
    }
  }

  // 记录服务器计时并在轮到本客户端时立即发送确认
  void _handleTimeLimit(List<int> payload) {
    try {
      final parsed = parseTimeLimitPayload(payload);
      timePlayer = parsed.player;
      timeLeft = parsed.seconds;
      _recordLog(
        'duel.time.updated',
        data: <String, Object?>{
          'player': parsed.player,
          'seconds': parsed.seconds,
          'is_self': parsed.player == gameState.playerId,
        },
      );
      if (parsed.player == gameState.playerId) {
        unawaited(_sendTimeConfirm());
      }
    } catch (error) {
      _handleProtocolError(error);
    }
  }

  // 发送本客户端已接收计时帧的确认消息
  Future<void> _sendTimeConfirm() async {
    try {
      await _client?.sendTimeConfirm();
      _recordLog('duel.time.confirmed');
    } catch (error) {
      _handleError(error);
    }
  }

  // 使用当前决策模式异步处理交互并防止过期结果发送到新时点
  Future<void> _handlePendingAction(int decisionGeneration) async {
    final action = gameState.pendingAction;
    if (action == null || (assignedPlayer != 0 && assignedPlayer != 1)) return;
    isDeciding = true;
    _recordLog(
      'decision.started',
      data: <String, Object?>{
        'decision_generation': decisionGeneration,
        'action_type': action.type,
        'action_player': action.player,
        'assigned_player': assignedPlayer,
        'option_count': action.options.length,
        'selection_min': action.selectionMin,
        'selection_max': action.selectionMax,
        'cancelable': action.cancelable,
        'finishable': action.finishable,
      },
    );
    notifyListeners();
    final effectiveSettings = _interventionRuntime.effective;
    late final MobileDecisionOutcome outcome;
    try {
      outcome = await _decisionEngine.decide(
        settings: effectiveSettings,
        apiKey: llmApiKey,
        gameState: gameState,
        action: action,
        excludedPayloadKeys: Set<String>.unmodifiable(_rejectedResponseKeys),
        runtimeControls: _interventionRuntime.toPromptJson(),
        gameChatContext: _gameChatHistory.toPromptContext(),
      );
    } catch (error, stackTrace) {
      if (decisionGeneration != _decisionGeneration ||
          !identical(gameState.pendingAction, action)) {
        return;
      }
      isDeciding = false;
      lastDecisionSource = 'decision_error';
      lastDecisionDescription = error.toString();
      _recordLog(
        'decision.failed',
        level: 'error',
        data: <String, Object?>{
          'action_type': action.type,
          'error': error.toString(),
          'stack': _truncateLog(stackTrace.toString()),
        },
      );
      notifyListeners();
      return;
    }
    if (decisionGeneration != _decisionGeneration ||
        !identical(gameState.pendingAction, action)) {
      return;
    }
    isDeciding = false;
    lastDecisionSource = outcome.source;
    lastDecisionDescription = outcome.description;
    lastLlmRawContent = outcome.rawLlmContent;
    lastDecisionElapsed = outcome.elapsed;
    lastPromptTokens = outcome.promptTokens;
    lastCompletionTokens = outcome.completionTokens;
    lastCachedTokens = outcome.cachedTokens;
    lastCoreConfidence = outcome.coreConfidence;
    lastCoreValue = outcome.coreValue;
    _recordLog(
      'decision.completed',
      data: <String, Object?>{
        'action_type': action.type,
        'source': outcome.source,
        'description': outcome.description,
        'elapsed_ms': outcome.elapsed.inMilliseconds,
        'prompt_tokens': outcome.promptTokens,
        'completion_tokens': outcome.completionTokens,
        'cached_tokens': outcome.cachedTokens,
        'core_confidence': outcome.coreConfidence,
        'core_value': outcome.coreValue,
        'llm_raw': _truncateLog(outcome.rawLlmContent),
      },
    );
    if (outcome.rawLlmContent != null) {
      debugPrint('[LLM 原始响应] ${outcome.rawLlmContent}');
    }
    final response = outcome.response;
    if (response == null) {
      notifyListeners();
      return;
    }
    try {
      _responseWatchdog?.cancel();
      final responseSequence = ++_responseSequence;
      _lastResponseAt = DateTime.now();
      _lastResponseActionType = action.type;
      _responseWatchdog = Timer(const Duration(seconds: 8), () {
        _recordLog(
          'duel.response.no_followup_game_frame',
          level: 'warning',
          data: <String, Object?>{
            'response_sequence': responseSequence,
            'action_type': action.type,
            'room_phase': roomPhase,
            'time_player': timePlayer,
            'time_left': timeLeft,
            'note': '服务器可能正在等待另一位玩家或尚未推进 OCG 消息',
          },
        );
      });
      await _client?.sendResponse(response.payload);
      lastResponsePayload = List<int>.unmodifiable(response.payload);
      _lastSentResponseKey = DecisionCatalog.payloadKey(response.payload);
      _recordLog(
        'duel.response.sent',
        data: <String, Object?>{
          'action_type': action.type,
          'decision_generation': decisionGeneration,
          'response_sequence': responseSequence,
          'payload_hex': response.payload
              .map((value) => value.toRadixString(16).padLeft(2, '0'))
              .join(' '),
        },
      );
      _progressAutonomousOverride();
      final interventionUpdate = outcome.interventionUpdate;
      if (interventionUpdate != null) {
        final result = _interventionRuntime.apply(interventionUpdate);
        _recordLog(
          result.applied
              ? 'runtime.autonomy.applied'
              : 'runtime.autonomy.ignored',
          level: result.applied ? 'info' : 'warning',
          data: <String, Object?>{
            'base_revision': interventionUpdate.baseRevision,
            'mode': interventionUpdate.mode,
            'core_confidence_threshold':
                interventionUpdate.coreConfidenceThreshold,
            'force_llm_message_types': interventionUpdate.forceLlmMessageTypes,
            'ttl_decisions': interventionUpdate.ttlDecisions,
            'reason': interventionUpdate.reason,
            'result_reason': result.reason,
          },
        );
      }
      final chatMessage = outcome.chatMessage;
      if (decisionSettings.llmGameChatEnabled && chatMessage != null) {
        unawaited(_sendAutomaticChat(chatMessage));
      }
      notifyListeners();
    } catch (error) {
      _responseWatchdog?.cancel();
      _handleError(error);
    }
  }

  // 推进现有临时覆盖寿命并在到期时恢复人工基线
  void _progressAutonomousOverride() {
    final progress = _interventionRuntime.onDecisionCommitted();
    if (!progress.changed) return;
    _recordLog(
      progress.expired
          ? 'runtime.autonomy.expired'
          : 'runtime.autonomy.progressed',
      data: <String, Object?>{
        'remaining_decisions': progress.remainingDecisions,
      },
    );
  }

  // 解析服务端聊天并在当前对局历史中去除本客户端回声
  void _handleGameChat(List<int> payload) {
    try {
      final decoded = decodeServerGameChat(payload);
      final agentPlayerId =
          gameState.duelStarted ? gameState.playerId : assignedPlayer;
      final message = _gameChatHistory.appendInbound(
        playerType: decoded.playerType,
        agentPlayerId: agentPlayerId,
        text: decoded.text,
      );
      _recordLog(
        'chat.received',
        data: <String, Object?>{
          'player_type': decoded.playerType,
          'role': classifyGameChatRole(decoded.playerType, agentPlayerId),
          'characters': decoded.text.runes.length,
          'echo_ignored': message == null,
        },
      );
    } catch (error) {
      _recordLog(
        'chat.decode_failed',
        level: 'warning',
        data: <String, Object?>{
          'payload_size': payload.length,
          'error': error.toString(),
        },
      );
    }
  }

  // 按固定间隔和去重规则发送 LLM 自动聊天建议
  Future<void> _sendAutomaticChat(String text) async {
    try {
      final normalized = normalizeGameChatText(
        text,
        maxUtf16Units: 120,
        truncate: true,
      );
      final now = DateTime.now();
      final previousAt = _lastAutomaticChatAt;
      if (previousAt != null &&
          now.difference(previousAt) < const Duration(seconds: 15)) {
        _recordLog(
          'chat.auto_send_skipped',
          data: const <String, Object?>{'reason': '自动聊天仍在十五秒节流期'},
        );
        return;
      }
      if (normalized == _lastAutomaticChatText) {
        _recordLog(
          'chat.auto_send_skipped',
          data: const <String, Object?>{'reason': '与上一条自动聊天重复'},
        );
        return;
      }
      await sendChat(normalized, source: 'llm', automatic: true);
      _lastAutomaticChatAt = now;
      _lastAutomaticChatText = normalized;
    } catch (error) {
      _recordLog(
        'chat.auto_send_failed',
        level: 'warning',
        data: <String, Object?>{'error': error.toString()},
      );
    }
  }

  // 异步记录脱敏诊断事件且不阻塞游戏网络循环
  void _recordLog(
    String event, {
    String level = 'info',
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    unawaited(
      _diagnosticLogStore.record(event, level: level, data: data).catchError((
        Object error,
      ) {
        debugPrint('[诊断日志写入失败] $error');
      }),
    );
  }

  // 截断可能很长的 LLM 原始返回以控制日志体积
  static String? _truncateLog(String? value) {
    if (value == null || value.length <= 4000) return value;
    return '${value.substring(0, 4000)}…';
  }
}
