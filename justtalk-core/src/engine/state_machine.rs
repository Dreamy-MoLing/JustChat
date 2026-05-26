//! WebRTC 状态机 — 编排 PeerConnection 生命周期。
//!
//! 从 p2p_service.dart 移植而来。每个函数接收状态 + 事件，返回需要执行的 WebrtcCommand 列表。
//! P2pEngine 负责将命令推送到 WebrtcCommand stream 并在 Dart 回调后调用下一个函数。

use crate::protocol::webrtc_types::WebrtcCommand;

/// 默认 ICE 服务器配置（Google STUN）
pub const ICE_SERVERS_JSON: &str = r#"{"iceServers":[{"urls":"stun:stun.l.google.com:19302"},{"urls":"stun:stun1.l.google.com:19302"}]}"#;

/// Offer 侧：开始主动连接流程。
///
/// 调用后返回命令序列：
/// 1. CreatePeerConnection → Dart 回调 on_peer_connection_created
/// 2. → 调用 on_offer_peer_created()
pub fn start_offer_flow(peer_id: &str) -> Vec<WebrtcCommand> {
    vec![WebrtcCommand::CreatePeerConnection {
        peer_id: peer_id.to_string(),
        ice_servers_json: ICE_SERVERS_JSON.to_string(),
    }]
}

/// Offer 侧：PeerConnection 创建完成后的第二步。
/// Dart 必须在 PC 上创建 DataChannel 并创建 Offer。
pub fn on_offer_peer_created(peer_id: &str) -> Vec<WebrtcCommand> {
    vec![
        // DataChannel 必须在 createOffer 之前创建
        WebrtcCommand::CreateDataChannel {
            peer_id: peer_id.to_string(),
            label: "chat".to_string(),
        },
        WebrtcCommand::CreateOffer {
            peer_id: peer_id.to_string(),
        },
    ]
}

/// Offer 侧：收到本地 SDP 后的第三步（由 createOffer 触发）。
/// 设置本地描述，等待 ICE 收集。
pub fn on_offer_local_desc(peer_id: &str, sdp: &str) -> Vec<WebrtcCommand> {
    vec![
        WebrtcCommand::SetLocalDescription {
            peer_id: peer_id.to_string(),
            sdp: sdp.to_string(),
            sdp_type: "offer".to_string(),
        },
        WebrtcCommand::WaitForIceGathering {
            peer_id: peer_id.to_string(),
            timeout_secs: 5,
        },
    ]
}

/// Offer 侧：ICE 收集完成，准备通过信令发送 offer。
/// 引擎在收到此结果后应通过 signaling_client 发送 sdp_offer。
pub fn on_offer_ice_complete(_peer_id: &str) -> Vec<WebrtcCommand> {
    // ICE 收集完成，引擎将发送 SDP 通过信令。无需更多 WebRTC 命令。
    vec![]
}

/// Answer 侧：收到远端 offer 后开始。
///
/// 1. CreatePeerConnection → Dart 回调 on_peer_connection_created
pub fn start_answer_flow(peer_id: &str) -> Vec<WebrtcCommand> {
    vec![WebrtcCommand::CreatePeerConnection {
        peer_id: peer_id.to_string(),
        ice_servers_json: ICE_SERVERS_JSON.to_string(),
    }]
}

/// Answer 侧：PC 创建完成，设置远端 SDP + 刷新暂存 ICE 候选。
pub fn on_answer_peer_created(peer_id: &str, offer_sdp: &str) -> Vec<WebrtcCommand> {
    vec![WebrtcCommand::SetRemoteDescription {
        peer_id: peer_id.to_string(),
        sdp: offer_sdp.to_string(),
        sdp_type: "offer".to_string(),
    }]
}

/// Answer 侧：setRemoteDescription 完成后，刷新暂存 ICE → 创建 answer。
pub fn on_answer_remote_set(peer_id: &str) -> Vec<WebrtcCommand> {
    vec![
        WebrtcCommand::CreateAnswer {
            peer_id: peer_id.to_string(),
        },
    ]
}

