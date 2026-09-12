<!-- Galatea Link mobile 本地 ONNX Runtime 兼容补丁说明 -->

# Galatea V3 窄整数张量补丁

上游 1.8.5 Android 实现声明了 `int16` 与 `int8`，但没有实现从 Dart `Int32List` 到这两种张量的转换

本地补丁为 Android 增加饱和转换，使 Model Protocol V3 的语义和动作响应张量可被原生 ONNX Runtime 接收
