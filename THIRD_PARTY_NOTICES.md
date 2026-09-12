# 第三方组件说明

Galatea Link mobile 使用 Flutter、Dart 及 `pubspec.yaml` 中列出的开源组件。应用设置页的“开源许可”会显示 Flutter 构建过程中由各组件登记的许可文本

其中 `third_party/flutter_onnxruntime` 是仓库内维护的 ONNX Runtime Flutter 适配层，其上游组件和原生二进制许可应随每次升级同步核对。发布者应在生成正式 APK 前检查依赖锁文件、原生 AAR/动态库来源和许可证是否一致

本文件不替代各组件自身的许可证。完整依赖版本以 `pubspec.lock` 和 Android 构建锁定结果为准
