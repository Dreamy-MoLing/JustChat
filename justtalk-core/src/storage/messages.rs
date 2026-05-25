//! Local message store (placeholder for SQLite persistence).

/// Stores chat messages locally for history and offline delivery.
#[derive(Debug, Clone)]
pub struct MessageStore {
    /// Database file path.
    pub db_path: String,
}

impl MessageStore {
    /// Open or create a message store at the given path.
    pub fn new(db_path: String) -> Self {
        Self { db_path }
    }

    /// Persist an incoming or outgoing message.
    pub async fn save(&self, _peer_id: &str, _payload: &[u8]) -> crate::Result<()> {
        Err(crate::Error::Storage("message store not yet implemented".into()))
    }

    /// Load recent messages for a peer conversation.
    pub async fn load_recent(&self, _peer_id: &str, _limit: u32) -> crate::Result<Vec<Vec<u8>>> {
        Err(crate::Error::Storage("message store not yet implemented".into()))
    }
}
