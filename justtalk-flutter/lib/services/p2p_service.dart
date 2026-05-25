import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class P2pService {
  WebSocketChannel? _channel;
  bool _signalingConnected = false;

  /// Per-peer data channels (offer side and answer side).
  final Map<String, RTCDataChannel> _dataChannels = {};

  /// Per-peer connections.
  final Map<String, RTCPeerConnection> _peers = {};

  /// Pending ICE candidates collected before remote description is set.
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  /// ICE candidates collected for manual (non-signaling) mode — one list per peer.
  final Map<String, List<RTCIceCandidate>> _manualCandidates = {};

  // ── Callbacks ──

  /// Called when a data message is received from a peer.
  void Function(String peerId, String message)? onDataReceived;

  /// Called when a peer's connection state changes.
  void Function(String peerId, bool connected)? onConnectionStateChanged;

  /// Called on error.
  void Function(String error)? onError;

  // ── Getters ──

  bool get isConnectedToSignaling => _signalingConnected;

  bool isPeerConnected(String peerId) {
    return _dataChannels.containsKey(peerId);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Signaling server mode
  // ══════════════════════════════════════════════════════════════════════

  /// Connect to signaling server and register this peer.
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
      case 'sdp_offer':
        _handleSdpOffer(msg);
        break;
      case 'ice_candidate':
        _handleIceCandidate(msg);
        break;
      case 'accept_connect':
        //对方接受了连接请求，可以开始WebRTC协商
        break;
      case 'error':
        onError?.call(msg['message'] as String? ?? 'unknown error');
        break;
    }
  }

  /// Initiate a P2P connection to a remote peer (via signaling server).
  Future<void> connect(String targetId) async {
    _sendSignal({'cmd': 'connect', 'target_id': targetId});
    await _createOfferPeerConnection(targetId);
    final offer = await _peers[targetId]!.createOffer();
    await _peers[targetId]!.setLocalDescription(offer);
    _sendSignal({
      'cmd': 'sdp_offer',
      'target_id': targetId,
      'sdp': jsonEncode(offer.toMap()),
    });
  }

  Future<void> _handleIncomingConnection(String fromId) async {
    _sendSignal({'cmd': 'accept_connect', 'target_id': fromId});
  }

  Future<void> _handleSdpOffer(Map<String, dynamic> msg) async {
    final fromId = msg['from_id'] as String;
    final sdp = jsonDecode(msg['sdp'] as String);

    if (!_peers.containsKey(fromId)) {
      await _createAnswerPeerConnection(fromId);
    }

    await _peers[fromId]!.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'], sdp['type']),
    );

    // Flush pending candidates.
    for (final c in _pendingCandidates.remove(fromId) ?? []) {
      await _peers[fromId]!.addCandidate(c);
    }

    // If this is an offer, create and send answer.
    if (sdp['type'] == 'offer') {
      final answer = await _peers[fromId]!.createAnswer();
      await _peers[fromId]!.setLocalDescription(answer);
      _sendSignal({
        'cmd': 'sdp_offer',
        'target_id': fromId,
        'sdp': jsonEncode(answer.toMap()),
      });
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> msg) async {
    final fromId = msg['from_id'] as String;
    final candidate = jsonDecode(msg['candidate'] as String);
    final ice = RTCIceCandidate(
      candidate['candidate'],
      candidate['sdpMid'],
      candidate['sdpMLineIndex'],
    );

    if (_peers[fromId]?.getRemoteDescription() != null) {
      await _peers[fromId]!.addCandidate(ice);
    } else {
      _pendingCandidates.putIfAbsent(fromId, () => []).add(ice);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Manual SDP exchange mode (zero server)
  // ══════════════════════════════════════════════════════════════════════

  /// Generate a connection code (offer side).
  /// Creates a PeerConnection, generates an offer, waits for ICE gathering,
  /// and returns a base64-encoded string containing SDP + ICE candidates.
  Future<String> generateConnectionCode(String peerId) async {
    final pc = await _createOfferPeerConnection(peerId);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    // Wait for ICE gathering to complete.
    await _waitForIceGathering(pc);

    // Collect ICE candidates gathered for this peer.
    final candidates = (_manualCandidates.remove(peerId) ?? [])
        .map((c) => c.toMap())
        .toList();

    // Use the SDP from the local description (includes candidates in the
    // SDP string itself, but explicit candidates help the answerer).
    final localDesc = await pc.getLocalDescription();
    final sdpMap = localDesc?.toMap();

    final codeData = {
      'sdp': sdpMap,
      'candidates': candidates,
    };

    final json = jsonEncode(codeData);
    final compressed = zlib.encode(utf8.encode(json));
    return 'JTC1:${base64Url.encode(compressed)}';
  }

  /// Accept a connection code (answer side).
  /// Decodes the offer, creates an answer, and returns the answer code.
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

    final pc = await _createAnswerPeerConnection(peerId);

    await pc.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String),
    );

    // Add ICE candidates from the offer.
    for (final c in candidates) {
      await pc.addCandidate(c);
    }

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    await _waitForIceGathering(pc);

    // Collect answer-side ICE candidates.
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

  /// Accept an answer code (offer side).
  /// Decodes the answer and sets the remote description to complete the connection.
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
    if (pc == null) {
      throw StateError('No pending connection for peer $peerId');
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'] as String, sdpMap['type'] as String),
    );

    for (final c in candidates) {
      await pc.addCandidate(c);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Peer connection helpers
  // ══════════════════════════════════════════════════════════════════════

  /// Create a peer connection for the offer side (creates DataChannel).
  Future<RTCPeerConnection> _createOfferPeerConnection(String peerId) async {
    final pc = await _buildPeerConnection(peerId);

    final dc = await pc.createDataChannel('chat', RTCDataChannelInit());
    dc.onMessage = (RTCDataChannelMessage m) {
      onDataReceived?.call(peerId, m.text);
    };
    _dataChannels[peerId] = dc;

    return pc;
  }

  /// Create a peer connection for the answer side (listens for DataChannel).
  Future<RTCPeerConnection> _createAnswerPeerConnection(String peerId) async {
    final pc = await _buildPeerConnection(peerId);

    pc.onDataChannel = (RTCDataChannel dc) {
      dc.onMessage = (RTCDataChannelMessage m) {
        onDataReceived?.call(peerId, m.text);
      };
      _dataChannels[peerId] = dc;
      onConnectionStateChanged?.call(peerId, true);
    };

    return pc;
  }

  /// Build a base PeerConnection with ICE servers and event handlers.
  Future<RTCPeerConnection> _buildPeerConnection(String peerId) async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    });

    pc.onIceCandidate = (candidate) {
      // Store for manual mode.
      _manualCandidates.putIfAbsent(peerId, () => []).add(candidate);

      // For signaling mode: forward to signaling server.
      if (_signalingConnected) {
        _sendSignal({
          'cmd': 'ice_candidate',
          'target_id': peerId,
          'candidate': jsonEncode(candidate.toMap()),
        });
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      final connected = state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      onConnectionStateChanged?.call(peerId, connected);

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _cleanupPeer(peerId);
      }
    };

    _peers[peerId] = pc;
    return pc;
  }

  /// Wait for ICE gathering to complete on a peer connection.
  Future<void> _waitForIceGathering(RTCPeerConnection pc) async {
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return;

    final completer = Completer<void>();
    pc.onIceGatheringState = (RTCIceGatheringState state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        if (!completer.isCompleted) completer.complete();
      }
    };

    // Timeout after 10 seconds.
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }

  void _cleanupPeer(String peerId) {
    _dataChannels.remove(peerId);
    _peers.remove(peerId);
    _pendingCandidates.remove(peerId);
    _manualCandidates.remove(peerId);
    onConnectionStateChanged?.call(peerId, false);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Messaging
  // ══════════════════════════════════════════════════════════════════════

  /// Send a text message to a specific peer.
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

  /// Clean up all connections.
  Future<void> dispose() async {
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _dataChannels.clear();
    _pendingCandidates.clear();
    _channel?.sink.close();
    _signalingConnected = false;
  }
}
