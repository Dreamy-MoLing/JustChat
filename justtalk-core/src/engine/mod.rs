//! P2pEngine — 核心引擎，整合信令、WebRTC 编排、配对、存储。
//!
//! 通过命令/事件模式与 Dart 侧通信：
//! - `take_webrtc_commands()` → Dart 执行 flutter_webrtc 操作
//! - `take_events()` → Dart UI 更新状态
//! - `on_*()` 方法 → Dart 回调引擎

pub mod code_router;
pub mod peer_manager;
pub mod state_machine;
pub mod pairing_flow;
pub mod peer_recovery;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use parking_lot::RwLock;
use tokio::sync::mpsc;

use crate::crypto::traits::MessageEncryptor;
use crate::crypto::plain::PlainEncryptor;
use crate::identity::keypair::KeyPair;
use crate::network::signaling_client::{SignalingClient, SignalingEvent};
use crate::network::reconnect_manager::{ReconnectManager, ReconnectAction};
use crate::network::health_monitor::HealthMonitor;
use crate::protocol::pairing::PairingCode;
use crate::protocol::signaling::{SignalingCommand, SignalingMessage};
use crate::protocol::webrtc_types::*;
use crate::storage::{ContactStore, MessageStore, SettingsStore};

use self::peer_manager::{IceCandidateData, PeerManager};
use self::peer_recovery::PeerRecovery;
use self::state_machine as sm;

/// 引擎内部状态
struct EngineInner {
    /// 我的 peer ID
    my_peer_id: String,
    /// 密钥对
    key_pair: KeyPair,
    /// 信令客户端
    signaling: SignalingClient,
    /// peer 状态管理
    peer_manager: PeerManager,
    /// 重连管理器
    reconnect_manager: ReconnectManager,
    /// 心跳监控器
    health_monitor: HealthMonitor,
    /// P2P 恢复逻辑
    peer_recovery: PeerRecovery,
    /// 加密器（v0.0.3 使用明文）
    encryptor: Box<dyn MessageEncryptor>,
    /// 存储
    message_store: MessageStore,
    contact_store: ContactStore,
    settings_store: SettingsStore,
    /// 显示器名称
    display_name: String,
    /// 信令服务器地址
    signaling_server: String,
    /// 信令连接状态
    signaling_connected: bool,
    signaling_connecting: bool,
    /// 事件接收器（来自信令）
    signaling_event_rx: Option<mpsc::UnboundedReceiver<SignalingEvent>>,
    /// 事件发送器 → Dart
    dart_event_tx: Option<mpsc::UnboundedSender<P2pEvent>>,
    /// WebrtcCommand 发送器 → Dart
    dart_cmd_tx: Option<mpsc::UnboundedSender<WebrtcCommand>>,
    /// 事件缓冲区（FFI poll 模式使用，Mutex 允许内部可变）
    event_buffer: Arc<parking_lot::Mutex<Vec<P2pEvent>>>,
    /// 命令缓冲区（FFI poll 模式使用）
    cmd_buffer: Arc<parking_lot::Mutex<Vec<WebrtcCommand>>>,
    /// 联系人
    contacts: Vec<ContactData>,
    /// 消息缓存（peer_id → messages）
    messages: HashMap<String, Vec<ChatMessageData>>,
    /// 活跃联系人 ID
    active_contact_id: String,
    /// 错误信息
    last_error: Option<String>,
    /// JTC1 手动模式：等待中的 peer ID
    pending_manual_peer_id: Option<String>,
    /// JTC1：等待出示的应答码
    pending_answer_code: Option<String>,
    /// JTC2：被扫码方的回调 peer ID
    on_paired_from_qr: Option<String>,
}

/// P2P 引擎——线程安全，可 Clone。
#[derive(Clone)]
pub struct P2pEngine {
    inner: Arc<RwLock<EngineInner>>,
}

impl P2pEngine {
    /// 创建新引擎实例。
    pub fn new(storage_path: PathBuf) -> Self {
        let key_pair = KeyPair::generate();
        let peer_id = key_pair.peer_id();
        let default_server = "ws://localhost:3000/ws".to_string();

        let engine = Self {
            inner: Arc::new(RwLock::new(EngineInner {
                my_peer_id: peer_id.clone(),
                key_pair,
                signaling: SignalingClient::new(
                    default_server.clone(),
                    peer_id.clone(),
                    String::new(),
                ),
                peer_manager: PeerManager::new(),
                reconnect_manager: ReconnectManager::new(),
                health_monitor: HealthMonitor::new(),
                peer_recovery: PeerRecovery::new(),
                encryptor: Box::new(PlainEncryptor::default()),
                message_store: MessageStore::new(storage_path.clone()),
                contact_store: ContactStore::new(storage_path.clone()),
                settings_store: SettingsStore::new(storage_path),
                display_name: "我".into(),
                signaling_server: default_server,
                signaling_connected: false,
                signaling_connecting: false,
                signaling_event_rx: None,
                dart_event_tx: None,
                dart_cmd_tx: None,
                event_buffer: Arc::new(parking_lot::Mutex::new(Vec::new())),
                cmd_buffer: Arc::new(parking_lot::Mutex::new(Vec::new())),
                contacts: Vec::new(),
                messages: HashMap::new(),
                active_contact_id: String::new(),
                last_error: None,
                pending_manual_peer_id: None,
                pending_answer_code: None,
                on_paired_from_qr: None,
            })),
        };

        // 加载持久化数据
        {
            let mut inner = engine.inner.write();
            if let Ok(contacts) = inner.contact_store.load_all() {
                inner.contacts = contacts;
            }
            if let Ok(settings) = inner.settings_store.load_all() {
                if let Some(name) = settings.get("displayName") {
                    inner.display_name = name.clone();
                }
                if let Some(server) = settings.get("signalingServer") {
                    inner.signaling_server = server.clone();
                }
            }
        }

        engine
    }

