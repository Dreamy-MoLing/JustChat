//! JustTalk core library — P2P text chat, end-to-end encryption, voice chat.
//!
//! Architecture:
//! - `protocol`  — wire format (envelope, message types)
//! - `crypto`    — encryption trait + implementations
//! - `network`   — P2P transport + signaling client
//! - `identity`  — Ed25519 keypairs, contacts
//! - `voice`     — audio capture/playback/encoding (phase 3)
//! - `storage`   — local SQLite persistence

pub mod protocol;
pub mod crypto;
pub mod identity;
pub mod network;
pub mod storage;
#[cfg(feature = "voice")]
pub mod voice;

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
