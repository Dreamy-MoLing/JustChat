// EngineBridge — Dart↔Rust 引擎桥接层（v0.0.3 FFI 模式）。
//
// 通过 `dart:ffi` 调用 Rust justtalk-core 引擎的 C ABI 函数。
// 所有复杂类型通过 JSON 序列化跨 FFI 边界。

import 'dart:async';
import 'webrtc_adapter.dart';
import 'native_ffi.dart';

/// P2P 事件类型
enum P2pEventType {
  messageReceived,
  connectionStateChanged,
  connectionPhaseChanged,
  signalingStateChanged,
  error,
  pairConnected,
  contactUpdated,
  signalingConnecting,
}

/// P2P 事件数据
class P2pEventData {
  final P2pEventType type;
  final Map<String, dynamic> data;
  P2pEventData({required this.type, required this.data});
}

/// 连接阶段
enum ConnectionPhase {
  idle,
  connecting,
  iceGathering,
  exchanging,
  connected,
  failed;

  /// 从 JSON 字符串解析
  static ConnectionPhase fromString(String s) {
    switch (s) {
      case 'idle':
        return ConnectionPhase.idle;
      case 'connecting':
        return ConnectionPhase.connecting;
      case 'iceGathering':
        return ConnectionPhase.iceGathering;
      case 'exchanging':
        return ConnectionPhase.exchanging;
      case 'connected':
        return ConnectionPhase.connected;
      case 'failed':
        return ConnectionPhase.failed;
      default:
        return ConnectionPhase.idle;
    }
  }
}

/// 引擎桥接（使用 Rust FFI）
class EngineBridge {
  final NativeEngine _native = NativeEngine();
  final WebrtcAdapter _adapter = WebrtcAdapter();

  final StreamController<P2pEventData> _eventController =
      StreamController<P2pEventData>.broadcast();

  Stream<P2pEventData> get eventStream => _eventController.stream;

  // ── 本地缓存（Rust 状态通过事件同步）──
  String _myPeerId = '';
  String _displayName = '我';
  bool _signalingConnected = false;
  bool _signalingConnecting = false;
  String? _lastError;
  String _activeContactId = '';
  final Map<String, ConnectionPhase> _peerPhases = {};
  String? _pendingAnswerCode;
  bool _initialized = false;

  EngineBridge() {
    _adapter.onCallback = (data) => _handleWebrtcCallback(data);
  }

  // ══════════════════════════════════════════════════════════
  // 初始化
  // ══════════════════════════════════════════════════════════

  /// 加载原生库并初始化引擎
  Future<void> init(String storagePath) async {
    _native.load();

    // 调用 Rust jt_engine_init
    final result = _native.init(storagePath);
    _myPeerId = result['peer_id'] as String? ?? '';
    _displayName = result['display_name'] as String? ?? '我';
    _initialized = true;
  }

  // ══════════════════════════════════════════════════════════
  // Getters
  // ══════════════════════════════════════════════════════════

  String get myPeerId =>
      _myPeerId.isNotEmpty ? _myPeerId : 'peer_loading';
  String get displayName => _displayName;
  bool get signalingConnected => _signalingConnected;
  bool get signalingConnecting => _signalingConnecting;
  String? get lastError => _lastError;
  String? get pendingAnswerCode => _pendingAnswerCode;
  String get activeContactId => _activeContactId;

  ConnectionPhase getPeerPhase(String peerId) =>
      _peerPhases[peerId] ?? ConnectionPhase.idle;

  void setActiveContact(String peerId) {
    _activeContactId = peerId;
    if (_initialized) {
      _native.call('set_active_contact', {'peer_id': peerId});
    }
  }

  void clearPendingAnswer() {
    _pendingAnswerCode = null;
  }

  // ══════════════════════════════════════════════════════════
  // 公开 API — 委托给 Rust jt_call()
  // ══════════════════════════════════════════════════════════

  Future<void> connectSignaling() async {
    _signalingConnecting = true;
    _emitEvent(P2pEventType.signalingConnecting, {});

    try {
      _native.call('connect_signaling');
      _signalingConnected = true;
      _signalingConnecting = false;
      _emitEvent(P2pEventType.signalingStateChanged, {'connected': true});
    } catch (e) {
      _signalingConnecting = false;
      _lastError = '信令连接失败: $e';
      _emitEvent(P2pEventType.error, {'message': _lastError!});
    }
  }

  Future<void> connectToPeer(String peerId) async {
    try {
      _native.call('connect_to_peer', {'peer_id': peerId});
    } catch (e) {
      _lastError = '连接 $peerId 失败: $e';
      _emitEvent(P2pEventType.error, {'message': _lastError!});
    }
  }

  Future<String> generatePairingCode() async {
    final result = _native.call('generate_pairing_code');
    return result['data']?['code'] as String? ?? '';
  }

  Future<void> acceptPairingCode(String code) async {
    _native.call('accept_pairing_code', {'code': code});
  }

  void sendMessage(String peerId, String text) {
    try {
      _native.call('send_message', {'peer_id': peerId, 'text': text});
    } catch (e) {
      _lastError = '发送失败: $e';
      _emitEvent(P2pEventType.error, {'message': _lastError!});
    }
  }

  void setDisplayName(String name) {
    _displayName = name;
    if (_initialized) {
      _native.call('set_display_name', {'name': name});
    }
  }

  void setSignalingServerUrl(String url) {
    if (_initialized) {
      _native.call('set_signaling_server', {'url': url});
    }
  }

