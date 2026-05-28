// ChatState — UI 状态持有者（v0.0.3 重构）。
//
// 所有 P2P 业务逻辑已迁移到 Rust justtalk-core 引擎。
// ChatState 只负责：持有 UI 数据、监听引擎事件、调用 notifyListeners。
//
// 公开接口保持不变，确保 UI 页面无需修改。

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/engine_bridge.dart' show EngineBridge, P2pEventData, P2pEventType, ConnectionPhase;
export '../services/engine_bridge.dart' show ConnectionPhase;

// ── 数据模型（UI 层使用）──

class ChatMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final bool isMine;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.timestamp,
    required this.isMine,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'content': content,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'isMine': isMine,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        content: json['content'] as String,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        isMine: json['isMine'] as bool,
      );
}

class Contact {
  final String peerId;
  final String displayName;
  final bool online;
  final DateTime? lastSeen;

  Contact({
    required this.peerId,
    required this.displayName,
    this.online = false,
    this.lastSeen,
  });

  String get initials {
    if (displayName.isEmpty) return '?';
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) return parts[0][0] + parts[1][0];
    return displayName[0];
  }

  Contact copyWith({String? displayName, bool? online, DateTime? lastSeen}) {
    return Contact(
      peerId: peerId,
      displayName: displayName ?? this.displayName,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'displayName': displayName,
        'online': online,
        'lastSeen': lastSeen?.millisecondsSinceEpoch,
      };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        peerId: json['peerId'] as String,
        displayName: json['displayName'] as String,
        online: json['online'] as bool? ?? false,
        lastSeen: json['lastSeen'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int)
            : null,
      );
}

// ── ChatState ──

class ChatState extends ChangeNotifier {
  static const _uuid = Uuid();

  // ── 引擎 ──
  late final EngineBridge _engine;

  // ── UI 状态 ──
  final List<Contact> _contacts = [];
  final Map<String, List<ChatMessage>> _messages = {};
  String _activeContactId = '';
  String _signalingServer = 'ws://localhost:3000/ws';
  bool _notificationsEnabled = true;
  bool _autoConnect = false;
  String? _lastError;
  String? _pendingAnswerCode;

  /// 当有人扫码配对时回调（HomePage 设置此回调）
  void Function(String peerId, String displayName)? onPairedFromQr;

  // ── 订阅 ──
  StreamSubscription<P2pEventData>? _eventSub;
  Timer? _pollTimer;

  ChatState() {
    _engine = EngineBridge();
    _eventSub = _engine.eventStream.listen(_onEngineEvent);
  }

