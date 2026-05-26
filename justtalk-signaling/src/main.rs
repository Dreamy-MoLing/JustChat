//! JustTalk signaling server.
//!
//! Endpoints:
//! - `GET  /health` — health check
//! - `GET  /peers`  — list online peers
//! - `WS   /ws`     — WebSocket for real-time signaling commands

use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;
use warp::ws::{Message, WebSocket};
use warp::Filter;

/// A registered peer's public info.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct PeerInfo {
    peer_id: String,
    pubkey: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
}

/// A connected peer with its message sender.
struct ConnectedPeer {
    info: PeerInfo,
    sender: mpsc::UnboundedSender<String>,
}

/// Shared application state: maps peer_id to connected peer.
type State = Arc<RwLock<HashMap<String, ConnectedPeer>>>;

/// JSON response wrapper.
#[derive(Debug, Serialize)]
struct ApiResponse<T: Serialize> {
    code: u16,
    data: Option<T>,
    message: String,
}

impl<T: Serialize> ApiResponse<T> {
    fn ok(data: T) -> Self {
        Self {
            code: 200,
            data: Some(data),
            message: "ok".into(),
        }
    }
}

impl ApiResponse<()> {
    #[allow(dead_code)]
    fn error(code: u16, message: impl Into<String>) -> Self {
        Self {
            code,
            data: None,
            message: message.into(),
        }
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let state: State = Arc::new(RwLock::new(HashMap::new()));

    let state_filter = warp::any().map(move || state.clone());

    // GET /peers
    let peers = warp::get()
        .and(warp::path("peers"))
        .and(state_filter.clone())
        .and_then(handle_peers);

    // GET /health
    let health = warp::get()
        .and(warp::path("health"))
        .map(|| warp::reply::json(&ApiResponse::ok("healthy")));

    // WS /ws
    let ws = warp::path("ws")
        .and(warp::ws())
        .and(state_filter.clone())
        .map(|ws: warp::ws::Ws, state| ws.on_upgrade(move |socket| handle_ws(socket, state)));

    let routes = peers.or(health).or(ws);

    tracing::info!("signaling server listening on 0.0.0.0:3000");
    warp::serve(routes).run(([0, 0, 0, 0], 3000)).await;
}

async fn handle_peers(state: State) -> Result<impl warp::Reply, Infallible> {
    let peers: Vec<PeerInfo> = state.read().values().map(|cp| cp.info.clone()).collect();
    Ok(warp::reply::json(&ApiResponse::ok(peers)))
}

async fn handle_ws(ws: WebSocket, state: State) {
    let (mut ws_tx, mut ws_rx) = ws.split();

    // First message must be a register command.
    let first_msg = match ws_rx.next().await {
        Some(Ok(m)) => m,
        _ => return,
    };

    let first_text = match first_msg.to_str() {
        Ok(t) => t,
        Err(_) => return,
    };

    // Validate message size.
    if first_text.len() > 65536 {
        let _ = ws_tx
            .send(Message::text(
                serde_json::json!({"cmd": "error", "message": "message too large"}).to_string(),
            ))
            .await;
        return;
    }

    let val: serde_json::Value = match serde_json::from_str(first_text) {
        Ok(v) => v,
        Err(e) => {
            let _ = ws_tx
                .send(Message::text(
                    serde_json::json!({"cmd": "error", "message": format!("invalid json: {e}")}).to_string(),
                ))
                .await;
            return;
        }
    };

    let cmd = val.get("cmd").and_then(|c| c.as_str()).unwrap_or("");
    if cmd != "register" {
        let _ = ws_tx
            .send(Message::text(
                serde_json::json!({"cmd": "error", "message": "first message must be register"}).to_string(),
            ))
            .await;
        return;
    }

    let peer_id = match val.get("peer_id").and_then(|v| v.as_str()) {
        Some(id) if !id.is_empty() && id.len() <= 128 => id.to_string(),
        _ => {
            let _ = ws_tx
                .send(Message::text(
                    serde_json::json!({"cmd": "error", "message": "invalid peer_id"}).to_string(),
                ))
                .await;
            return;
        }
    };

    let pubkey = val
        .get("pubkey")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    // Create channel for this peer.
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();

    // Register the peer.
    {
        let mut state = state.write();
        // Remove any existing connection for the same peer_id.
        if let Some(old) = state.remove(&peer_id) {
            drop(old.sender); // Close old channel.
        }
        state.insert(
            peer_id.clone(),
            ConnectedPeer {
                info: PeerInfo {
                    peer_id: peer_id.clone(),
                    pubkey,
                    display_name: None,
                },
                sender: tx,
            },
        );
    }

    tracing::info!(peer_id = %peer_id, "peer registered");

    // Confirm registration.
    let _ = ws_tx
        .send(Message::text(
            serde_json::json!({"cmd": "registered", "success": true, "peer_id": peer_id}).to_string(),
        ))
        .await;

    // Broadcast peer_online to all other peers.
    broadcast(
        &state,
        &peer_id,
        &serde_json::json!({"cmd": "peer_online", "peer_id": peer_id}).to_string(),
    );

    // Spawn task to forward messages from channel to WebSocket.
    let _peer_id_clone = peer_id.clone();
    let forward_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if ws_tx.send(Message::text(msg)).await.is_err() {
                break;
            }
        }
    });

    // Main loop: read from WebSocket and route commands.
    while let Some(result) = ws_rx.next().await {
        let msg = match result {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!(peer_id = %peer_id, "ws error: {e}");
                break;
            }
        };

        if msg.is_close() {
            break;
        }

        let text = match msg.to_str() {
            Ok(t) => t,
            Err(_) => continue,
        };

        // Validate message size.
        if text.len() > 65536 {
            let _ = send_to_peer(
                &state,
                &peer_id,
                &serde_json::json!({"cmd": "error", "message": "message too large"}).to_string(),
            );
            continue;
        }

        let val: serde_json::Value = match serde_json::from_str(text) {
            Ok(v) => v,
            Err(e) => {
                let _ = send_to_peer(
                    &state,
                    &peer_id,
                    &serde_json::json!({"cmd": "error", "message": format!("invalid json: {e}")}).to_string(),
                );
                continue;
            }
        };

        let cmd = val.get("cmd").and_then(|c| c.as_str()).unwrap_or("");
        match cmd {
            "ping" => {
                let _ = send_to_peer(
                    &state,
                    &peer_id,
                    &serde_json::json!({"cmd": "pong"}).to_string(),
                );
            }
            "connect" => {
                let target_id = match val.get("target_id").and_then(|v| v.as_str()) {
                    Some(id) => id,
                    None => continue,
                };
                let msg = serde_json::json!({
                    "cmd": "connect_req",
                    "from_id": peer_id,
                })
                .to_string();
                if send_to_peer(&state, target_id, &msg).is_err() {
                    let _ = send_to_peer(
                        &state,
                        &peer_id,
                        &serde_json::json!({"cmd": "error", "message": "peer not found"}).to_string(),
                    );
                }
            }
            "accept_connect" => {
                let target_id = match val.get("target_id").and_then(|v| v.as_str()) {
                    Some(id) => id,
                    None => continue,
                };
                let msg = serde_json::json!({
                    "cmd": "accept_connect",
                    "from_id": peer_id,
                })
                .to_string();
                let _ = send_to_peer(&state, target_id, &msg);
            }
            "sdp_offer" => {
                let target_id = match val.get("target_id").and_then(|v| v.as_str()) {
                    Some(id) => id,
                    None => continue,
                };
                let sdp = match val.get("sdp") {
                    Some(s) => s.clone(),
                    None => continue,
                };
                let msg = serde_json::json!({
                    "cmd": "sdp_offer",
                    "from_id": peer_id,
                    "sdp": sdp,
                })
                .to_string();
                let _ = send_to_peer(&state, target_id, &msg);
            }
            "ice_candidate" => {
                let target_id = match val.get("target_id").and_then(|v| v.as_str()) {
                    Some(id) => id,
                    None => continue,
                };
                let candidate = match val.get("candidate") {
                    Some(c) => c.clone(),
                    None => continue,
                };
                let msg = serde_json::json!({
                    "cmd": "ice_candidate",
                    "from_id": peer_id,
                    "candidate": candidate,
                })
                .to_string();
                let _ = send_to_peer(&state, target_id, &msg);
            }
            "pair_intent" => {
                let display_name = val
                    .get("display_name")
                    .and_then(|v| v.as_str())
                    .unwrap_or(&peer_id)
                    .to_string();
                // Store display_name on this peer's info.
                {
                    let mut state = state.write();
                    if let Some(peer) = state.get_mut(&peer_id) {
                        peer.info.display_name = Some(display_name.clone());
                    }
                }
                tracing::info!(peer_id = %peer_id, display_name = %display_name, "pair_intent set");
            }
            "connect_via_pair" => {
                let target_id = match val.get("target_peer_id").and_then(|v| v.as_str()) {
                    Some(id) => id,
                    None => continue,
                };
                let display_name = val
                    .get("display_name")
                    .and_then(|v| v.as_str())
                    .unwrap_or(&peer_id)
                    .to_string();
                let msg = serde_json::json!({
                    "cmd": "pair_connect",
                    "from_id": peer_id,
                    "display_name": display_name,
                })
                .to_string();
                if send_to_peer(&state, target_id, &msg).is_err() {
                    let _ = send_to_peer(
                        &state,
                        &peer_id,
                        &serde_json::json!({"cmd": "error", "message": "peer not found"}).to_string(),
                    );
                }
            }
            _ => {
                let _ = send_to_peer(
                    &state,
                    &peer_id,
                    &serde_json::json!({"cmd": "error", "message": format!("unknown command: {cmd}")}).to_string(),
                );
            }
        }
    }

    // Clean up on disconnect.
    forward_task.abort();
    state.write().remove(&peer_id);
    tracing::info!(peer_id = %peer_id, "peer disconnected");

    // Broadcast peer_offline to all other peers.
    broadcast(
        &state,
        &peer_id,
        &serde_json::json!({"cmd": "peer_offline", "peer_id": peer_id}).to_string(),
    );
}

/// Send a message to a specific peer. Returns Err if peer not found.
fn send_to_peer(state: &State, peer_id: &str, msg: &str) -> Result<(), ()> {
    let state = state.read();
    if let Some(peer) = state.get(peer_id) {
        peer.sender.send(msg.to_string()).map_err(|_| ())
    } else {
        Err(())
    }
}

/// Broadcast a message to all peers except the sender.
fn broadcast(state: &State, sender_id: &str, msg: &str) {
    let state = state.read();
    for (id, peer) in state.iter() {
        if id != sender_id {
            let _ = peer.sender.send(msg.to_string());
        }
    }
}
