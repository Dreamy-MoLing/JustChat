// WebRTC 适配器 — 薄层，只执行 flutter_webrtc 操作，零业务逻辑。
//
// 监听 Rust 引擎的 WebrtcCommand stream，执行对应的 flutter_webrtc API，
// 完成后回调 engine.on_xxx()。
//
// 这是 v0.0.3 架构中 Flutter 侧唯一的非 UI 代码，
// 且完全不含状态机、协议、配对等业务逻辑。

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Dart 侧的 WebRTC 命令接口（与 Rust WebrtcCommand 对应）
class WebrtcCommand {
  final String cmd;
  final Map<String, dynamic> params;

  WebrtcCommand({required this.cmd, required this.params});

  factory WebrtcCommand.fromJson(Map<String, dynamic> json) {
    return WebrtcCommand(cmd: json['cmd'] as String, params: json);
  }
}

/// WebRTC 适配器
class WebrtcAdapter {
  /// PeerConnection 池
  final Map<String, RTCPeerConnection> _pcs = {};

  /// DataChannel 池
  final Map<String, RTCDataChannel> _dcs = {};

  /// 引擎回调：Dart → Rust
  void Function(Map<String, dynamic>)? onCallback;

  /// ICE 服务器配置
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  /// 执行一条 WebRTC 命令
  Future<void> execute(WebrtcCommand command) async {
    final params = command.params;
    final peerId = params['peer_id'] as String? ?? '';

    try {
      switch (command.cmd) {
        case 'create_peer_connection':
          await _createPeerConnection(peerId);
        case 'create_data_channel':
          await _createDataChannel(peerId, params['label'] as String? ?? 'chat');
        case 'create_offer':
          await _createOffer(peerId);
        case 'create_answer':
          await _createAnswer(peerId);
        case 'set_local_description':
          await _setLocalDescription(
            peerId,
            params['sdp'] as String,
            params['sdp_type'] as String,
          );
        case 'set_remote_description':
          await _setRemoteDescription(
            peerId,
            params['sdp'] as String,
            params['sdp_type'] as String,
          );
        case 'add_ice_candidate':
          await _addIceCandidate(peerId, params);
        case 'wait_for_ice_gathering':
          await _waitForIceGathering(
            peerId,
            (params['timeout_secs'] as num?)?.toInt() ?? 5,
          );
        case 'send_data_channel_message':
          _sendMessage(peerId, params['data'] as String? ?? '');
        case 'close_peer_connection':
          await _closePeerConnection(peerId);
      }
    } catch (e) {
      onCallback?.call({
        'callback': 'on_peer_connection_failed',
        'peer_id': peerId,
        'error': e.toString(),
      });
    }
  }

  Future<void> _createPeerConnection(String peerId) async {
    final pc = await createPeerConnection(_iceServers);

    // ICE candidate 回调
    pc.onIceCandidate = (candidate) {
      onCallback?.call({
        'callback': 'on_ice_candidate',
        'peer_id': peerId,
        'candidate': candidate.candidate,
        'sdp_mid': candidate.sdpMid,
        'sdp_m_line_index': candidate.sdpMLineIndex,
      });
    };

    // ICE gathering state
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        onCallback?.call({
          'callback': 'on_ice_gathering_complete',
          'peer_id': peerId,
        });
      }
    };

    // ICE connection state
    pc.onIceConnectionState = (state) {
      onCallback?.call({
        'callback': 'on_ice_connection_state_change',
        'peer_id': peerId,
        'state': state.name,
      });
    };

    // DataChannel 监听（answer 侧）
    pc.onDataChannel = (dc) {
      _dcs[peerId] = dc;
      dc.onMessage = (msg) {
        onCallback?.call({
          'callback': 'on_data_channel_message',
          'peer_id': peerId,
          'data': msg.text,
        });
      };
      onCallback?.call({
        'callback': 'on_data_channel_open',
        'peer_id': peerId,
      });
    };

    _pcs[peerId] = pc;
    onCallback?.call({
      'callback': 'on_peer_connection_created',
      'peer_id': peerId,
      'is_offer_side': true,
    });
  }

  Future<void> _createDataChannel(String peerId, String label) async {
    final pc = _pcs[peerId];
    if (pc == null) return;

    final dc = await pc.createDataChannel(label, RTCDataChannelInit());
    dc.onMessage = (msg) {
      onCallback?.call({
        'callback': 'on_data_channel_message',
        'peer_id': peerId,
        'data': msg.text,
      });
    };
    _dcs[peerId] = dc;

    // offer 侧 DC 创建后即可视为已连接
    onCallback?.call({
      'callback': 'on_data_channel_open',
      'peer_id': peerId,
    });
  }

  Future<void> _createOffer(String peerId) async {
    final pc = _pcs[peerId];
    if (pc == null) return;

    final offer = await pc.createOffer();
    onCallback?.call({
      'callback': 'on_local_description',
      'peer_id': peerId,
      'sdp': offer.sdp,
      'sdp_type': 'offer',
    });
  }

  Future<void> _createAnswer(String peerId) async {
    final pc = _pcs[peerId];
    if (pc == null) return;

    final answer = await pc.createAnswer();
    onCallback?.call({
      'callback': 'on_local_description',
      'peer_id': peerId,
      'sdp': answer.sdp,
      'sdp_type': 'answer',
    });
  }

  Future<void> _setLocalDescription(String peerId, String sdp, String type) async {
    final pc = _pcs[peerId];
    if (pc == null) return;
    await pc.setLocalDescription(RTCSessionDescription(sdp, type));
  }

  Future<void> _setRemoteDescription(String peerId, String sdp, String type) async {
    final pc = _pcs[peerId];
    if (pc == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
  }

  Future<void> _addIceCandidate(String peerId, Map<String, dynamic> params) async {
    final pc = _pcs[peerId];
    if (pc == null) return;

    await pc.addCandidate(RTCIceCandidate(
      params['candidate'] as String? ?? '',
      params['sdp_mid'] as String?,
      (params['sdp_m_line_index'] as num?)?.toInt(),
    ));
  }

  Future<void> _waitForIceGathering(String peerId, int timeoutSecs) async {
    final pc = _pcs[peerId];
    if (pc == null) return;

    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }

    final completer = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        if (!completer.isCompleted) completer.complete();
      }
    };

    await completer.future.timeout(
      Duration(seconds: timeoutSecs),
      onTimeout: () {},
    );
  }

  void _sendMessage(String peerId, String data) {
    _dcs[peerId]?.send(RTCDataChannelMessage(data));
  }

  Future<void> _closePeerConnection(String peerId) async {
    await _pcs[peerId]?.close();
    _pcs.remove(peerId);
    _dcs.remove(peerId);
  }

  /// 清理所有连接
  Future<void> dispose() async {
    for (final pc in _pcs.values) {
      await pc.close();
    }
    _pcs.clear();
    _dcs.clear();
  }
}
