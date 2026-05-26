//! JustTalk core library — P2P text chat, end-to-end encryption, voice chat.
//!
//! Architecture (v0.0.3):
//! - `protocol`  — wire format (signaling, pairing, webrtc types, message envelope)
//! - `crypto`    — encryption trait + implementations
//! - `network`   — signaling WebSocket client (tokio-tungstenite)
//! - `identity`  — Ed25519 keypairs
//! - `engine`    — P2pEngine: 核心引擎，编排信令/WebRTC/配对/存储
//! - `storage`   — JSON 文件持久化 (messages, contacts, settings)

pub mod protocol;
pub mod crypto;
pub mod identity;
pub mod network;
pub mod engine;
pub mod storage;
pub mod api;

/// Common error type for justtalk-core operations.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("crypto error: {0}")]
    Crypto(String),
    #[error("network error: {0}")]
    Network(String),
    #[error("protocol error: {0}")]
    Protocol(String),
    #[error("storage error: {0}")]
    Storage(String),
    #[error("identity error: {0}")]
    Identity(String),
}

/// Convenience result type.
pub type Result<T> = std::result::Result<T, Error>;
