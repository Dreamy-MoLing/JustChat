//! WebRTC 命令和事件类型 — Rust↔Dart FFI 边界定义。
//!
//! Rust 引擎通过 `WebrtcCommand` 告诉 Dart WebrtcAdapter 执行什么平台操作，
//! Dart UI 通过 `P2pEvent` 接收引擎推送的状态变化。

use serde::{Deserialize, Serialize};

/// Rust 发送给 Dart WebrtcAdapter 的 WebRTC 操作命令。
///
/// Dart 侧监听此 stream，逐一执行对应的 flutter_webrtc API 调用，
/// 完成后通过 engine.on_xxx() 回调 Rust。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum WebrtcCommand {
    /// 创建 RTCPeerConnection
    CreatePeerConnection {
        peer_id: String,
        /// JSON 序列化的 iceServers 配置
        ice_servers_json: String,
    },
    /// 创建 DataChannel（必须在 createOffer 前）
    CreateDataChannel {
        peer_id: String,
        label: String,
    },
    /// 创建 SDP Offer
    CreateOffer { peer_id: String },
    /// 创建 SDP Answer
    CreateAnswer { peer_id: String },
    /// 设置本地 SDP
    SetLocalDescription {
        peer_id: String,
        sdp: String,
        sdp_type: String,
    },
    /// 设置远端 SDP
    SetRemoteDescription {
        peer_id: String,
        sdp: String,
        sdp_type: String,
    },
    /// 添加 ICE 候选
    AddIceCandidate {
        peer_id: String,
        candidate: String,
        sdp_mid: Option<String>,
        sdp_m_line_index: Option<i32>,
    },
    /// 等待 ICE 收集完成（半 Trickle 策略）
    WaitForIceGathering {
        peer_id: String,
        timeout_secs: u32,
    },
    /// 通过 DataChannel 发送消息
    SendDataChannelMessage {
        peer_id: String,
        data: String,
    },
    /// 关闭 PeerConnection
    ClosePeerConnection { peer_id: String },
}

/// Rust 引擎推送给 Dart UI 的状态变更事件。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum P2pEvent {
    /// 收到新消息
    MessageReceived {
        peer_id: String,
        sender_id: String,
        content: String,
        timestamp_ms: i64,
        message_id: String,
    },
    /// 连接状态变化
    ConnectionStateChanged {
        peer_id: String,
        connected: bool,
    },
    /// 连接阶段变化（用于 UI 展示连接进度）
    ConnectionPhaseChanged {
        peer_id: String,
        phase: ConnectionPhase,
    },
    /// 信令服务器连接状态
    SignalingStateChanged { connected: bool },
    /// 错误
    Error { message: String },
    /// 有人扫码配对（被扫码方通知 UI）
    PairConnected {
        peer_id: String,
        display_name: String,
    },
    /// 联系人更新
    ContactUpdated {
        peer_id: String,
        display_name: String,
        online: bool,
    },
    /// 信令连接中
    SignalingConnecting,
    /// 信令已连接
    SignalingConnected,
    /// 信令已断开
    SignalingDisconnected { reason: String },
    /// 请求重连
    ReconnectRequested,
}

/// WebRTC 连接阶段 —— 对应 UI 连接状态栏的展示。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionPhase {
    Idle,
    Connecting,
    IceGathering,
    Exchanging,
    Connected,
    Failed,
}

/// 连接模式
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionMode {
    Signaling,
    Manual,
}

/// 联系人数据（FFI 传输用）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContactData {
    pub peer_id: String,
    pub display_name: String,
    pub online: bool,
    pub last_seen_ms: Option<i64>,
}

/// 聊天消息数据（FFI 传输用）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessageData {
    pub id: String,
    pub sender_id: String,
    pub content: String,
    pub timestamp_ms: i64,
    pub is_mine: bool,
}