  /// 初始化引擎（加载 Rust FFI 库）
  Future<void> init(String storagePath) async {
    await _engine.init(storagePath);
    // 定期轮询 Rust 引擎（每 100ms 拉取事件和命令）
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _engine.tick();
    });
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════
  // 引擎事件处理
  // ══════════════════════════════════════════════════════════

  void _onEngineEvent(P2pEventData event) {
    switch (event.type) {
      case P2pEventType.messageReceived:
        final d = event.data;
        final msg = ChatMessage(
          id: d['message_id'] as String? ?? _uuid.v4(),
          senderId: d['sender_id'] as String? ?? '',
          content: d['content'] as String? ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (d['timestamp_ms'] as num?)?.toInt() ??
                  DateTime.now().millisecondsSinceEpoch),
          isMine: false,
        );
        final peerId = d['peer_id'] as String? ?? '';
        _messages.putIfAbsent(peerId, () => []);
        _messages[peerId]!.add(msg);
        notifyListeners();
        break;

      case P2pEventType.connectionStateChanged:
        final peerId = event.data['peer_id'] as String? ?? '';
        final connected = event.data['connected'] as bool? ?? false;
        final idx = _contacts.indexWhere((c) => c.peerId == peerId);
        if (idx >= 0) {
          _contacts[idx] = _contacts[idx].copyWith(
            online: connected,
            lastSeen: connected ? null : DateTime.now(),
          );
        }
        notifyListeners();
        break;

      case P2pEventType.connectionPhaseChanged:
        notifyListeners();
        break;

      case P2pEventType.signalingStateChanged:
        notifyListeners();
        break;

      case P2pEventType.error:
        _lastError = event.data['message'] as String?;
        notifyListeners();
        break;

      case P2pEventType.pairConnected:
        final peerId = event.data['peer_id'] as String? ?? '';
        final displayName = event.data['display_name'] as String? ?? peerId;
        if (!_contacts.any((c) => c.peerId == peerId)) {
          _contacts.add(
              Contact(peerId: peerId, displayName: displayName, online: false));
        }
        _activeContactId = peerId;
        onPairedFromQr?.call(peerId, displayName);
        notifyListeners();
        break;

      case P2pEventType.contactUpdated:
        final peerId = event.data['peer_id'] as String? ?? '';
        final name = event.data['display_name'] as String? ?? '';
        final online = event.data['online'] as bool? ?? false;
        final idx = _contacts.indexWhere((c) => c.peerId == peerId);
        if (idx >= 0) {
          _contacts[idx] =
              _contacts[idx].copyWith(displayName: name, online: online);
        }
        notifyListeners();
        break;

      case P2pEventType.signalingConnecting:
        notifyListeners();
        break;
    }
  }

  // ══════════════════════════════════════════════════════════
  // Getters（公开接口不变）
  // ══════════════════════════════════════════════════════════

  String get myPeerId => _engine.myPeerId;
  String get displayName => _engine.displayName;
  bool get signalingConnected => _engine.signalingConnected;
  bool get signalingConnecting => _engine.signalingConnecting;
  String? get lastError => _lastError;
  String get signalingServer => _signalingServer;
  String get activeContactId => _activeContactId;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get autoConnect => _autoConnect;
  List<Contact> get contacts => List.unmodifiable(_contacts);
  String? get pendingAnswerCode => _pendingAnswerCode;

  ConnectionPhase getPeerPhase(String peerId) => _engine.getPeerPhase(peerId);
  bool isPeerConnected(String peerId) =>
      _engine.getPeerPhase(peerId) == ConnectionPhase.connected;
  List<ChatMessage> getMessages(String contactId) =>
      _messages[contactId] ?? [];
  Contact? getContact(String peerId) {
    try {
      return _contacts.firstWhere((c) => c.peerId == peerId);
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════
  // Mutators（委托给引擎）
  // ══════════════════════════════════════════════════════════

  void setDisplayName(String name) {
    _engine.setDisplayName(name);
    notifyListeners();
  }

  void setNotificationsEnabled(bool v) {
    _notificationsEnabled = v;
    notifyListeners();
  }

  void setAutoConnect(bool v) {
    _autoConnect = v;
    notifyListeners();
  }

  void setSignalingServer(String url) {
    _signalingServer = url;
    notifyListeners();
  }

  void setActiveContact(String peerId) {
    _activeContactId = peerId;
    _engine.setActiveContact(peerId);
    notifyListeners();
  }

  void addContact(Contact contact) {
    final idx = _contacts.indexWhere((c) => c.peerId == contact.peerId);
    if (idx >= 0) {
      _contacts[idx] = contact;
    } else {
      _contacts.add(contact);
    }
    notifyListeners();
  }

  void removeContact(String peerId) {
    _contacts.removeWhere((c) => c.peerId == peerId);
    _messages.remove(peerId);
    notifyListeners();
  }

  void addMessage(String contactId, ChatMessage message) {
    _messages.putIfAbsent(contactId, () => []);
    _messages[contactId]!.add(message);
    notifyListeners();
  }

  void clearPendingAnswer() {
    _pendingAnswerCode = null;
    _engine.clearPendingAnswer();
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════
  // 委托给引擎的方法
  // ══════════════════════════════════════════════════════════

  Future<void> connectToSignaling() async {
    await _engine.connectSignaling();
    notifyListeners();
  }

  Future<void> connectToPeer(String peerId) async {
    await _engine.connectToPeer(peerId);
  }

  Future<PairingCode> generatePairingCode() async {
    final encoded = await _engine.generatePairingCode();
    return PairingCode(encoded: encoded);
  }

  Future<void> acceptPairingCode(String code) async {
    _lastError = null;
    try {
      await _engine.acceptPairingCode(code);
    } catch (e) {
      _lastError = '处理连接码失败: $e';
    }
    notifyListeners();
  }

  void sendChatMessage(String contactId, String text) {
    final msg = ChatMessage(
      id: _uuid.v4(),
      senderId: myPeerId,
      content: text,
      timestamp: DateTime.now(),
      isMine: true,
    );
    addMessage(contactId, msg);
    _engine.sendMessage(contactId, text);
  }

  Future<void> handleConnectionCode(String code) async {
    if (code.startsWith('JTC2:')) {
      await acceptPairingCode(code);
      return;
    }
    if (code.startsWith('JTC1:')) {
      _lastError = 'JTC1 手动交换已在 v0.0.3 移除，请使用 JTC2 扫码配对';
    } else {
      _lastError = '无效的连接码格式';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _eventSub?.cancel();
    _engine.dispose();
    super.dispose();
  }
}

// ── 重新导出引擎类型供 UI 页面使用 ──
// ConnectionPhase 已由 engine_bridge.dart 导出，通过 chat_state.dart 透传

/// JTC2 过期异常（保留供 UI 层使用）
class PairingCodeExpiredException implements Exception {
  final int elapsedSeconds;
  PairingCodeExpiredException(this.elapsedSeconds);

  @override
  String toString() => '二维码已过期（已过 $elapsedSeconds 秒），请刷新后重试';
}

/// JTC2 配对码（薄模型，UI 层使用）
class PairingCode {
  static const expirySeconds = 300;
  final String encoded;
  final DateTime createdAt;

  PairingCode({required this.encoded, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt).inSeconds > expirySeconds;

  int get remainingSeconds =>
      expirySeconds - DateTime.now().difference(createdAt).inSeconds;

  String encode() => encoded;
}

