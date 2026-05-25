//! Chat message types and envelope format.
//!
//! Wire format: MessagePack-encoded `Envelope`.
//! Each envelope carries an encrypted `payload` — the encryption layer
//! is handled by the `crypto` module, transparent to the protocol.

use serde::{Deserialize, Serialize};

/// Protocol version for forward compatibility.
pub const PROTOCOL_VERSION: u8 = 1;

/// Top-level envelope wrapping every P2P message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Envelope {
    /// Protocol version (currently 1).
    pub version: u8,
    /// Type of the enclosed message.
    #[serde(rename = "type")]
    pub msg_type: MessageType,
    /// Sender's peer ID (32-byte Ed25519 public key, hex-encoded).
    pub sender_id: String,
    /// Unix timestamp in milliseconds.
    pub timestamp: u64,
    /// Message payload. For encrypted sessions this is ciphertext;
    /// for plaintext (v0.1) this is the serialized inner message.
    pub payload: Vec<u8>,
}

/// Message classification for routing and display.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MessageType {
    /// User-typed text chat message.
    Text,
    /// System notification (join/leave/online/offline).
    System,
    /// Voice audio frame (v0.5+).
    VoiceFrame,
    /// PreKeyBundle for establishing a Signal session (v0.2+).
    KeyExchange,
    /// Online/offline presence update.
    Presence,
}

/// The inner text message payload (decrypted content).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextMessage {
    /// Display text.
    pub content: String,
    /// Optional reply target (message ID).
    pub reply_to: Option<String>,
}

/// System notification content.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum SystemMessage {
    PeerOnline {
        peer_id: String,
    },
    PeerOffline {
        peer_id: String,
    },
}

impl Envelope {
    /// Create a new envelope with the current timestamp.
    pub fn new(msg_type: MessageType, sender_id: String, payload: Vec<u8>) -> Self {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;
        Self {
            version: PROTOCOL_VERSION,
            msg_type,
            sender_id,
            timestamp,
            payload,
        }
    }

    /// Serialize to MessagePack bytes.
    pub fn to_vec(&self) -> crate::Result<Vec<u8>> {
        rmp_serde::to_vec(self).map_err(|e| crate::Error::Protocol(e.to_string()))
    }

    /// Deserialize from MessagePack bytes.
    pub fn from_bytes(data: &[u8]) -> crate::Result<Self> {
        rmp_serde::from_slice(data).map_err(|e| crate::Error::Protocol(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_roundtrip() {
        let env = Envelope::new(
            MessageType::Text,
            "peer-1".into(),
            b"hello world".to_vec(),
        );
        let bytes = env.to_vec().unwrap();
        let decoded = Envelope::from_bytes(&bytes).unwrap();
        assert_eq!(decoded.msg_type, MessageType::Text);
        assert_eq!(decoded.sender_id, "peer-1");
        assert_eq!(decoded.payload, b"hello world");
        assert_eq!(decoded.version, PROTOCOL_VERSION);
    }

    #[test]
    fn text_message_serialization() {
        let msg = TextMessage {
            content: "hello".into(),
            reply_to: None,
        };
        let json = serde_json::to_string(&msg).unwrap();
        assert!(json.contains("hello"));
    }
}
