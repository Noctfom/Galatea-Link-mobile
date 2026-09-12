// Galatea Link 移动端入口，创建独立游戏客户端应用

import 'package:flutter/material.dart';

import 'src/standalone_app.dart';
import 'src/local_game_controller.dart';
import 'src/services/secure_settings_store.dart';

// 创建移动端应用并注入网络与状态服务
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SecureSettingsStore();
  final controller = LocalGameController(store: store);
  runApp(StandaloneApp(controller: controller));
}
