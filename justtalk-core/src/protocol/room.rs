//! Multi-party room protocol (v0.3+).
//!
//! Rooms are identified by a UUID v4 string.
//! The signaling server tracks room membership but does NOT relay messages.

use serde::{Deserialize, Serialize};

/// Room state visible to all members.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Room {
    pub id: String,
    pub name: String,
    pub creator: String,
    pub members: Vec<String>,
}

/// A member joining or leaving.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum RoomEvent {
    MemberJoined { room_id: String, peer_id: String },
    MemberLeft { room_id: String, peer_id: String },
    RoomClosed { room_id: String },
}
