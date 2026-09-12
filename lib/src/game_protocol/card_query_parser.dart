// YGOPro 卡片查询数据解析器，按分块长度安全还原公开卡片属性

import 'byte_cursor.dart';

const int queryCode = 0x00000001;
const int queryPosition = 0x00000002;
const int queryAlias = 0x00000004;
const int queryType = 0x00000008;
const int queryLevel = 0x00000010;
const int queryRank = 0x00000020;
const int queryAttribute = 0x00000040;
const int queryRace = 0x00000080;
const int queryAttack = 0x00000100;
const int queryDefense = 0x00000200;
const int queryBaseAttack = 0x00000400;
const int queryBaseDefense = 0x00000800;
const int queryReason = 0x00001000;
const int queryReasonCard = 0x00002000;
const int queryEquipCard = 0x00004000;
const int queryTargetCard = 0x00008000;
const int queryOverlayCard = 0x00010000;
const int queryCounters = 0x00020000;
const int queryOwner = 0x00040000;
const int queryStatus = 0x00080000;
const int queryIsPublic = 0x00100000;
const int queryLeftScale = 0x00200000;
const int queryRightScale = 0x00400000;
const int queryLink = 0x00800000;
const int queryIsHidden = 0x01000000;
const int queryCover = 0x02000000;
const int queryEnd = 0x80000000;

const int _knownQueryFlags = queryCode |
    queryPosition |
    queryAlias |
    queryType |
    queryLevel |
    queryRank |
    queryAttribute |
    queryRace |
    queryAttack |
    queryDefense |
    queryBaseAttack |
    queryBaseDefense |
    queryReason |
    queryReasonCard |
    queryEquipCard |
    queryTargetCard |
    queryOverlayCard |
    queryCounters |
    queryOwner |
    queryStatus |
    queryIsPublic |
    queryLeftScale |
    queryRightScale |
    queryLink |
    queryIsHidden |
    queryCover |
    queryEnd;

class CardLocationReference {
  const CardLocationReference({
    required this.controller,
    required this.location,
    required this.sequence,
    required this.position,
  });

  final int controller;
  final int location;
  final int sequence;
  final int position;
}

class CardQueryUpdate {
  const CardQueryUpdate({
    required this.flags,
    this.clearData = false,
    this.code,
    this.position,
    this.alias,
    this.type,
    this.level,
    this.rank,
    this.attribute,
    this.race,
    this.attack,
    this.defense,
    this.baseAttack,
    this.baseDefense,
    this.reason,
    this.reasonCard,
    this.equipCard,
    this.targetCards,
    this.overlayCodes,
    this.counters,
    this.owner,
    this.status,
    this.isPublic,
    this.leftScale,
    this.rightScale,
    this.link,
    this.linkMarker,
    this.isHidden,
    this.cover,
  });

  final int flags;
  final bool clearData;
  final int? code;
  final int? position;
  final int? alias;
  final int? type;
  final int? level;
  final int? rank;
  final int? attribute;
  final int? race;
  final int? attack;
  final int? defense;
  final int? baseAttack;
  final int? baseDefense;
  final int? reason;
  final CardLocationReference? reasonCard;
  final CardLocationReference? equipCard;
  final List<CardLocationReference>? targetCards;
  final List<int>? overlayCodes;
  final Map<int, int>? counters;
  final int? owner;
  final int? status;
  final bool? isPublic;
  final int? leftScale;
  final int? rightScale;
  final int? link;
  final int? linkMarker;
  final bool? isHidden;
  final int? cover;
}

class CardQueryBlock {
  const CardQueryBlock({required this.byteLength, this.update});

  final int byteLength;
  final CardQueryUpdate? update;

  bool get hasUpdate => update != null;
}

