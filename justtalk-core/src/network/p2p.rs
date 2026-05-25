//! P2P connection abstraction (placeholder for WebRTC / QUIC transport).

/// Represents a direct peer-to-peer connection.
///
/// Will be backed by WebRTC data channels (v0.2) or QUIC (v0.4+).
#[derive(Debug, Clone)]
pub struct P2pConnection {
    /// Remote peer ID.
    pub peer_id: String,
    /// Whether the connection is currently active.
    pub connected: bool,
}

impl P2pConnection {
    /// Create a new connection handle (not yet connected).
    pub fn new(peer_id: String) -> Self {
        Self {
            peer_id,
            connected: false,
        }
    }

    /// Send raw bytes to the remote peer.
    pub async fn send(&self, _data: &[u8]) -> crate::Result<()> {
        Err(crate::Error::Network("P2P transport not yet implemented".into()))
    }

    /// Receive the next message from the remote peer.
    pub async fn recv(&self) -> crate::Result<Vec<u8>> {
        Err(crate::Error::Network("P2P transport not yet implemented".into()))
    }
}