    // ══════════════════════════════════════════════════════════
    // 生命周期
    // ══════════════════════════════════════════════════════════

    /// 设置 Dart 侧的事件接收器和命令接收器。
    pub fn set_dart_channels(
        &self,
        event_tx: mpsc::UnboundedSender<P2pEvent>,
        cmd_tx: mpsc::UnboundedSender<WebrtcCommand>,
    ) {
        let mut inner = self.inner.write();
        inner.dart_event_tx = Some(event_tx);
        inner.dart_cmd_tx = Some(cmd_tx);
    }

    /// 处理信令事件（由 tokio 驱动，需要外部事件循环调用）
    pub fn poll_signaling_events(&self) {
        let mut inner = self.inner.write();
        let mut events = Vec::new();

        // 非阻塞地收集所有待处理事件
        if let Some(ref mut rx) = inner.signaling_event_rx {
            loop {
                match rx.try_recv() {
                    Ok(event) => events.push(event),
                    Err(_) => break,
                }
            }
        }

        for event in events {
            self.handle_signaling_event(Some(&mut *inner), event);
        }
    }

    fn handle_signaling_event(
        &self,
        inner: Option<&mut EngineInner>,
        event: SignalingEvent,
    ) {
        // 允许调用者传入已获取的锁，否则自己获取
        if let Some(inner) = inner {
            match event {
                SignalingEvent::Connected => {
                    inner.signaling_connected = true;
                    inner.signaling_connecting = false;
                    inner.reconnect_manager.on_connected();
                    inner.health_monitor.on_connected();
                    // 恢复 P2P 连接
                    self.recover_peer_connections(inner);
                    self.emit_event_inner(inner, P2pEvent::SignalingStateChanged { connected: true });
                }
                SignalingEvent::Disconnected => {
                    inner.signaling_connected = false;
                    inner.signaling_connecting = false;
                    inner.signaling_event_rx = None;
                    inner.health_monitor.on_disconnected();
                    inner.reconnect_manager.on_disconnected();
                    self.emit_event_inner(inner, P2pEvent::SignalingStateChanged { connected: false });
                }
                SignalingEvent::Message(msg) => {
                    inner.health_monitor.on_message_received();
                    self.handle_signaling_message_inner(inner, msg);
                }
                SignalingEvent::Error(e) => {
                    self.emit_event_inner(inner, P2pEvent::Error { message: e });
                }
            }
        }
    }

    fn emit_event_inner(&self, inner: &EngineInner, event: P2pEvent) {
        inner.event_buffer.lock().push(event.clone());
        if let Some(ref tx) = inner.dart_event_tx {
            let _ = tx.send(event);
        }
    }

    fn emit_cmd_inner(&self, inner: &EngineInner, cmd: WebrtcCommand) {
        inner.cmd_buffer.lock().push(cmd.clone());
        if let Some(ref tx) = inner.dart_cmd_tx {
            let _ = tx.send(cmd);
        }
    }

    fn emit_cmds_inner(&self, inner: &EngineInner, cmds: Vec<WebrtcCommand>) {
        for cmd in cmds {
            self.emit_cmd_inner(inner, cmd);
        }
    }

