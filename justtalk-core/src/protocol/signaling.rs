//! 信令协议定义 — 匹配 justtalk-signaling 服务器的实际 JSON over WebSocket 协议。
//!
//! 每条消息是 `{"cmd": "<command>", ...}` 格式的 JSON 对象。
//! 服务器负责 peer 注册、消息路由、配对意图管理。

use serde::{Deserialize, Serialize};

/// 客户端→服务器命令。
///
/// 序列化为 `{"cmd": "<name>", ...}` 格式。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum SignalingCommand {
    /// 注册 peer（必须是 WebSocket 第一条消息）
    Register {
        peer_id: String,
        pubkey: String,
    },
    /// 心跳 ping
    Ping,
    /// 请求连接到目标 peer
    Connect {
        target_id: String,
    },
    /// 接受连接请求
    AcceptConnect {
        target_id: String,
    },
    /// 转发 SDP
    SdpOffer {
        target_id: String,
        sdp: serde_json::Value,
    },
    /// 转发 ICE 候选
    IceCandidate {
        target_id: String,
        candidate: serde_json::Value,
    },
    /// 公告配对意图（被扫码方调用）
    PairIntent {
        peer_id: String,
        display_name: String,
    },
    /// 扫码方请求配对连接
    ConnectViaPair {
        target_peer_id: String,
        display_name: String,
    },
}

/// 服务器→客户端消息。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum SignalingMessage {
    /// 心跳响应
    Pong,
    /// 注册确认
    Registered {
        success: bool,
        peer_id: String,
    },
    /// 新 peer 上线（广播给其他 peer）
    PeerOnline {
        peer_id: String,
    },
    /// Peer 断开（广播给其他 peer）
    PeerOffline {
        peer_id: String,
    },
    /// 收到连接请求
    ConnectRequest {
        from_id: String,
    },
    /// 配对连接通知（被扫码方收到）
    PairConnect {
        from_id: String,
        display_name: String,
    },
    /// 收到 SDP（offer 或 answer）
    SdpOffer {
        from_id: String,
        sdp: serde_json::Value,
    },
    /// 收到 ICE 候选
    IceCandidate {
        from_id: String,
        candidate: serde_json::Value,
    },
    /// 连接已接受
    AcceptConnect {
        from_id: String,
    },
    /// 错误
    Error {
        message: String,
    },
}

impl SignalingCommand {
    /// 序列化为 JSON 字符串
    pub fn to_json(&self) -> serde_json::Result<String> {
        serde_json::to_string(self)
    }
}

impl SignalingMessage {
    /// 从 JSON 字符串反序列化
    pub fn from_json(json: &str) -> serde_json::Result<Self> {
        serde_json::from_str(json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serialize_register() {
        let cmd = SignalingCommand::Register {
            peer_id: "alice".into(),
            pubkey: "abc123".into(),
        };
        let json = cmd.to_json().unwrap();
        assert!(json.contains(r#""cmd":"register""#));
        assert!(json.contains(r#""peer_id":"alice""#));
    }

    #[test]
    fn deserialize_peer_online() {
        let json = r#"{"cmd":"peer_online","peer_id":"bob"}"#;
        let msg = SignalingMessage::from_json(json).unwrap();
        match msg {
            SignalingMessage::PeerOnline { peer_id } => assert_eq!(peer_id, "bob"),
            _ => panic!("Expected PeerOnline"),
        }
    }

    #[test]
    fn deserialize_pair_connect() {
        let json = r#"{"cmd":"pair_connect","from_id":"alice","display_name":"Alice"}"#;
        let msg = SignalingMessage::from_json(json).unwrap();
        match msg {
            SignalingMessage::PairConnect {
                from_id,
                display_name,
            } => {
                assert_eq!(from_id, "alice");
                assert_eq!(display_name, "Alice");
            }
            _ => panic!("Expected PairConnect"),
        }
    }

    #[test]
    fn deserialize_error() {
        let json = r#"{"cmd":"error","message":"peer not found"}"#;
        let msg = SignalingMessage::from_json(json).unwrap();
        match msg {
            SignalingMessage::Error { message } => assert_eq!(message, "peer not found"),
            _ => panic!("Expected Error"),
        }
    }
}
