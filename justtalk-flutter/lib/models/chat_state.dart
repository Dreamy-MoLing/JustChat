import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../services/p2p_service.dart';

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
}

class ChatState extends ChangeNotifier {
  String _myPeerId = '';
  final List<Contact> _contacts = [];
  final Map<String, List<ChatMessage>> _messages = {};
  String _activeContactId = '';

  // ── Settings ──
  String _displayName = '我';
  bool _notificationsEnabled = true;
  bool _autoConnect = false;
  String _signalingServer = 'ws://localhost:3000/ws';

  // ── Connection state ──
  final Map<String, bool> _peerConnectionStates = {};
  bool _signalingConnected = false;
  String? _lastError;

  // ── P2P Service ──
  late final P2pService _p2pService;
  static const _uuid = Uuid();
  String? _pendingManualPeerId;

  /// Pending answer code from an incoming connection code (for UI display).
  String? _pendingAnswerCode;

  ChatState() {
    _myPeerId = _generateShortId();
    _p2pService = P2pService();
    _p2pService.onDataReceived = _onPeerMessage;
    _p2pService.onConnectionStateChanged = _onConnectionChanged;
    _p2pService.onError = _onP2pError;
  }

  String _generateShortId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'peer_${now.toRadixString(36)}';
  }

  // ── Getters ──
  String get myPeerId => _myPeerId;
  String get displayName => _displayName;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get autoConnect => _autoConnect;
  String get signalingServer => _signalingServer;
  List<Contact> get contacts => List.unmodifiable(_contacts);
  String get activeContactId => _activeContactId;
  bool get signalingConnected => _signalingConnected;
  String? get lastError => _lastError;

  bool isPeerConnected(String peerId) => _peerConnectionStates[peerId] ?? false;

  String? get pendingAnswerCode => _pendingAnswerCode;

  void clearPendingAnswer() {
    _pendingAnswerCode = null;
    notifyListeners();
  }

  // ── Mutators ──
  void setMyPeerId(String id) {
    _myPeerId = id;
    notifyListeners();
  }

  void setDisplayName(String name) {
    _displayName = name;
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

  List<ChatMessage> getMessages(String contactId) {
    return _messages[contactId] ?? [];
  }

  Contact? getContact(String peerId) {
    try {
      return _contacts.firstWhere((c) => c.peerId == peerId);
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // P2P Integration
  // ══════════════════════════════════════════════════════════════════════

  void _onPeerMessage(String peerId, String text) {
    final msg = ChatMessage(
      id: _uuid.v4(),
      senderId: peerId,
      content: text,
      timestamp: DateTime.now(),
      isMine: false,
    );
    addMessage(peerId, msg);
  }

  void _onConnectionChanged(String peerId, bool connected) {
    if (peerId == '__signaling__') {
      _signalingConnected = connected;
    } else {
      _peerConnectionStates[peerId] = connected;
      // Update contact online status.
      final idx = _contacts.indexWhere((c) => c.peerId == peerId);
      if (idx >= 0) {
        _contacts[idx] = _contacts[idx].copyWith(
          online: connected,
          lastSeen: connected ? null : DateTime.now(),
        );
      }
    }
    notifyListeners();
  }

  void _onP2pError(String error) {
    _lastError = error;
    notifyListeners();
  }

  /// Send a message: store locally + send via P2P.
  void sendChatMessage(String contactId, String text) {
    final msg = ChatMessage(
      id: _uuid.v4(),
      senderId: _myPeerId,
      content: text,
      timestamp: DateTime.now(),
      isMine: true,
    );
    addMessage(contactId, msg);
    _p2pService.sendMessage(text, contactId);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Signaling server mode
  // ══════════════════════════════════════════════════════════════════════

  /// Connect to the signaling server.
  Future<void> connectToSignaling() async {
    try {
      await _p2pService.connectSignaling(_signalingServer, _myPeerId, '');
      _lastError = null;
    } catch (e) {
      _lastError = 'Failed to connect to signaling server: $e';
      notifyListeners();
    }
  }

  /// Connect to a peer via signaling server.
  Future<void> connectToPeer(String peerId) async {
    try {
      await _p2pService.connect(peerId);
    } catch (e) {
      _lastError = 'Failed to connect to peer: $e';
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Manual SDP exchange mode (zero server)
  // ══════════════════════════════════════════════════════════════════════

  /// Generate a connection code to share with the other peer.
  Future<String> generateConnectionCode() async {
    final peerId = 'peer_${_uuid.v4().substring(0, 8)}';
    _pendingManualPeerId = peerId;

    // 预建联系人，连接成功后自动变为在线
    final contactName = '好友 ${peerId.substring(5, 11)}';
    addContact(Contact(peerId: peerId, displayName: contactName, online: false));
    setActiveContact(peerId);

    return await _p2pService.generateConnectionCode(peerId);
  }

  /// Accept a connection code from the other peer, returns the answer code.
  Future<String> acceptConnectionCode(String code) async {
    final peerId = 'peer_${_uuid.v4().substring(0, 8)}';
    final answer = await _p2pService.acceptConnectionCode(peerId, code);

    // 预建联系人 + 记录 peerId，通知 UI 显示应答码
    _pendingManualPeerId = peerId;
    _pendingAnswerCode = answer;
    final contactName = '好友 ${peerId.substring(5, 11)}';
    addContact(Contact(peerId: peerId, displayName: contactName, online: false));
    setActiveContact(peerId);
    _lastError = null;
    notifyListeners();

    return answer;
  }

  /// Accept an answer code to complete the connection.
  Future<void> acceptAnswerCode(String answerCode) async {
    final peerId = _pendingManualPeerId;
    if (peerId == null) {
      throw StateError('没有等待中的连接。请先生成连接码或接受对方的连接码。');
    }
    await _p2pService.acceptAnswerCode(peerId, answerCode);
    _pendingManualPeerId = null;
    _pendingAnswerCode = null;

    // 标记联系人已在线
    final idx = _contacts.indexWhere((c) => c.peerId == peerId);
    if (idx >= 0) {
      _contacts[idx] = _contacts[idx].copyWith(online: true);
    }
    _lastError = null;
    notifyListeners();
  }

  /// Handle an incoming connection code (from deep link or share).
  /// Determines if it's an offer or answer, processes accordingly.
  Future<void> handleConnectionCode(String code) async {
    if (!code.startsWith('JTC1:')) return;

    try {
      final compressed = base64Url.decode(code.substring(5));
      final json = utf8.decode(zlib.decode(compressed));
      final data = jsonDecode(json) as Map<String, dynamic>;
      final sdpMap = data['sdp'] as Map<String, dynamic>;
      final sdpType = sdpMap['type'] as String;

      if (sdpType == 'offer') {
        // 收到 offer → 生成应答并用联系人保存状态
        await acceptConnectionCode(code);
      } else if (sdpType == 'answer') {
        // 收到 answer → 完成连接
        if (_pendingManualPeerId == null) {
          _lastError = '没有等待中的连接。请先生成连接码。';
          notifyListeners();
          return;
        }
        await acceptAnswerCode(code);
      }
      notifyListeners();
    } catch (e) {
      _lastError = '处理连接码失败: $e';
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Cleanup
  // ══════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _p2pService.dispose();
    super.dispose();
  }
}
