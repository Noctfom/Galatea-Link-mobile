// YGOPro 协议字节游标，提供边界严格的整数和文本读取

import 'dart:convert';
import 'dart:typed_data';

class YgoProtocolException implements Exception {
  const YgoProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ByteCursor {
  ByteCursor(List<int> source)
      : _bytes = Uint8List.fromList(source),
        _offset = 0;

  final Uint8List _bytes;
  int _offset;

  // 返回当前读取位置
  int get offset => _offset;

  // 返回当前剩余字节数
  int get remaining => _bytes.length - _offset;

  // 读取一个无符号字节
  int readUint8() {
    _require(1);
    return _bytes[_offset++];
  }

  // 读取小端无符号十六位整数
  int readUint16Le() {
    _require(2);
    final value = _bytes[_offset] | (_bytes[_offset + 1] << 8);
    _offset += 2;
    return value;
  }

  // 读取小端无符号三十二位整数
  int readUint32Le() {
    _require(4);
    final value = _bytes[_offset] |
        (_bytes[_offset + 1] << 8) |
        (_bytes[_offset + 2] << 16) |
        (_bytes[_offset + 3] << 24);
    _offset += 4;
    return value;
  }

  // 读取小端有符号十六位整数
  int readInt16Le() {
    final value = readUint16Le();
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  // 读取小端有符号三十二位整数
  int readInt32Le() {
    final value = readUint32Le();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  // 读取指定长度的独立字节副本
  Uint8List readBytes(int length) {
    if (length < 0) {
      throw const YgoProtocolException('读取长度不能为负数');
    }
    _require(length);
    final value = Uint8List.fromList(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return value;
  }

  // 读取以零结尾的 UTF-16LE 文本
  String readUtf16LeZ({int? maxBytes}) {
    final start = _offset;
    final limit = maxBytes == null ? _bytes.length : start + maxBytes;
    if (limit > _bytes.length || maxBytes != null && maxBytes.isOdd) {
      throw const YgoProtocolException('UTF-16LE 文本边界无效');
    }
    var end = start;
    while (end + 1 < limit) {
      if (_bytes[end] == 0 && _bytes[end + 1] == 0) {
        final text = utf8.decode(_utf16LeToUtf8(_bytes.sublist(start, end)));
        _offset = end + 2;
        return text;
      }
      end += 2;
    }
    throw const YgoProtocolException('UTF-16LE 文本缺少结束符');
  }

  // 确认当前载荷已经完整读取
  void requireEnd() {
    if (remaining != 0) {
      throw YgoProtocolException('消息仍有 $remaining 个未读取字节');
    }
  }

  // 检查读取操作不会越过消息边界
  void _require(int length) {
    if (length < 0 || remaining < length) {
      throw YgoProtocolException(
        '消息长度不足 offset=$_offset need=$length remaining=$remaining',
      );
    }
  }

  // 将 UTF-16LE 原始单元转换为 UTF-8 字节
  static List<int> _utf16LeToUtf8(List<int> source) {
    if (source.length.isOdd) {
      throw const YgoProtocolException('UTF-16LE 字节长度必须为偶数');
    }
    final units = <int>[];
    for (var index = 0; index < source.length; index += 2) {
      units.add(source[index] | (source[index + 1] << 8));
    }
    return utf8.encode(String.fromCharCodes(units));
  }
}
