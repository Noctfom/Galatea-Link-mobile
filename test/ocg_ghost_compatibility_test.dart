// OCG 幽灵字段兼容测试，验证手机本地房间与标准在线房间可以共用解析器

import 'package:flutter_test/flutter_test.dart';
import 'package:galatea_link_mobile/src/game_protocol/ocg_parser.dart';
import 'package:galatea_link_mobile/src/game_state.dart';

// 把三十二位整数编码为小端字节
List<int> _u32(int value) => <int>[
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ];

// 创建一条标准的十三字节连锁候选
List<int> _chainOption({
  required int code,
  int effectFlag = 0,
  int location = 0x0a040800,
  int description = 0,
}) =>
    <int>[
      effectFlag,
      ..._u32(code),
      ..._u32(location),
      ..._u32(description),
    ];

// 运行标准网络布局与 Core 本地幽灵布局兼容测试
void main() {
  test('normalizes real core ghost confirm cards payload', () {
    final parsed = OcgParser.parse(<int>[
      31,
      1,
      0,
      1,
      ..._u32(46986420),
      0,
      2,
      3,
    ]);

    expect(parsed, hasLength(1));
    expect(parsed.single.type, 31);
    expect(parsed.single.normalizedCoreGhost, isTrue);
    expect(parsed.single.payload, <int>[
      1,
      1,
      ..._u32(46986420),
      0,
      2,
      3,
    ]);
  });

  test('normalizes real core ghost select chain payload', () {
    final raw = <int>[
      16,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0x21,
      0,
      0,
      ..._chainOption(code: 48680970),
    ];
    final parsed = OcgParser.parse(raw);

    expect(parsed, hasLength(1));
    expect(parsed.single.normalizedCoreGhost, isTrue);
    expect(parsed.single.payload, hasLength(24));

    final state = MobileGameState()..applyBatch(raw);
    expect(state.pendingAction?.type, 16);
    expect(state.pendingAction?.options, <int>[0, -1]);
  });

  test('removes core delimiter before later chain options', () {
    final raw = <int>[
      16,
      0,
      2,
      1,
      0,
      ...List<int>.filled(8, 0),
      ..._chainOption(code: 111, description: 1),
      0xff,
      ..._chainOption(code: 222, description: 2),
    ];
    final parsed = OcgParser.parse(raw);

    expect(parsed.single.normalizedCoreGhost, isTrue);
    expect(parsed.single.payload, hasLength(37));
    expect(parsed.single.payload.contains(0xff), isFalse);
  });

  test('keeps standard chain layout followed by another message', () {
    final standardPayload = <int>[
      0,
      1,
      0,
      ...List<int>.filled(8, 0),
      ..._chainOption(code: 12345678),
    ];
    final parsed = OcgParser.parse(<int>[
      16,
      ...standardPayload,
      40,
      1,
    ]);

    expect(parsed.map((message) => message.type), <int>[16, 40]);
    expect(parsed.first.normalizedCoreGhost, isFalse);
    expect(parsed.first.payload, standardPayload);
  });
}
