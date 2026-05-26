import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 连接超时秒数
const connectionTimeoutSeconds = 15;

/// Connection mode for a peer.
enum ConnectionMode { signaling }

/// WebRTC 连接阶段——用于 UI 展示连接进度
enum ConnectionPhase {
  idle,           // 空闲
  connecting,     // 正在创建 PeerConnection
  iceGathering,   // 正在收集 ICE 候选
  exchanging,     // 正在交换 SDP
  connected,      // 已连接
  failed,         // 连接失败
}

class P2pService {
  WebSocketChannel? _channel;
  bool _signalingConnected = false;

  /// Per-peer data channels.
  final Map<String, RTCDataChannel> _dataChannels = {};

  /// Per-peer RTCPeerConnections.
  final Map<String, RTCPeerConnection> _peers = {};

  /// ICE candidates buffered before remote description is set.
  /// 关键：WebRTC 规定 addIceCandidate 必须在 setRemoteDescription 之后调用。
  /// 先到达的候选暂存于此，setRemoteDescription 完成后 flush。
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  /// ICE candidates for manual mode (JTC1).
  final Map<String, List<RTCIceCandidate>> _manualCandidates = {};

  /// Connection mode per peer.
  final Map<String, ConnectionMode> _connectionModes = {};

  /// Connection phase per peer — for UI status display.
  final Map<String, ConnectionPhase> _connectionPhases = {};

  /// 连接超时计时器，per peer
  final Map<String, Timer> _connectionTimers = {};

  /// My display name for JTC2 pairing codes.
  String myDisplayName = '我';

  // ── Callbacks ──

  void Function(String peerId, String message)? onDataReceived;
  void Function(String peerId, bool connected)? onConnectionStateChanged;
  void Function(String peerId, ConnectionPhase phase)? onConnectionPhase;
  void Function(String error)? onError;
  /// 收到配对请求时回调（被扫码方创建 B 的联系人）
  void Function(String peerId, String displayName)? onPairConnect;

  // ── Getters ──

  bool get isConnectedToSignaling => _signalingConnected;

  bool isPeerConnected(String peerId) => _dataChannels.containsKey(peerId);

  ConnectionPhase getPeerPhase(String peerId) =>
      _connectionPhases[peerId] ?? ConnectionPhase.idle;

  // ══════════════════════════════════════════════════════════════════════
  // JTC2: Pairing token exchange (信令服务器模式)
  // ══════════════════════════════════════════════════════════════════════

  /// 被扫码方——告知信令服务器："我接受配对，B 可通过 connect_via_pair 找到我"
  void registerPairIntent(String peerId) {
    if (_signalingConnected) {
      _sendSignal({
        'cmd': 'pair_intent',
        'peer_id': peerId,
        'display_name': myDisplayName,
      });
    }
  }

  /// 扫码方——告知信令服务器："我要连接 A"，然后等待 A 发 offer
  /// A 收到 pair_connect → _handlePairConnect → A 创建 offer → 通过信令传回
  Future<void> connectViaPairing(String remotePeerId, {String? remoteName}) async {
    _connectionModes[remotePeerId] = ConnectionMode.signaling;
    _setPhase(remotePeerId, ConnectionPhase.exchanging);

    if (!_signalingConnected) {
      _setPhase(remotePeerId, ConnectionPhase.failed);
      throw Exception('未连接到信令服务器，无法完成配对。请先确保信令服务器可访问。');
    }

    _sendSignal({
      'cmd': 'connect_via_pair',
      'target_peer_id': remotePeerId,
      'display_name': myDisplayName,
    });
    // 不在这里创建 PeerConnection。
    // 等 A 发来 sdp_offer 后，由 _handleSdpOffer 创建 answer-side PC。
  }

  // ══════════════════════════════════════════════════════════════════════
  // Signaling server connection
  // ══════════════════════════════════════════════════════════════════════