    /// 信令重连后恢复所有活跃 peer 连接
    fn recover_peer_connections(&self, inner: &mut EngineInner) {
        let active_peers = inner.peer_manager.active_peer_ids();
        if !active_peers.is_empty() {
            tracing::info!("恢复 {} 个 peer 连接", active_peers.len());
            let commands = inner.peer_recovery.recover_peers(active_peers);
            for cmd in commands {
                let _ = inner.signaling.send(cmd);
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // 信令消息处理
    // ══════════════════════════════════════════════════════════

    fn handle_signaling_message_inner(&self, inner: &mut EngineInner, msg: SignalingMessage) {
        match msg {
            SignalingMessage::Registered { .. } => {
                // 已通过 SignalingEvent::Connected 处理
            }
            SignalingMessage::Pong => {
                inner.health_monitor.on_pong_received();
            }
            SignalingMessage::PeerOnline { peer_id } => {
                // 更新联系人在线状态
                let name = inner.contacts.iter_mut().find(|c| c.peer_id == peer_id).map(|c| {
                    c.online = true;
                    c.display_name.clone()
                });
                if let Some(name) = name {
                    self.emit_event_inner(inner, P2pEvent::ContactUpdated {
                        peer_id: peer_id.clone(),
                        display_name: name,
                        online: true,
                    });
                }
            }
            SignalingMessage::PeerOffline { peer_id } => {
                let name = inner.contacts.iter_mut().find(|c| c.peer_id == peer_id).map(|c| {
                    c.online = false;
                    c.last_seen_ms = Some(chrono::Utc::now().timestamp_millis());
                    c.display_name.clone()
                });
                if let Some(name) = name {
                    self.emit_event_inner(inner, P2pEvent::ContactUpdated {
                        peer_id: peer_id.clone(),
                        display_name: name,
                        online: false,
                    });
                }
            }
            SignalingMessage::PairConnect { from_id, display_name } => {
                // 被扫码方：有人扫码配对，创建联系人
                if !inner.contacts.iter().any(|c| c.peer_id == from_id) {
                    let contact = ContactData {
                        peer_id: from_id.clone(),
                        display_name: display_name.clone(),
                        online: false,
                        last_seen_ms: None,
                    };
                    inner.contacts.push(contact);
                    let _ = inner.contact_store.upsert(&ContactData {
                        peer_id: from_id.clone(),
                        display_name: display_name.clone(),
                        online: false,
                        last_seen_ms: None,
                    });
                }
                inner.active_contact_id = from_id.clone();
                self.emit_event_inner(inner, P2pEvent::PairConnected {
                    peer_id: from_id,
                    display_name: display_name.clone(),
                });
            }
            SignalingMessage::SdpOffer { from_id, sdp } => {
                let sdp_str = sdp.to_string();
                let sdp_map: HashMap<String, serde_json::Value> =
                    serde_json::from_str(&sdp_str).unwrap_or_default();
                let sdp_type = sdp_map
                    .get("type")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                match sdp_type {
                    "offer" => {
                        // Answer 侧：收到 offer
                        if !inner.peer_manager.contains(&from_id) {
                            inner.peer_manager.create_peer(&from_id, ConnectionMode::Signaling);
                            let cmds = sm::start_answer_flow(&from_id);
                            self.emit_cmds_inner(inner, cmds);
                        }
                        let cmds = sm::on_answer_peer_created(&from_id, &sdp_str);
                        self.emit_cmds_inner(inner, cmds);
                        self.emit_event_inner(inner, P2pEvent::ConnectionPhaseChanged {
                            peer_id: from_id.clone(),
                            phase: ConnectionPhase::Connecting,
                        });
                    }
                    "answer" => {
                        // Offer 侧：收到 answer
                        let cmds = sm::on_receive_answer(&from_id, &sdp_str);
                        self.emit_cmds_inner(inner, cmds);
                        self.emit_event_inner(inner, P2pEvent::ConnectionPhaseChanged {
                            peer_id: from_id,
                            phase: ConnectionPhase::Exchanging,
                        });
                    }
                    _ => {}
                }
            }
            SignalingMessage::IceCandidate { from_id, candidate } => {
                let cand_map: HashMap<String, serde_json::Value> =
                    serde_json::from_str(&candidate.to_string()).unwrap_or_default();
                let cand_str = cand_map
                    .get("candidate")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let sdp_mid = cand_map
                    .get("sdpMid")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                let sdp_m_line_index = cand_map.get("sdpMLineIndex").and_then(|v| v.as_i64()).map(|i| i as i32);

                // Trickle ICE：可能在 offer 之前到达
                if inner.peer_manager.contains(&from_id) {
                    inner.peer_manager.add_pending_ice(
                        &from_id,
                        IceCandidateData {
                            candidate: cand_str.clone(),
                            sdp_mid: sdp_mid.clone(),
                            sdp_m_line_index,
                        },
                    );
                }

                let cmds = sm::add_remote_ice(&from_id, &cand_str, sdp_mid.as_deref(), sdp_m_line_index);
                self.emit_cmds_inner(inner, cmds);
            }
            SignalingMessage::ConnectRequest { from_id } => {
                // 收到连接请求，自动接受
                let _ = inner.signaling.send(SignalingCommand::AcceptConnect {
                    target_id: from_id.clone(),
                });
            }
            SignalingMessage::Error { message } => {
                self.emit_event_inner(inner, P2pEvent::Error { message });
            }
            _ => {}
        }
    }

    // ══════════════════════════════════════════════════════════
    // Dart → Rust 回调（WebRTC 操作完成）
    // ══════════════════════════════════════════════════════════

    /// Dart 创建了 PeerConnection
    pub fn on_peer_connection_created(&self, peer_id: &str, is_offer_side: bool) {
        let mut inner = self.inner.write();
        if is_offer_side {
            let cmds = sm::on_offer_peer_created(peer_id);
            self.emit_cmds_inner(&inner, cmds);
        }
        inner.peer_manager.set_phase(peer_id, ConnectionPhase::Connecting);
        self.emit_event_inner(&inner, P2pEvent::ConnectionPhaseChanged {
            peer_id: peer_id.to_string(),
            phase: ConnectionPhase::Connecting,
        });
    }

    /// Dart 获得了本地 SDP
    pub fn on_local_description(&self, peer_id: &str, sdp: &str, sdp_type: &str) {
        let mut inner = self.inner.write();

        match sdp_type {
            "offer" => {
                let cmds = sm::on_offer_local_desc(peer_id, sdp);
                self.emit_cmds_inner(&inner, cmds);
                inner.peer_manager.set_phase(peer_id, ConnectionPhase::IceGathering);
            }
            "answer" => {
                let cmds = sm::on_answer_local_desc(peer_id, sdp);
                self.emit_cmds_inner(&inner, cmds);
                inner.peer_manager.set_phase(peer_id, ConnectionPhase::IceGathering);
            }
            _ => {}
        }

        self.emit_event_inner(&inner, P2pEvent::ConnectionPhaseChanged {
            peer_id: peer_id.to_string(),
            phase: ConnectionPhase::IceGathering,
        });
    }

    /// Dart 收到 ICE 候选（本端 Trickle ICE 回调）
    pub fn on_ice_candidate(
        &self,
        peer_id: &str,
        candidate: &str,
        sdp_mid: Option<&str>,
        sdp_m_line_index: Option<i32>,
    ) {
        let inner = self.inner.read();
        // 通过信令转发给对端（信令模式）
        if inner.signaling_connected {
            let cand_json = serde_json::json!({
                "candidate": candidate,
                "sdpMid": sdp_mid,
                "sdpMLineIndex": sdp_m_line_index,
            });

            let _ = inner.signaling.send(SignalingCommand::IceCandidate {
                target_id: peer_id.to_string(),
                candidate: cand_json,
            });
        }

        // JTC1 手动模式：收集候选
        let mut inner = self.inner.write();
        inner.peer_manager.add_manual_ice(
            peer_id,
            IceCandidateData {
                candidate: candidate.to_string(),
                sdp_mid: sdp_mid.map(|s| s.to_string()),
                sdp_m_line_index,
            },
        );
    }

    /// Dart 报告 ICE 收集完成
    pub fn on_ice_gathering_complete(&self, peer_id: &str) {
        let mut inner = self.inner.write();

        // 获取已收集的本地 SDP
        inner.peer_manager.set_phase(peer_id, ConnectionPhase::Exchanging);
        self.emit_event_inner(&inner, P2pEvent::ConnectionPhaseChanged {
            peer_id: peer_id.to_string(),
            phase: ConnectionPhase::Exchanging,
        });

        // 信令模式：ICE 收集完成后，引擎已在之前通过 signaling_client 发送 SDP
        // （在 on_local_description 中已发送）
    }

    /// Dart 报告 DataChannel 已打开
    pub fn on_data_channel_open(&self, peer_id: &str) {
        let mut inner = self.inner.write();
        inner.peer_manager.set_phase(peer_id, ConnectionPhase::Connected);
        self.emit_event_inner(&inner, P2pEvent::ConnectionStateChanged {
            peer_id: peer_id.to_string(),
            connected: true,
        });
        self.emit_event_inner(&inner, P2pEvent::ConnectionPhaseChanged {
            peer_id: peer_id.to_string(),
            phase: ConnectionPhase::Connected,
        });

        // 更新联系人状态
        if let Some(contact) = inner.contacts.iter_mut().find(|c| c.peer_id == peer_id) {
            contact.online = true;
        }
    }

    /// Dart 收到 DataChannel 消息
    pub fn on_data_channel_message(&self, peer_id: &str, data: &str) {
        let inner = self.inner.write();
        let msg = ChatMessageData {
            id: format!("msg_{}", chrono::Utc::now().timestamp_millis()),
            sender_id: peer_id.to_string(),
            content: data.to_string(),
            timestamp_ms: chrono::Utc::now().timestamp_millis(),
            is_mine: false,
        };

        // 存储
        let _ = inner.message_store.save_message(peer_id, &msg);

        self.emit_event_inner(&inner, P2pEvent::MessageReceived {
            peer_id: peer_id.to_string(),
            sender_id: peer_id.to_string(),
            content: data.to_string(),
            timestamp_ms: msg.timestamp_ms,
            message_id: msg.id,
        });
    }

    /// Dart 报告 ICE 连接状态变化
    pub fn on_ice_connection_state_change(&self, peer_id: &str, state: &str) {
        let mut inner = self.inner.write();

        match state {
            "checking" => {
                inner.peer_manager.set_phase(peer_id, ConnectionPhase::Connecting);
            }
            "connected" | "completed" => {
                inner.peer_manager.set_phase(peer_id, ConnectionPhase::Connected);
                self.emit_event_inner(&inner, P2pEvent::ConnectionStateChanged {
                    peer_id: peer_id.to_string(),
                    connected: true,
                });
            }
            "failed" | "disconnected" => {
                inner.peer_manager.set_phase(peer_id, ConnectionPhase::Failed);
                self.emit_event_inner(&inner, P2pEvent::ConnectionStateChanged {
                    peer_id: peer_id.to_string(),
                    connected: false,
                });
            }
            _ => {}
        }
    }

    /// Dart 报告 PeerConnection 错误
    pub fn on_peer_connection_failed(&self, peer_id: &str, error: &str) {
        let mut inner = self.inner.write();
        inner.peer_manager.set_phase(peer_id, ConnectionPhase::Failed);
        inner.peer_manager.remove(peer_id);
        inner.signaling.send(SignalingCommand::Connect {
            target_id: peer_id.to_string(),
        }).ok();
        self.emit_event_inner(&inner, P2pEvent::Error {
            message: format!("连接 {peer_id} 失败: {error}"),
        });
        self.emit_event_inner(&inner, P2pEvent::ConnectionStateChanged {
            peer_id: peer_id.to_string(),
            connected: false,
        });
    }

    // ══════════════════════════════════════════════════════════
    // Dart → Rust 方法（UI 触发）
    // ══════════════════════════════════════════════════════════

    /// 连接到信令服务器（异步）
    pub async fn connect_signaling(&self) -> crate::Result<()> {
        let url;
        let peer_id;
        let pubkey;
        {
            let mut inner = self.inner.write();
            inner.signaling_connecting = true;
            inner.last_error = None;
            url = inner.signaling_server.clone();
            peer_id = inner.my_peer_id.clone();
            pubkey = hex::encode(inner.key_pair.public_key_bytes());
            self.emit_event_inner(&inner, P2pEvent::SignalingConnecting);
        }

        {
            let mut inner = self.inner.write();
            inner.signaling = SignalingClient::new(url.clone(), peer_id.clone(), pubkey);
            match inner.signaling.connect().await {
                Ok(event_rx) => {
                    inner.signaling_event_rx = Some(event_rx);
                }
                Err(e) => {
                    inner.signaling_connecting = false;
                    inner.last_error = Some(format!("信令连接失败: {e}"));
                    self.emit_event_inner(&inner, P2pEvent::Error {
                        message: inner.last_error.clone().unwrap(),
                    });
                }
            }
        }

        Ok(())
    }

    /// 通过信令连接到 peer
    pub fn connect_to_peer(&self, peer_id: &str) {
        let mut inner = self.inner.write();
        inner.peer_manager.create_peer(peer_id, ConnectionMode::Signaling);

        // 发送 connect → 开始 offer 流程
        let _ = inner.signaling.send(SignalingCommand::Connect {
            target_id: peer_id.to_string(),
        });

        let cmds = sm::start_offer_flow(peer_id);
        self.emit_cmds_inner(&inner, cmds);
    }

    /// 扫码方：接受 JTC2 配对码并连接
    pub async fn accept_pairing_code(&self, code: &str) -> crate::Result<()> {
        let pairing = PairingCode::decode(code)?;
        let target_server = pairing.signaling_server.clone();
        let peer_id = pairing.peer_id.clone();
        let display_name = pairing.display_name.clone();

        {
            let mut inner = self.inner.write();
            // 创建联系人
            if !inner.contacts.iter().any(|c| c.peer_id == peer_id) {
                let contact = ContactData {
                    peer_id: peer_id.clone(),
                    display_name: display_name.clone(),
                    online: false,
                    last_seen_ms: None,
                };
                inner.contacts.push(contact.clone());
                let _ = inner.contact_store.upsert(&contact);
            }
            inner.active_contact_id = peer_id.clone();
        }

        // 如果需要切换信令服务器
        if let Some(server) = target_server {
            let current = {
                let inner = self.inner.read();
                inner.signaling_server.clone()
            };
            if current != server {
                {
                    let mut inner = self.inner.write();
                    inner.signaling_server = server.clone();
                }
                self.connect_signaling().await?;
                // 等待一小段让 peer_online 消息到达
                tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            }
        }

        // 通过信令发起 connect_via_pair
        {
            let inner = self.inner.read();
            let _ = inner.signaling.send(SignalingCommand::ConnectViaPair {
                target_peer_id: peer_id.clone(),
                display_name: inner.display_name.clone(),
            });
        }

        self.emit_event_inner(&self.inner.read(), P2pEvent::ConnectionPhaseChanged {
            peer_id: peer_id.clone(),
            phase: ConnectionPhase::Exchanging,
        });

        Ok(())
    }

    /// 被扫码方：生成 JTC2 QR 配对码
    pub fn generate_pairing_code(&self) -> PairingCode {
        let inner = self.inner.read();
        let code = pairing_flow::prepare_jtc2_qr(
            &inner.my_peer_id,
            &inner.display_name,
            Some(&inner.signaling_server),
        );

        // 通过信令发送 pair_intent
        let _ = inner.signaling.send(SignalingCommand::PairIntent {
            peer_id: inner.my_peer_id.clone(),
            display_name: inner.display_name.clone(),
        });

        code
    }

    /// 发送聊天消息
    pub fn send_message(&self, peer_id: &str, text: &str) {
        let inner = self.inner.read();
        let msg = ChatMessageData {
            id: format!("msg_{}", chrono::Utc::now().timestamp_millis()),
            sender_id: inner.my_peer_id.clone(),
            content: text.to_string(),
            timestamp_ms: chrono::Utc::now().timestamp_millis(),
            is_mine: true,
        };

        // 存储
        let _ = inner.message_store.save_message(peer_id, &msg);

        // 发送本地事件让 UI 更新
        self.emit_event_inner(&inner, P2pEvent::MessageReceived {
            peer_id: peer_id.to_string(),
            sender_id: inner.my_peer_id.clone(),
            content: text.to_string(),
            timestamp_ms: msg.timestamp_ms,
            message_id: msg.id,
        });

        // 通过 DataChannel 发送
        let cmds = sm::send_message(peer_id, text);
        self.emit_cmds_inner(&inner, cmds);
    }

    // ══════════════════════════════════════════════════════════
    // 联系人管理
    // ══════════════════════════════════════════════════════════

    pub fn add_contact(&self, peer_id: &str, display_name: &str) {
        let mut inner = self.inner.write();
        if !inner.contacts.iter().any(|c| c.peer_id == peer_id) {
            let contact = ContactData {
                peer_id: peer_id.to_string(),
                display_name: display_name.to_string(),
                online: false,
                last_seen_ms: None,
            };
            inner.contacts.push(contact.clone());
            let _ = inner.contact_store.upsert(&contact);
        }
    }

    pub fn remove_contact(&self, peer_id: &str) {
        let mut inner = self.inner.write();
        inner.contacts.retain(|c| c.peer_id != peer_id);
        let _ = inner.contact_store.remove(peer_id);
        let _ = inner.message_store.delete_peer_messages(peer_id);
    }

    pub fn get_contacts(&self) -> Vec<ContactData> {
        self.inner.read().contacts.clone()
    }

    pub fn get_messages(&self, peer_id: &str) -> Vec<ChatMessageData> {
        let inner = self.inner.read();
        inner
            .message_store
            .load_messages(peer_id)
            .unwrap_or_default()
    }

    // ══════════════════════════════════════════════════════════
    // 设置
    // ══════════════════════════════════════════════════════════

    pub fn set_display_name(&self, name: &str) {
        let mut inner = self.inner.write();
        inner.display_name = name.to_string();
        let _ = inner.settings_store.set("displayName", name);
    }

    pub fn set_signaling_server(&self, url: &str) {
        let mut inner = self.inner.write();
        inner.signaling_server = url.to_string();
        let _ = inner.settings_store.set("signalingServer", url);
    }

    pub fn set_auto_connect(&self, enabled: bool) {
        let inner = self.inner.read();
        let _ = inner.settings_store.set("autoConnect", &enabled.to_string());
    }

    pub fn set_notifications_enabled(&self, enabled: bool) {
        let inner = self.inner.read();
        let _ = inner
            .settings_store
            .set("notificationsEnabled", &enabled.to_string());
    }

    // ══════════════════════════════════════════════════════════
    // Getters
    // ══════════════════════════════════════════════════════════

    pub fn my_peer_id(&self) -> String {
        self.inner.read().my_peer_id.clone()
    }

    pub fn display_name(&self) -> String {
        self.inner.read().display_name.clone()
    }

    pub fn signaling_connected(&self) -> bool {
        self.inner.read().signaling_connected
    }

    pub fn signaling_connecting(&self) -> bool {
        self.inner.read().signaling_connecting
    }

    pub fn active_contact_id(&self) -> String {
        self.inner.read().active_contact_id.clone()
    }

    pub fn set_active_contact(&self, peer_id: &str) {
        self.inner.write().active_contact_id = peer_id.to_string();
    }

    pub fn get_peer_phase(&self, peer_id: &str) -> ConnectionPhase {
        self.inner.read().peer_manager.get_phase(peer_id)
    }

    pub fn is_peer_connected(&self, peer_id: &str) -> bool {
        matches!(
            self.inner.read().peer_manager.get_phase(peer_id),
            ConnectionPhase::Connected
        )
    }

    pub fn pending_answer_code(&self) -> Option<String> {
        self.inner.read().pending_answer_code.clone()
    }

    pub fn clear_pending_answer(&self) {
        self.inner.write().pending_answer_code = None;
    }

    pub fn last_error(&self) -> Option<String> {
        self.inner.read().last_error.clone()
    }

    // ══════════════════════════════════════════════════════════
    // JTC1 手动 SDP 交换（降级方案）
    // ══════════════════════════════════════════════════════════

    /// 生成 JTC1 连接码（offer 侧）
    pub fn generate_connection_code(&self, peer_id: &str) -> crate::Result<String> {
        let mut inner = self.inner.write();
        inner.peer_manager.create_peer(peer_id, ConnectionMode::Manual);
        inner.pending_manual_peer_id = Some(peer_id.to_string());

        let cmds = sm::start_jtc1_offer_flow(peer_id);
        self.emit_cmds_inner(&inner, cmds);

        // 注意：实际的连接码编码在 Dart 侧 ICE 收集完成后，
        // Dart 调用 on_local_description + on_ice_gathering_complete，
        // 然后调用 encode_jtc1_offer
        Ok("JTC1_PENDING".to_string())
    }

    /// 编码 JTC1 offer（在 ICE 收集完成后调用）
    pub fn encode_jtc1_offer_data(
        &self,
        peer_id: &str,
        sdp: serde_json::Value,
    ) -> crate::Result<String> {
        let mut inner = self.inner.write();
        let candidates: Vec<serde_json::Value> = inner
            .peer_manager
            .take_manual_ice(peer_id)
            .iter()
            .map(|c| {
                serde_json::json!({
                    "candidate": c.candidate,
                    "sdpMid": c.sdp_mid,
                    "sdpMLineIndex": c.sdp_m_line_index,
                })
            })
            .collect();
        pairing_flow::encode_jtc1_offer(sdp, candidates)
    }

    /// 接受 JTC1 连接码（answer 侧）
    pub fn accept_connection_code(&self, code: &str) -> crate::Result<String> {
        let data = pairing_flow::decode_jtc1(code)?;
        let peer_id = format!("peer_{}", chrono::Utc::now().timestamp_millis());

        let mut inner = self.inner.write();
        inner.peer_manager.create_peer(&peer_id, ConnectionMode::Manual);
        inner.pending_manual_peer_id = Some(peer_id.clone());

        let sdp_str = data.sdp.to_string();
        let cmds = sm::start_jtc1_answer_flow(&peer_id, &sdp_str);
        self.emit_cmds_inner(&inner, cmds);

        Ok(peer_id) // 返回临时 peer_id
    }

    /// 编码 JTC1 answer（在 answer 侧 ICE 收集完成后调用）
    pub fn encode_jtc1_answer_data(
        &self,
        peer_id: &str,
        sdp: serde_json::Value,
    ) -> crate::Result<String> {
        let mut inner = self.inner.write();
        let candidates: Vec<serde_json::Value> = inner
            .peer_manager
            .take_manual_ice(peer_id)
            .iter()
            .map(|c| {
                serde_json::json!({
                    "candidate": c.candidate,
                    "sdpMid": c.sdp_mid,
                    "sdpMLineIndex": c.sdp_m_line_index,
                })
            })
            .collect();
        let answer = pairing_flow::encode_jtc1_answer(sdp, candidates)?;
        inner.pending_answer_code = Some(answer.clone());
        Ok(answer)
    }

    /// 接受 JTC1 应答码（offer 侧）
    pub fn accept_answer_code(&self, peer_id: &str, answer_code: &str) -> crate::Result<()> {
        let data = pairing_flow::decode_jtc1(answer_code)?;
        let sdp_str = data.sdp.to_string();

        let mut inner = self.inner.write();

        // setRemoteDescription(answer)
        let cmds = sm::on_receive_answer(peer_id, &sdp_str);
        self.emit_cmds_inner(&inner, cmds);

        // 添加对端的 ICE 候选
        for cand in &data.candidates {
            let cand_str = cand
                .get("candidate")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let sdp_mid = cand.get("sdpMid").and_then(|v| v.as_str());
            let sdp_m_line_index = cand.get("sdpMLineIndex").and_then(|v| v.as_i64());

            let cmds = sm::add_remote_ice(
                peer_id,
                cand_str,
                sdp_mid,
                sdp_m_line_index.map(|i| i as i32),
            );
            self.emit_cmds_inner(&inner, cmds);
        }

        inner.pending_manual_peer_id = None;
        inner.pending_answer_code = None;

        Ok(())
    }

    /// 统一入口：处理从深链接/粘贴的连接码
    pub fn handle_connection_code(&self, code: &str) -> crate::Result<()> {
        let code_type = code_router::detect_code_type(code);
        match code_type {
            code_router::CodeType::Jtc2 => Err(crate::Error::Protocol(
                "JTC2 配对码需异步处理，请调用 accept_pairing_code".into(),
            )),
            code_router::CodeType::Jtc1 => self.handle_jtc1_code(code),
            code_router::CodeType::Unknown => Err(crate::Error::Protocol("无效的连接码格式".into())),
        }
    }

    /// 处理 JTC1 连接码（offer 或 answer）
    fn handle_jtc1_code(&self, code: &str) -> crate::Result<()> {
        let data = pairing_flow::decode_jtc1(code)?;
        let sdp_type = data.sdp.get("type").and_then(|v| v.as_str()).unwrap_or("");

        if sdp_type == "offer" {
            self.accept_connection_code(code)?;
        } else if sdp_type == "answer" {
            let peer_id = {
                let inner = self.inner.read();
                inner.pending_manual_peer_id.clone()
            };
            if let Some(pid) = peer_id {
                self.accept_answer_code(&pid, code)?;
            } else {
                return Err(crate::Error::Protocol("没有等待中的连接".into()));
            }
        } else {
            return Err(crate::Error::Protocol(
                format!("不支持的 SDP 类型: {sdp_type}").into(),
            ));
        }
        Ok(())
    }

    /// 处理引擎事件（应定期调用以处理信令消息）
    pub fn tick(&self) {
        let mut inner = self.inner.write();

        // 1. 检查重连
        if let Some(action) = inner.reconnect_manager.tick() {
            match action {
                ReconnectAction::Connect => {
                    // 异步重连需要通过事件驱动
                    let url = inner.signaling_server.clone();
                    let peer_id = inner.my_peer_id.clone();
                    let pubkey = hex::encode(inner.key_pair.public_key_bytes());
                    inner.signaling = SignalingClient::new(url, peer_id, pubkey);
                    inner.signaling_connecting = true;
                    self.emit_event_inner(&inner, P2pEvent::SignalingConnecting);
                }
                ReconnectAction::Wait => {}
            }
        }

        // 2. 检查心跳
        if inner.health_monitor.should_send_ping() {
            let _ = inner.signaling.send(SignalingCommand::Ping);
            inner.health_monitor.on_ping_sent();
        }

        // 3. 检查 pong 超时
        if inner.health_monitor.is_pong_timeout() {
            inner.health_monitor.on_disconnected();
            inner.reconnect_manager.on_disconnected();
            inner.signaling_connected = false;
            inner.signaling_connecting = false;
            inner.signaling_event_rx = None;
            self.emit_event_inner(&inner, P2pEvent::SignalingStateChanged { connected: false });
        }

        // 4. 检查 peer 超时
        let timed_out_peers = inner.peer_manager.check_timeouts();
        for peer_id in timed_out_peers {
            tracing::warn!(peer_id = %peer_id, "peer 连接超时");
            inner.peer_manager.remove(&peer_id);
            self.emit_event_inner(&inner, P2pEvent::ConnectionStateChanged {
                peer_id,
                connected: false,
            });
        }

        // 5. 处理信令事件
        drop(inner);
        self.poll_signaling_events();
    }

    /// 释放事件缓冲区（FFI poll 使用）
    pub fn drain_events(&self) -> Vec<P2pEvent> {
        let inner = self.inner.read();
        std::mem::take(&mut *inner.event_buffer.lock())
    }

    /// 释放命令缓冲区（FFI poll 使用）
    pub fn drain_commands(&self) -> Vec<WebrtcCommand> {
        let inner = self.inner.read();
        std::mem::take(&mut *inner.cmd_buffer.lock())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn engine_create() {
        let dir = TempDir::new().unwrap();
        let engine = P2pEngine::new(dir.path().to_path_buf());
        assert!(!engine.my_peer_id().is_empty());
        assert_eq!(engine.display_name(), "我");
    }

    #[test]
    fn contacts_crud() {
        let dir = TempDir::new().unwrap();
        let engine = P2pEngine::new(dir.path().to_path_buf());
        engine.add_contact("peer1", "Alice");
        assert_eq!(engine.get_contacts().len(), 1);
        engine.remove_contact("peer1");
        assert!(engine.get_contacts().is_empty());
    }

    #[test]
    fn settings() {
        let dir = TempDir::new().unwrap();
        let engine = P2pEngine::new(dir.path().to_path_buf());
        engine.set_display_name("舰长");
        assert_eq!(engine.display_name(), "舰长");
    }

    #[test]
    fn test_reconnect_manager_integration() {
        use crate::network::reconnect_manager::{ReconnectManager, ReconnectState, ReconnectAction};

        let mut rm = ReconnectManager::new();

        // 初始状态
        assert_eq!(*rm.state(), ReconnectState::Idle);

        // 连接成功
        rm.on_connected();
        assert_eq!(*rm.state(), ReconnectState::Connected);

        // 断开
        rm.on_disconnected();
        assert!(matches!(rm.state(), ReconnectState::Reconnecting { .. }));

        // 第一次重连
        let action = rm.tick();
        assert_eq!(action, Some(ReconnectAction::Connect));

        // 重连失败
        rm.on_connect_failed();
        assert!(matches!(rm.state(), ReconnectState::Reconnecting { .. }));
    }

    #[test]
    fn test_health_monitor_integration() {
        use crate::network::health_monitor::HealthMonitor;

        let mut hm = HealthMonitor::new();

        // 连接
        hm.on_connected();
        assert!(hm.is_healthy());

        // 发送 ping
        hm.on_ping_sent();
        assert!(hm.is_healthy()); // 还没超时

        // 收到 pong
        hm.on_pong_received();
        assert!(hm.is_healthy());

        // 断开
        hm.on_disconnected();
        assert!(!hm.is_healthy());
    }

    #[test]
    fn test_peer_recovery_integration() {
        use crate::engine::peer_recovery::PeerRecovery;

        let recovery = PeerRecovery::new();
        let peers = vec!["peer1".to_string(), "peer2".to_string()];
        let commands = recovery.recover_peers(peers);
        assert_eq!(commands.len(), 2);

        let empty_commands = recovery.recover_peers(vec![]);
        assert!(empty_commands.is_empty());
    }
}
