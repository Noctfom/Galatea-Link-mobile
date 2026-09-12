// YGOPro TCP 分包编解码，处理两字节小端长度和消息类型

import 'dart:typed_data';

import 'byte_cursor.dart';

const int maxYgoFrameLength = 0xFFFF;

class YgoFrame {
  const YgoFrame({required this.type, required this.payload});

  final int type;
  final Uint8List payload;
}

class YgoFrameCodec {
  YgoFrameCodec({this.maxFrameLength = maxYgoFrameLength});

  final int maxFrameLength;
  final List<int> _buffer = <int>[];

  // 将消息类型和载荷编码为 YGOPro TCP 数据帧
  Uint8List encode(int type, List<int> payload) {
    if (type < 0 || type > 0xFF) {
      throw const YgoProtocolException('YGOPro 消息类型必须位于 0 到 255');
    }
    final length = payload.length + 1;
    if (length < 1 || length > maxFrameLength) {
      throw YgoProtocolException('YGOPro 消息长度超出范围: $length');
    }
    final result = Uint8List(length + 2);
    result[0] = length & 0xFF;
    result[1] = (length >> 8) & 0xFF;
    result[2] = type;
    result.setRange(3, result.length, payload);
    return result;
  }

  // 接收任意分片并只返回完整的数据帧
  List<YgoFrame> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = <YgoFrame>[];
    while (_buffer.length >= 2) {
      final length = _buffer[0] | (_buffer[1] << 8);
      if (length < 1 || length > maxFrameLength) {
        _buffer.clear();
        throw YgoProtocolException('YGOPro 帧长度无效: $length');
      }
      final totalLength = length + 2;
      if (_buffer.length < totalLength) {
        break;
      }
      final type = _buffer[2];
      final payload = Uint8List.fromList(_buffer.sublist(3, totalLength));
      _buffer.removeRange(0, totalLength);
      frames.add(YgoFrame(type: type, payload: payload));
    }
    return frames;
  }

  // 清空尚未组成完整帧的缓存
  void clear() {
    _buffer.clear();
  }
}
