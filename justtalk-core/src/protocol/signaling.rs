//! Signaling protocol commands (JSON over WebSocket).
//!
//! The signaling server *only* coordinates connection setup —
//! chat data flows directly P2P.

use serde::{Deserialize, Serialize};

/// Client-to-server command.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum ClientCommand {
    /// Register this peer with the signaling server.
    Register {
        peer_id: String,
        /// Base64-encoded Ed25519 public key.
        pubkey: String,
    },
    /// Request to connect to a target peer.
    Connect {
        target_id: String,
    },
    /// Acknowledge a connect request from another peer.
    AcceptConnect {
        target_id: String,
    },
    /// Clean disconnect from a peer.
    Disconnect {
        target_id: String,
    },
    /// Create a multi-party chat room (v0.3+).
    CreateRoom {
        room_name: String,
    },
    /// Join an existing room (v0.3+).
    JoinRoom {
        room_id: String,
    },
    /// Heartbeat response.
    Pong,
}

/// Server-to-client message.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum ServerMessage {
    /// Registration succeeded.
    Registered {
        success: bool,
        error: Option<String>,
    },
    /// A peer came online.
    PeerOnline {
        peer_id: String,
    },
    /// A peer went offline.
    PeerOffline {
        peer_id: String,
    },
    /// Someone wants to connect with you.
    ConnectRequest {
        from_id: String,
    },
    /// WebRTC session description from the remote peer.
    SdpOffer {
        from_id: String,
        sdp: String,
        candidates: Vec<serde_json::Value>,
    },
    /// WebRTC ICE candidate.
    IceCandidate {
        from_id: String,
        candidate: serde_json::Value,
    },
    /// A room was created (v0.3+).
    RoomCreated {
        room_id: String,
    },
    /// Heartbeat ping.
    Ping,
    /// Generic error.
    Error {
        message: String,
    },
}
