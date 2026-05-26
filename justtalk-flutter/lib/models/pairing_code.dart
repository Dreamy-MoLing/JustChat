import 'dart:convert';
import 'dart:math';

/// 二维码已过期异常
class PairingCodeExpiredException implements Exception {
  final int elapsedSeconds;
  PairingCodeExpiredException(this.elapsedSeconds);

  @override
  String toString() => '二维码已过期（已过 $elapsedSeconds 秒），请刷新后重试';
}

/// JTC2 pairing token format (v4).
///
/// 结构: JTC2:base64(version(1) + token(16) + timestamp(8) + peerIdLen(1) + peerId(N) + nameLen(1) + name(N) + sigAddrLen(1) + sigAddr(N))
///
/// v4 新增:
///   - createdAt 时间戳（8字节 int64 big-endian，毫秒），扫码端校验 5 分钟有效期
///
/// 兼容性: decode 支持 v2/v3（旧版本无时间戳，跳过过期校验）
class PairingCode {
  static const expirySeconds = 300; // 5 分钟

  final String token;
  final String peerId;
  final String displayName;
  final String? signalingServer;
  final DateTime createdAt;

  PairingCode({
    required this.token,
    required this.peerId,
    required this.displayName,
    this.signalingServer,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 是否已过期
  bool get isExpired {
    return DateTime.now().difference(createdAt).inSeconds > expirySeconds;
  }

  /// 距过期还剩多少秒（负数表示已过期）
  int get remainingSeconds {
    return expirySeconds - DateTime.now().difference(createdAt).inSeconds;
  }

  /// Encode to JTC2 string (v4).
  String encode() {
    final bytes = <int>[];
    // Version byte: 4
    bytes.add(4);
    // Token (16 bytes).
    bytes.addAll(utf8.encode(token));
    // Timestamp: 8 bytes big-endian (milliseconds since epoch).
    final ts = createdAt.millisecondsSinceEpoch;
    for (var i = 7; i >= 0; i--) {
      bytes.add((ts >> (i * 8)) & 0xFF);
    }
    // Peer ID: length byte + UTF-8 bytes.
    final peerBytes = utf8.encode(peerId);
    bytes.add(peerBytes.length);
    bytes.addAll(peerBytes);
    // Display name: length byte + UTF-8 bytes.
    final nameBytes = utf8.encode(displayName);
    bytes.add(nameBytes.length);
    bytes.addAll(nameBytes);
    // Signaling server (optional): length byte + bytes.
    if (signalingServer != null && signalingServer!.isNotEmpty) {
      final sigBytes = utf8.encode(signalingServer!);
      bytes.add(sigBytes.length);
      bytes.addAll(sigBytes);
    } else {
      bytes.add(0);
    }
    return 'JTC2:${base64Url.encode(bytes)}';
  }

  /// Decode from JTC2 string (supports v2/v3/v4).
  ///
  /// v4 含时间戳，解码后自动校验 5 分钟有效期。
  /// v2/v3 无时间戳，跳过过期校验（向后兼容）。
  factory PairingCode.decode(String code) {
    if (!code.startsWith('JTC2:')) {
      throw FormatException('Not a JTC2 code');
    }
    final raw = base64Url.decode(code.substring(5));
    if (raw.isEmpty) throw FormatException('Empty token data');

    final version = raw[0];
    if (version < 2 || version > 4) {
      throw FormatException('Unsupported version: $version');
    }

    var pos = 1;

    // Token: 16 bytes.
    const tokenLen = 16;
    if (pos + tokenLen > raw.length) throw FormatException('Truncated token');
    final token = utf8.decode(raw.sublist(pos, pos + tokenLen));
    pos += tokenLen;

    // Timestamp (v4+): 8 bytes big-endian int64.
    DateTime? createdAt;
    if (version >= 4) {
      if (pos + 8 > raw.length) throw FormatException('Truncated timestamp');
      int ts = 0;
      for (var i = 0; i < 8; i++) {
        ts = (ts << 8) | raw[pos + i];
      }
      pos += 8;
      createdAt = DateTime.fromMillisecondsSinceEpoch(ts);

      // 校验 5 分钟有效期
      final elapsed = DateTime.now().difference(createdAt).inSeconds;
      if (elapsed > expirySeconds) {
        throw PairingCodeExpiredException(elapsed);
      }
    }

    // Peer ID (v3+) or fallback.
    String peerId;
    if (version >= 3) {
      if (pos >= raw.length) throw FormatException('Missing peerId length');
      final peerLen = raw[pos];
      pos++;
      if (pos + peerLen > raw.length) throw FormatException('Truncated peerId');
      peerId = utf8.decode(raw.sublist(pos, pos + peerLen));
      pos += peerLen;
    } else {
      peerId = 'pair_$token';
    }

    // Display name.
    if (pos >= raw.length) throw FormatException('Missing name length');
    final nameLen = raw[pos];
    pos++;
    if (pos + nameLen > raw.length) throw FormatException('Truncated name');
    final displayName = utf8.decode(raw.sublist(pos, pos + nameLen));
    pos += nameLen;

    // Signaling server.
    String? signalingServer;
    if (pos < raw.length) {
      final sigLen = raw[pos];
      pos++;
      if (sigLen > 0 && pos + sigLen <= raw.length) {
        signalingServer = utf8.decode(raw.sublist(pos, pos + sigLen));
      }
    }

    return PairingCode(
      token: token,
      peerId: peerId,
      displayName: displayName,
      signalingServer: signalingServer,
      createdAt: createdAt,
    );
  }

  static String _randomToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return utf8.decode(bytes);
  }

  factory PairingCode.create(String peerId, String displayName, {String? signalingServer}) {
    return PairingCode(
      token: _randomToken(),
      peerId: peerId,
      displayName: displayName,
      signalingServer: signalingServer,
    );
  }
}