class CardQueryParser {
  // 读取一个带四字节总长度头的查询分块
  static CardQueryBlock parseBlock(ByteCursor source) {
    final blockLength = source.readUint32Le();
    if (blockLength < 4) {
      throw YgoProtocolException('卡片查询分块长度无效 length=$blockLength');
    }
    final bodyLength = blockLength - 4;
    if (bodyLength > source.remaining) {
      throw YgoProtocolException(
        '卡片查询分块越界 length=$blockLength remaining=${source.remaining + 4}',
      );
    }
    if (bodyLength == 0) {
      return const CardQueryBlock(byteLength: 4);
    }
    if (bodyLength < 4) {
      throw YgoProtocolException('卡片查询分块缺少字段位图 length=$blockLength');
    }

    final cursor = ByteCursor(source.readBytes(bodyLength));
    final flags = cursor.readUint32Le();
    final unknownFlags = flags & ~_knownQueryFlags;
    if (unknownFlags != 0) {
      throw YgoProtocolException(
        '卡片查询包含未知字段 flags=0x${unknownFlags.toRadixString(16)}',
      );
    }
    if (flags == 0) {
      final padding = cursor.readBytes(cursor.remaining);
      if (padding.any((value) => value != 0)) {
        throw YgoProtocolException('空卡片查询包含非零兼容填充');
      }
      return CardQueryBlock(
        byteLength: blockLength,
        update: const CardQueryUpdate(flags: 0, clearData: true),
      );
    }

    int? code;
    int? position;
    int? alias;
    int? type;
    int? level;
    int? rank;
    int? attribute;
    int? race;
    int? attack;
    int? defense;
    int? baseAttack;
    int? baseDefense;
    int? reason;
    CardLocationReference? reasonCard;
    CardLocationReference? equipCard;
    List<CardLocationReference>? targetCards;
    List<int>? overlayCodes;
    Map<int, int>? counters;
    int? owner;
    int? status;
    bool? isPublic;
    int? leftScale;
    int? rightScale;
    int? link;
    int? linkMarker;
    bool? isHidden;
    int? cover;

    if (_has(flags, queryCode)) code = cursor.readUint32Le() & 0x7fffffff;
    if (_has(flags, queryPosition)) {
      position = (cursor.readUint32Le() >> 24) & 0xff;
    }
    if (_has(flags, queryAlias)) alias = cursor.readUint32Le();
    if (_has(flags, queryType)) type = cursor.readUint32Le();
    if (_has(flags, queryLevel)) level = cursor.readUint32Le();
    if (_has(flags, queryRank)) rank = cursor.readUint32Le();
    if (_has(flags, queryAttribute)) attribute = cursor.readUint32Le();
    if (_has(flags, queryRace)) race = cursor.readUint32Le();
    if (_has(flags, queryAttack)) attack = cursor.readInt32Le();
    if (_has(flags, queryDefense)) defense = cursor.readInt32Le();
    if (_has(flags, queryBaseAttack)) baseAttack = cursor.readInt32Le();
    if (_has(flags, queryBaseDefense)) baseDefense = cursor.readInt32Le();
    if (_has(flags, queryReason)) reason = cursor.readUint32Le();
    if (_has(flags, queryReasonCard)) reasonCard = _readLocation(cursor);
    if (_has(flags, queryEquipCard)) equipCard = _readLocation(cursor);
    if (_has(flags, queryTargetCard)) {
      targetCards = _readLocations(cursor, '目标卡片');
    }
    if (_has(flags, queryOverlayCard)) {
      overlayCodes = _readCodes(cursor, '叠放卡片');
    }
    if (_has(flags, queryCounters)) counters = _readCounters(cursor);
    if (_has(flags, queryOwner)) owner = cursor.readUint32Le();
    if (_has(flags, queryStatus)) status = cursor.readUint32Le();
    if (_has(flags, queryIsPublic)) isPublic = true;
    if (_has(flags, queryLeftScale)) leftScale = cursor.readUint32Le();
    if (_has(flags, queryRightScale)) rightScale = cursor.readUint32Le();
    if (_has(flags, queryLink)) {
      link = cursor.readUint32Le();
      linkMarker = cursor.readUint32Le();
    }
    if (_has(flags, queryIsHidden)) isHidden = true;
    if (_has(flags, queryCover)) cover = cursor.readUint32Le();
    cursor.requireEnd();

    return CardQueryBlock(
      byteLength: blockLength,
      update: CardQueryUpdate(
        flags: flags,
        code: code,
        position: position,
        alias: alias,
        type: type,
        level: level,
        rank: rank,
        attribute: attribute,
        race: race,
        attack: attack,
        defense: defense,
        baseAttack: baseAttack,
        baseDefense: baseDefense,
        reason: reason,
        reasonCard: reasonCard,
        equipCard: equipCard,
        targetCards:
            targetCards == null ? null : List.unmodifiable(targetCards),
        overlayCodes:
            overlayCodes == null ? null : List.unmodifiable(overlayCodes),
        counters: counters == null ? null : Map.unmodifiable(counters),
        owner: owner,
        status: status,
        isPublic: isPublic,
        leftScale: leftScale,
        rightScale: rightScale,
        link: link,
        linkMarker: linkMarker,
        isHidden: isHidden,
        cover: cover,
      ),
    );
  }

  // 判断查询位图是否包含指定字段
  static bool _has(int flags, int queryFlag) => (flags & queryFlag) != 0;

  // 读取四字节卡片位置引用
  static CardLocationReference _readLocation(ByteCursor cursor) {
    return CardLocationReference(
      controller: cursor.readUint8(),
      location: cursor.readUint8(),
      sequence: cursor.readUint8(),
      position: cursor.readUint8(),
    );
  }

  // 读取带数量头的卡片位置列表
  static List<CardLocationReference> _readLocations(
    ByteCursor cursor,
    String label,
  ) {
    final count = cursor.readUint32Le();
    _validateCount(count, cursor.remaining, 4, label);
    return List<CardLocationReference>.generate(
      count,
      (_) => _readLocation(cursor),
      growable: false,
    );
  }

  // 读取带数量头的卡片密码列表
  static List<int> _readCodes(ByteCursor cursor, String label) {
    final count = cursor.readUint32Le();
    _validateCount(count, cursor.remaining, 4, label);
    return List<int>.generate(
      count,
      (_) => cursor.readUint32Le() & 0x7fffffff,
      growable: false,
    );
  }

  // 读取卡片指示物类型及数量
  static Map<int, int> _readCounters(ByteCursor cursor) {
    final count = cursor.readUint32Le();
    _validateCount(count, cursor.remaining, 4, '指示物');
    final result = <int, int>{};
    for (var index = 0; index < count; index++) {
      result[cursor.readUint16Le()] = cursor.readUint16Le();
    }
    return result;
  }

  // 验证变长列表不会越过当前查询分块
  static void _validateCount(
    int count,
    int remaining,
    int itemBytes,
    String label,
  ) {
    if (count > remaining ~/ itemBytes) {
      throw YgoProtocolException(
        '$label数量越界 count=$count remaining=$remaining',
      );
    }
  }
}