  void setAutoConnect(bool enabled) {
    if (_initialized) {
      _native.call('set_auto_connect', {'enabled': enabled});
    }
  }

  void setNotificationsEnabled(bool enabled) {
    if (_initialized) {
      _native.call('set_notifications_enabled', {'enabled': enabled});
    }
  }

  /// 检查是否首次启动
  bool isFirstLaunch() {
    if (!_initialized) return true;
    try {
      final result = _native.call('get_settings', {'key': 'firstLaunchDone'});
      return result['data']?['value'] != 'true';
    } catch (_) {
      return true;
    }
  }

  /// 标记首次启动完成
  void setFirstLaunchDone() {
    if (_initialized) {
      _native.call('set_settings', {'key': 'firstLaunchDone', 'value': 'true'});
    }
  }

  /// 接受 JTC1 连接码（answer 侧）
  String? acceptConnectionCode(String code) {
    final result = _native.call('accept_connection_code', {'code': code});
    return result['data']?['peer_id'] as String?;
  }

  /// 获取已编码的 JTC1 应答码
  String? encodeJtc1Answer(String peerId) {
    final result = _native.call('encode_jtc1_answer', {'peer_id': peerId});
    return result['data']?['code'] as String?;
  }

  // ══════════════════════════════════════════════════════════
  // 事件轮询 — 定期调用
  // ══════════════════════════════════════════════════════════

  void tick() {
    if (!_initialized) return;

    // 让 Rust 引擎处理信令事件
    _native.call('tick');

    // 拉取 P2P 事件
    final events = _native.pollEvents();
    for (final e in events) {
      if (e is Map<String, dynamic>) {
        _dispatchEvent(e);
      }
    }

    // 拉取 WebRTC 命令
    final commands = _native.pollCommands();
    for (final cmd in commands) {
      if (cmd is Map<String, dynamic>) {
        _adapter.execute(WebrtcCommand.fromJson(cmd));
      }
    }
  }

  void _dispatchEvent(Map<String, dynamic> event) {
    final eventType = event['event'] as String?;
    if (eventType == null) return;

    switch (eventType) {
      case 'message_received':
        _emitEvent(P2pEventType.messageReceived, event);
      case 'connection_state_changed':
        final peerId = event['peer_id'] as String? ?? '';
        final connected = event['connected'] as bool? ?? false;
        if (connected) {
          _peerPhases[peerId] = ConnectionPhase.connected;
        } else {
          _peerPhases.remove(peerId);
        }
        _emitEvent(P2pEventType.connectionStateChanged, event);
      case 'connection_phase_changed':
        final peerId = event['peer_id'] as String? ?? '';
        final phase = event['phase'] as String? ?? '';
        _peerPhases[peerId] = ConnectionPhase.fromString(phase);
        _emitEvent(P2pEventType.connectionPhaseChanged, event);
      case 'signaling_state_changed':
        _signalingConnected = event['connected'] as bool? ?? false;
        _emitEvent(P2pEventType.signalingStateChanged, event);
      case 'error':
        _lastError = event['message'] as String?;
        _emitEvent(P2pEventType.error, event);
      case 'pair_connected':
        _emitEvent(P2pEventType.pairConnected, event);
      case 'contact_updated':
        _emitEvent(P2pEventType.contactUpdated, event);
      case 'signaling_connecting':
        _emitEvent(P2pEventType.signalingConnecting, event);
    }
  }

  void _emitEvent(P2pEventType type, Map<String, dynamic> data) {
    _eventController.add(P2pEventData(type: type, data: data));
  }

  // ══════════════════════════════════════════════════════════
  // WebRTC 回调处理（来自 WebrtcAdapter）
  // ══════════════════════════════════════════════════════════

  void _handleWebrtcCallback(Map<String, dynamic> data) {
    final callback = data['callback'] as String?;
    if (callback == null || !_initialized) return;

    // 将回调转发给 Rust 引擎
    final params = Map<String, dynamic>.from(data);
    params.remove('callback');
    _native.call(callback, params);

    final peerId = data['peer_id'] as String? ?? '';

    switch (callback) {
      case 'on_peer_connection_created':
        _peerPhases[peerId] = ConnectionPhase.connecting;
        _emitEvent(P2pEventType.connectionPhaseChanged, {
          'peer_id': peerId,
          'phase': 'connecting',
        });
      case 'on_local_description':
        _peerPhases[peerId] = ConnectionPhase.iceGathering;
      case 'on_ice_gathering_complete':
        _peerPhases[peerId] = ConnectionPhase.exchanging;
      case 'on_data_channel_open':
        _peerPhases[peerId] = ConnectionPhase.connected;
        _emitEvent(P2pEventType.connectionStateChanged, {
          'peer_id': peerId,
          'connected': true,
        });
      case 'on_data_channel_message':
        _emitEvent(P2pEventType.messageReceived, data);
      case 'on_ice_connection_state_change':
        final state = data['state'] as String? ?? '';
        if (state == 'failed' || state == 'disconnected') {
          _peerPhases[peerId] = ConnectionPhase.failed;
          _emitEvent(P2pEventType.connectionStateChanged, {
            'peer_id': peerId,
            'connected': false,
          });
        }
      case 'on_peer_connection_failed':
        _peerPhases[peerId] = ConnectionPhase.failed;
        _lastError = data['error'] as String?;
        _emitEvent(P2pEventType.error, {'message': _lastError ?? '连接失败'});
    }
  }

  Future<void> dispose() async {
    await _adapter.dispose();
    await _eventController.close();
  }
}