  /// 连接到信令服务器并注册本 peer
  Future<void> connectSignaling(String url, String peerId, String pubkey) async {
    final uri = Uri.parse(url);
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (data) {
        final msg = jsonDecode(data as String);
        _handleSignalingMessage(msg);
      },
      onDone: () {
        _signalingConnected = false;
        onConnectionStateChanged?.call('__signaling__', false);
      },
      onError: (e) {
        _signalingConnected = false;
        onError?.call('signaling error: $e');
      },
    );

    _sendSignal({'cmd': 'register', 'peer_id': peerId, 'pubkey': pubkey});
    _signalingConnected = true;
    onConnectionStateChanged?.call('__signaling__', true);
  }

  void _sendSignal(Map<String, dynamic> cmd) {
    _channel?.sink.add(jsonEncode(cmd));
  }

  /// 信令消息分发
  void _handleSignalingMessage(Map<String, dynamic> msg) {
    final cmd = msg['cmd'] as String?;
    switch (cmd) {
      case 'pong':
        break;
      case 'registered':
        break;
      case 'peer_online':
        onConnectionStateChanged?.call(msg['peer_id'] as String, true);
        break;
      case 'peer_offline':
        onConnectionStateChanged?.call(msg['peer_id'] as String, false);
        break;
      case 'connect_req':
        _handleIncomingConnection(msg['from_id'] as String);
        break;
      case 'pair_connect':
        // 被扫码方收到配对请求 → 创建 offer
        _handlePairConnect(msg);
        break;
      case 'sdp_offer':
        // 收到 SDP offer 或 answer
        _handleSdpOffer(msg);
        break;
      case 'ice_candidate':
        // Trickle ICE：接收对端候选地址
        _handleIceCandidate(msg);
        break;
      case 'accept_connect':
        break;
      case 'error':
        onError?.call(msg['message'] as String? ?? 'unknown error');
        break;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // WebRTC 状态机 — 核心流程
  // ══════════════════════════════════════════════════════════════════════
  //
  // Offer 侧 (A，被扫码方)：
  //   1. createPeerConnection
  //   2. createDataChannel          ← 必须在 createOffer 之前
  //   3. createOffer
  //   4. setLocalDescription(offer) ← 触发 ICE 收集
  //   5. 等待 ICE 收集完成（半 Trickle：收集完再发 offer）
  //   6. 发送 offer（含 ICE 候选）
  //   7. 接收 answer → setRemoteDescription(answer)
  //   8. DataChannel open → P2P 连接建立
  //
  // Answer 侧 (B，扫码方)：
  //   1. 接收 offer → createPeerConnection（如尚不存在）
  //   2. setRemoteDescription(offer)
  //   3. flush 暂存的 ICE 候选（Trickle: 候选可能在 offer 之前到达）
  //   4. createAnswer
  //   5. setLocalDescription(answer)
  //   6. 发送 answer
  //   7. onDataChannel 回调 → P2P 连接建立

  /// Offer 侧 (被扫码方 A)：收到 B 的配对请求，创建 offer 并发给 B
  ///
  /// 流程：收到 pair_connect → 创建 PC+DataChannel → createOffer →
  ///       setLocalDescription → 等 ICE 收集 → 发送含候选的 offer
  Future<void> _handlePairConnect(Map<String, dynamic> msg) async {
    final fromId = msg['from_id'] as String;
    final displayName = msg['display_name'] as String? ?? fromId;
    _connectionModes[fromId] = ConnectionMode.signaling;
    _setPhase(fromId, ConnectionPhase.connecting);

    // 通知 ChatState：有人扫码配对，创建 B 的联系人
    onPairConnect?.call(fromId, displayName);

    // ── 启动 15 秒连接超时计时器 ──
    _startConnectionTimeout(fromId);

    try {
      final pc = await _createOfferPeerConnection(fromId);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _setPhase(fromId, ConnectionPhase.iceGathering);

      await _waitForIceGathering(pc, timeoutSeconds: 5);
      _setPhase(fromId, ConnectionPhase.exchanging);

      final localDesc = await pc.getLocalDescription();
      if (localDesc == null) {
        _onConnectionTimeout(fromId, '无法获取本地 SDP');
        return;
      }

      _sendSignal({'cmd': 'accept_connect', 'target_id': fromId});
      _sendSignal({
        'cmd': 'sdp_offer',
        'target_id': fromId,
        'sdp': jsonEncode(localDesc.toMap()),
      });
    } catch (e) {
      _onConnectionTimeout(fromId, '配对连接失败: $e');
    }
  }

  /// 主动连接（用户点击"连接"按钮时调用）
  Future<void> connect(String targetId) async {
    _connectionModes[targetId] = ConnectionMode.signaling;
    _setPhase(targetId, ConnectionPhase.connecting);
    _startConnectionTimeout(targetId);

    try {
      _sendSignal({'cmd': 'connect', 'target_id': targetId});

      final pc = await _createOfferPeerConnection(targetId);
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _setPhase(targetId, ConnectionPhase.iceGathering);
      await _waitForIceGathering(pc, timeoutSeconds: 5);
      _setPhase(targetId, ConnectionPhase.exchanging);

      final localDesc = await pc.getLocalDescription();
      _sendSignal({
        'cmd': 'sdp_offer',
        'target_id': targetId,
        'sdp': jsonEncode(localDesc?.toMap()),
      });
    } catch (e) {
      _onConnectionTimeout(targetId, 'Connect failed: $e');
    }
  }

  /// 收到连接请求
  Future<void> _handleIncomingConnection(String fromId) async {
    _sendSignal({'cmd': 'accept_connect', 'target_id': fromId});
  }

  /// Answer 侧 (扫码方 B)：收到 A 的 SDP offer 或 answer
  ///
  /// offer 分支：创建 answer-side PC → setRemoteDescription →
  ///             flush 暂存 ICE → createAnswer → setLocalDescription → 发回 answer
  /// answer 分支（A 收到 B 的 answer）：setRemoteDescription → 连接完成
  Future<void> _handleSdpOffer(Map<String, dynamic> msg) async {
    final fromId = msg['from_id'] as String;
    final sdp = jsonDecode(msg['sdp'] as String);
    final sdpType = sdp['type'] as String;

    try {
      // ── 如果是 offer：创建 answer-side PC ──
      if (sdpType == 'offer') {
        if (!_peers.containsKey(fromId)) {
          await _createAnswerPeerConnection(fromId);
          _setPhase(fromId, ConnectionPhase.connecting);
        }

        // ── setRemoteDescription(offer) ──
        // WebRTC 规定：必须先设 remote description，然后才能 addIceCandidate
        await _peers[fromId]!.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'], sdpType),
        );
        _setPhase(fromId, ConnectionPhase.iceGathering);

        // ── flush 暂存的 ICE 候选 ──
        // Trickle ICE：候选可能在 offer 之前到达，暂存在 _pendingCandidates
        // 现在 remote description 已设置，可以安全添加
        final pending = _pendingCandidates.remove(fromId);
        if (pending != null) {
          for (final c in pending) {
            await _peers[fromId]!.addCandidate(c);
          }
        }

        // ── createAnswer ──
        final answer = await _peers[fromId]!.createAnswer();

        // ── setLocalDescription(answer) ──
        await _peers[fromId]!.setLocalDescription(answer);
        _setPhase(fromId, ConnectionPhase.exchanging);

        // 等待 ICE 收集（让 answer 也含候选）
        await _waitForIceGathering(_peers[fromId]!, timeoutSeconds: 5);

        final localDesc = await _peers[fromId]!.getLocalDescription();
        _sendSignal({
          'cmd': 'sdp_offer',
          'target_id': fromId,
          'sdp': jsonEncode(localDesc?.toMap()),
        });
      } else {
        // ── 收到 answer（offer 侧 A）：setRemoteDescription(answer) ──
        if (!_peers.containsKey(fromId)) {
          onError?.call('No peer connection for answer from $fromId');
          return;
        }

        await _peers[fromId]!.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'], sdpType),
        );

        // flush 暂存的 ICE 候选
        final pending = _pendingCandidates.remove(fromId);
        if (pending != null) {
          for (final c in pending) {
            await _peers[fromId]!.addCandidate(c);
          }
        }
      }
    } catch (e) {
      _setPhase(fromId, ConnectionPhase.failed);
      onError?.call('SDP exchange failed for $fromId: $e');
    }
  }

  /// Trickle ICE：接收对端 ICE 候选
  ///
  /// 候选可能在任何时候到达：
  /// - 如果 remote description 已设置 → 直接 addIceCandidate
  /// - 如果还没收到 offer → 暂存到 _pendingCandidates，等 offer 到达后 flush
  Future<void> _handleIceCandidate(Map<String, dynamic> msg) async {
    final fromId = msg['from_id'] as String;
    final candidate = jsonDecode(msg['candidate'] as String);
    final ice = RTCIceCandidate(
      candidate['candidate'],
      candidate['sdpMid'],
      candidate['sdpMLineIndex'],
    );

    if (_peers[fromId]?.getRemoteDescription() != null) {
      // remote description 已设置，直接添加
      await _peers[fromId]!.addCandidate(ice);
    } else {
      // 还没收到 offer，暂存等待
      _pendingCandidates.putIfAbsent(fromId, () => []).add(ice);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // JTC1: Manual SDP exchange (零服务器降级方案)
  // ══════════════════════════════════════════════════════════════════════

  /// 生成连接码（offer 侧）
  /// 创建 PC → createOffer → setLocalDescription → 等 ICE 收集 → 打包 SDP+候选
  Future<String> generateConnectionCode(String peerId) async {
    final pc = await _createOfferPeerConnection(peerId);
    _setPhase(peerId, ConnectionPhase.connecting);

    // WebRTC 状态机：offer 侧
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _setPhase(peerId, ConnectionPhase.iceGathering);

    // JTC1 无信令通道做 Trickle，必须等 ICE 收集完成
    await _waitForIceGathering(pc);

    final candidates = (_manualCandidates.remove(peerId) ?? [])
        .map((c) => c.toMap())
        .toList();

    final localDesc = await pc.getLocalDescription();
    final codeData = {
      'sdp': localDesc?.toMap(),
      'candidates': candidates,
    };

    final json = jsonEncode(codeData);
    final compressed = zlib.encode(utf8.encode(json));
    return 'JTC1:${base64Url.encode(compressed)}';
  }

  /// 接受连接码（answer 侧）
  Future<String> acceptConnectionCode(String peerId, String code) async {
    if (!code.startsWith('JTC1:')) {
      throw FormatException('Invalid connection code format');
    }

    final compressed = base64Url.decode(code.substring(5));
    final json = utf8.decode(zlib.decode(compressed));
    final data = jsonDecode(json) as Map<String, dynamic>;

    final sdpMap = data['sdp'] as Map<String, dynamic>;
    final candidates = (data['candidates'] as List?)
            ?.map((c) => RTCIceCandidate(
                  c['candidate'] as String,
                  c['sdpMid'] as String?,
                  c['sdpMLineIndex'] as int?,
                ))
            .toList() ??
        [];

    // ── answer 侧状态机 ──
    final pc = await _createAnswerPeerConnection(peerId);

    // setRemoteDescription 必须在 addIceCandidate 之前
    await pc.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String),
    );

    for (final c in candidates) {
      await pc.addCandidate(c);
    }

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await _waitForIceGathering(pc);

    final answerCandidates = (_manualCandidates.remove(peerId) ?? [])
        .map((c) => c.toMap())
        .toList();
    final localDesc = await pc.getLocalDescription();

    final answerData = {
      'sdp': localDesc?.toMap(),
      'candidates': answerCandidates,
    };

    final answerJson = jsonEncode(answerData);
    final answerCompressed = gzip.encode(utf8.encode(answerJson));
    return 'JTC1:${base64.encode(answerCompressed)}';
  }

  /// 接受应答码（offer 侧）
  Future<void> acceptAnswerCode(String peerId, String code) async {
    if (!code.startsWith('JTC1:')) {
      throw FormatException('Invalid answer code format');
    }

    final compressed = base64Url.decode(code.substring(5));
    final json = utf8.decode(zlib.decode(compressed));
    final data = jsonDecode(json) as Map<String, dynamic>;

    final sdpMap = data['sdp'] as Map<String, dynamic>;
    final candidates = (data['candidates'] as List?)
            ?.map((c) => RTCIceCandidate(
                  c['candidate'] as String,
                  c['sdpMid'] as String?,
                  c['sdpMLineIndex'] as int?,
                ))
            .toList() ??
        [];

    final pc = _peers[peerId];
    if (pc == null) throw StateError('No pending connection for peer $peerId');

    // setRemoteDescription 必须在 addIceCandidate 之前
    await pc.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String),
    );

    for (final c in candidates) {
      await pc.addCandidate(c);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // PeerConnection 工厂方法
  // ══════════════════════════════════════════════════════════════════════

  /// 创建 offer 侧 PC：主动创建 DataChannel（必须在 createOffer 前）
  Future<RTCPeerConnection> _createOfferPeerConnection(String peerId) async {
    final pc = await _buildPeerConnection(peerId);

    // DataChannel 必须在 createOffer 之前创建，才会被写入 SDP
    final dc = await pc.createDataChannel('chat', RTCDataChannelInit());
    dc.onMessage = (RTCDataChannelMessage m) {
      onDataReceived?.call(peerId, m.text);
    };
    _dataChannels[peerId] = dc;

    return pc;
  }

  /// 创建 answer 侧 PC：监听远端 DataChannel
  Future<RTCPeerConnection> _createAnswerPeerConnection(String peerId) async {
    final pc = await _buildPeerConnection(peerId);

    // answer 侧不主动创建 DataChannel，而是监听对端发来的 channel
    pc.onDataChannel = (RTCDataChannel dc) {
      dc.onMessage = (RTCDataChannelMessage m) {
        onDataReceived?.call(peerId, m.text);
      };
      _dataChannels[peerId] = dc;
      _setPhase(peerId, ConnectionPhase.connected);
      onConnectionStateChanged?.call(peerId, true);
    };

    return pc;
  }

  /// 构造基础 PeerConnection：配置 ICE 服务器 + 注册事件回调
  Future<RTCPeerConnection> _buildPeerConnection(String peerId) async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    });

    // ── onIceCandidate：Trickle ICE 回调 ──
    // 每次发现新的候选地址（host/srflx/relay）时触发
    pc.onIceCandidate = (candidate) {
      // 存储用于 JTC1 手动模式
      _manualCandidates.putIfAbsent(peerId, () => []).add(candidate);

      // 信令模式：即时转发候选到对端（Trickle ICE）
      if (_signalingConnected) {
        _sendSignal({
          'cmd': 'ice_candidate',
          'target_id': peerId,
          'candidate': jsonEncode(candidate.toMap()),
        });
      }
    };

    // ── onIceConnectionState：ICE 连接状态 ──
    // 比 onConnectionState 更细粒度，适合 UI 展示
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          _setPhase(peerId, ConnectionPhase.connecting);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _setPhase(peerId, ConnectionPhase.connected);
          onConnectionStateChanged?.call(peerId, true);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _setPhase(peerId, ConnectionPhase.failed);
          _cleanupPeer(peerId);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          // 短暂断开可能是网络波动，不立即清理
          break;
        default:
          break;
      }
    };

    // ── onConnectionState：整体连接状态 ──
    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _cleanupPeer(peerId);
      }
    };

    _peers[peerId] = pc;
    _setPhase(peerId, ConnectionPhase.idle);
    return pc;
  }

  // ══════════════════════════════════════════════════════════════════════
  // ICE gathering helper
  // ══════════════════════════════════════════════════════════════════════

  /// 等待 ICE 候选收集完毕（或超时）
  ///
  /// WebRTC ICE 收集阶段：
  /// 1. host 候选：本地 IP 地址（最快，通常 < 100ms）
  /// 2. srflx 候选：STUN 服务器返回的公网地址（数百 ms）
  /// 3. relay 候选：TURN 中继地址（如果有配置，1-2s）
  ///
  /// 使用半 Trickle 策略：等待收集完毕或超时。
  /// 超时后我们仍然通过 Trickle ICE 发送后续候选，
  /// 所以即使超时也不影响最终连通性。
  Future<void> _waitForIceGathering(RTCPeerConnection pc, {int timeoutSeconds = 5}) async {
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }

    final completer = Completer<void>();
    pc.onIceGatheringState = (RTCIceGatheringState state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        if (!completer.isCompleted) completer.complete();
      }
    };

    return completer.future.timeout(
      Duration(seconds: timeoutSeconds),
      onTimeout: () {
        // 超时不是致命错误——剩余的候选通过 Trickle ICE 异步发送
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════════════

  void _setPhase(String peerId, ConnectionPhase phase) {
    _connectionPhases[peerId] = phase;
    onConnectionPhase?.call(peerId, phase);
    // 连接成功或失败时取消超时计时器
    if (phase == ConnectionPhase.connected || phase == ConnectionPhase.failed) {
      _connectionTimers.remove(peerId)?.cancel();
    }
  }

  /// 启动 15 秒连接超时计时器
  void _startConnectionTimeout(String peerId) {
    _connectionTimers[peerId]?.cancel();
    _connectionTimers[peerId] = Timer(
      const Duration(seconds: connectionTimeoutSeconds),
      () => _onConnectionTimeout(peerId, '连接超时（$connectionTimeoutSeconds秒），请检查网络后重试'),
    );
  }

  /// 连接超时处理：关闭 PeerConnection、清理资源、通知错误
  void _onConnectionTimeout(String peerId, String reason) {
    _setPhase(peerId, ConnectionPhase.failed);
    _connectionTimers.remove(peerId)?.cancel();
    onError?.call(reason);
    // 关闭对等连接以释放资源
    final pc = _peers.remove(peerId);
    if (pc != null) {
      pc.close().catchError((_) {});
    }
    _dataChannels.remove(peerId);
    _pendingCandidates.remove(peerId);
    _manualCandidates.remove(peerId);
    _connectionModes.remove(peerId);
    onConnectionStateChanged?.call(peerId, false);
  }

  void _cleanupPeer(String peerId) {
    _connectionTimers.remove(peerId)?.cancel();
    _dataChannels.remove(peerId);
    _peers.remove(peerId);
    _pendingCandidates.remove(peerId);
    _manualCandidates.remove(peerId);
    _connectionModes.remove(peerId);
    _connectionPhases.remove(peerId);
    onConnectionStateChanged?.call(peerId, false);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Messaging
  // ══════════════════════════════════════════════════════════════════════

  /// 发送文字消息到指定 peer
  void sendMessage(String text, String targetId) {
    final dc = _dataChannels[targetId];
    if (dc != null) {
      dc.send(RTCDataChannelMessage(text));
    } else {
      onError?.call('No data channel for peer $targetId');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Cleanup
  // ══════════════════════════════════════════════════════════════════════

  Future<void> dispose() async {
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _dataChannels.clear();
    _pendingCandidates.clear();
    _manualCandidates.clear();
    _connectionModes.clear();
    _connectionPhases.clear();
    _channel?.sink.close();
    _signalingConnected = false;
  }
}