/// Answer 侧：收到本地 answer SDP 后，设置本地描述 → 收集 ICE。
pub fn on_answer_local_desc(peer_id: &str, sdp: &str) -> Vec<WebrtcCommand> {
    vec![
        WebrtcCommand::SetLocalDescription {
            peer_id: peer_id.to_string(),
            sdp: sdp.to_string(),
            sdp_type: "answer".to_string(),
        },
        WebrtcCommand::WaitForIceGathering {
            peer_id: peer_id.to_string(),
            timeout_secs: 5,
        },
    ]
}

/// Answer 侧：ICE 收集完成，准备通过信令发送 answer。
pub fn on_answer_ice_complete(_peer_id: &str) -> Vec<WebrtcCommand> {
    vec![]
}

/// Offer 侧：收到远端 answer → setRemoteDescription + flush 暂存 ICE。
pub fn on_receive_answer(peer_id: &str, answer_sdp: &str) -> Vec<WebrtcCommand> {
    vec![WebrtcCommand::SetRemoteDescription {
        peer_id: peer_id.to_string(),
        sdp: answer_sdp.to_string(),
        sdp_type: "answer".to_string(),
    }]
}

/// 添加 ICE 候选（Trickle ICE）。
/// Dart 收到对端的 ICE 候选后，引擎调用此函数生成 AddIceCandidate 命令。
pub fn add_remote_ice(
    peer_id: &str,
    candidate: &str,
    sdp_mid: Option<&str>,
    sdp_m_line_index: Option<i32>,
) -> Vec<WebrtcCommand> {
    vec![WebrtcCommand::AddIceCandidate {
        peer_id: peer_id.to_string(),
        candidate: candidate.to_string(),
        sdp_mid: sdp_mid.map(|s| s.to_string()),
        sdp_m_line_index,
    }]
}

/// 发送 DataChannel 消息
pub fn send_message(peer_id: &str, data: &str) -> Vec<WebrtcCommand> {
    vec![WebrtcCommand::SendDataChannelMessage {
        peer_id: peer_id.to_string(),
        data: data.to_string(),
    }]
}

/// JTC1 offer 侧流程（手动 SDP 交换，无信令）
pub fn start_jtc1_offer_flow(peer_id: &str) -> Vec<WebrtcCommand> {
    start_offer_flow(peer_id)
}

/// JTC1 answer 侧流程
pub fn start_jtc1_answer_flow(peer_id: &str, offer_sdp: &str) -> Vec<WebrtcCommand> {
    vec![
        WebrtcCommand::CreatePeerConnection {
            peer_id: peer_id.to_string(),
            ice_servers_json: ICE_SERVERS_JSON.to_string(),
        },
        WebrtcCommand::SetRemoteDescription {
            peer_id: peer_id.to_string(),
            sdp: offer_sdp.to_string(),
            sdp_type: "offer".to_string(),
        },
    ]
}

/// 关闭 peer 连接
pub fn close_peer(peer_id: &str) -> Vec<WebrtcCommand> {
    vec![WebrtcCommand::ClosePeerConnection {
        peer_id: peer_id.to_string(),
    }]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offer_flow_steps() {
        let cmds = start_offer_flow("peer1");
        assert!(cmds.len() == 1);
        match &cmds[0] {
            WebrtcCommand::CreatePeerConnection { peer_id, .. } => {
                assert_eq!(peer_id, "peer1");
            }
            _ => panic!("Expected CreatePeerConnection"),
        }
    }

    #[test]
    fn offer_peer_creates_dc_and_offer() {
        let cmds = on_offer_peer_created("peer2");
        assert_eq!(cmds.len(), 2);
    }

    #[test]
    fn send_message_command() {
        let cmds = send_message("peer3", "hello");
        match &cmds[0] {
            WebrtcCommand::SendDataChannelMessage { peer_id, data } => {
                assert_eq!(peer_id, "peer3");
                assert_eq!(data, "hello");
            }
            _ => panic!("Expected SendDataChannelMessage"),
        }
    }
}
