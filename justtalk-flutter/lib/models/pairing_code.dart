import 'dart:convert';
import 'dart:math';

/// JTC2 pairing token format.
///
/// QR 码只包含短令牌 + 昵称，实现无摩擦扫码连接。
/// 结构: JTC2:base64(version(1) + token(16) + nameLen(1) + name(N) + sigAddrLen(1) + sigAddr(N))
///
/// 扫码端解码后立即创建联系人（显示对方昵称），
/// 然后通过信令服务器完成 WebRTC 协商。
///
/// 令牌总长度 ≈ 40~120 字节 → QR Version 4~5，普通相机可扫。
class PairingCode {
  final String token;
  final String displayName;
  final String? signalingServer;

  PairingCode({
    required this.token,
    required this.displayName,
    this.signalingServer,
  });

  /// Encode to JTC2 string.
  String encode() {
    final bytes = <int>[];
    // Version byte.
    bytes.add(2);
    // Token (16 random bytes).
    bytes.addAll(utf8.encode(token));
    // Display name: length byte + UTF-8 bytes.
    final nameBytes = utf8.encode(displayName);
    bytes.add(nameBytes.length); // max 255
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

  /// Decode from JTC2 string.
  factory PairingCode.decode(String code) {
    if (!code.startsWith('JTC2:')) {
      throw FormatException('Not a JTC2 code');
    }
    final raw = base64Url.decode(code.substring(5));
    if (raw.isEmpty) throw FormatException('Empty token data');
    final version = raw[0];
    if (version != 2) throw FormatException('Unsupported version: $version');
    var pos = 1;
    // Token: 16 bytes UTF-8 string.
    const tokenLen = 16;
    if (pos + tokenLen > raw.length) throw FormatException('Truncated token');
    final token = utf8.decode(raw.sublist(pos, pos + tokenLen));
    pos += tokenLen;
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
      displayName: displayName,
      signalingServer: signalingServer,
    );
  }

  /// Generate a new random token.
  static String _randomToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return utf8.decode(bytes);
  }

  /// Create a new PairingCode with a random token and the given display name.
  factory PairingCode.create(String displayName, {String? signalingServer}) {
    return PairingCode(
      token: _randomToken(),
      displayName: displayName,
      signalingServer: signalingServer,
    );
  }
}
