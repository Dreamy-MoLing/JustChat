//! WebSocket client for the signaling server (placeholder).

/// Client that communicates with the signaling server to discover peers
/// and negotiate P2P connections.
#[derive(Debug, Clone)]
pub struct SignalingClient {
    /// Server URL (e.g. `ws://localhost:3000/ws`).
    pub server_url: String,
    /// Local peer ID.
    pub peer_id: String,
}

impl SignalingClient {
    /// Create a new signaling client.
    pub fn new(server_url: String, peer_id: String) -> Self {
        Self { server_url, peer_id }
    }

    /// Connect to the signaling server and register this peer.
    pub async fn connect(&self) -> crate::Result<()> {
        Err(crate::Error::Network("signaling client not yet implemented".into()))
    }

    /// Send a command to the signaling server.
    pub async fn send_command(&self, _cmd: &crate::protocol::signaling::ClientCommand) -> crate::Result<()> {
        Err(crate::Error::Network("signaling client not yet implemented".into()))
    }
}
