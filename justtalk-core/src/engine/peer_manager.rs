//! 每 peer 连接状态管理。
//!
//! 跟踪每个 peer 的 WebRTC 连接阶段、ICE 候选缓冲、超时计时器。

use std::collections::HashMap;
use std::time::Instant;

use crate::protocol::webrtc_types::{ConnectionMode, ConnectionPhase};

/// 默认连接超时（秒）
pub const CONNECTION_TIMEOUT_SECS: u64 = 15;

/// 单个 peer 的连接状态
#[derive(Debug, Clone)]
pub struct PeerState {
    pub peer_id: String,
    pub connection_mode: ConnectionMode,
    pub phase: ConnectionPhase,
    /// 连接开始时间（用于超时检测）
    pub started_at: Instant,
    /// Trickle ICE: 在 setRemoteDescription 前到达的候选暂存于此
    pub pending_ice: Vec<IceCandidateData>,
    /// JTC1 手动模式: 收集到的所有候选
    pub manual_ice: Vec<IceCandidateData>,
    /// SDP offer/answer 缓存
    pub local_sdp: Option<String>,
    pub local_sdp_type: Option<String>,
}

/// ICE 候选数据
#[derive(Debug, Clone)]
pub struct IceCandidateData {
    pub candidate: String,
    pub sdp_mid: Option<String>,
    pub sdp_m_line_index: Option<i32>,
}

impl PeerState {
    pub fn new(peer_id: String, mode: ConnectionMode) -> Self {
        Self {
            peer_id,
            connection_mode: mode,
            phase: ConnectionPhase::Idle,
            started_at: Instant::now(),
            pending_ice: Vec::new(),
            manual_ice: Vec::new(),
            local_sdp: None,
            local_sdp_type: None,
        }
    }

    /// 连接是否超时
    pub fn is_timed_out(&self) -> bool {
        self.started_at.elapsed().as_secs() >= CONNECTION_TIMEOUT_SECS
    }

    /// 距超时还剩多少秒
    pub fn remaining_secs(&self) -> u64 {
        CONNECTION_TIMEOUT_SECS.saturating_sub(self.started_at.elapsed().as_secs())
    }
}

/// Peer 管理器：维护所有 peer 的状态
#[derive(Debug, Clone, Default)]
pub struct PeerManager {
    peers: HashMap<String, PeerState>,
}

impl PeerManager {
    pub fn new() -> Self {
        Self {
            peers: HashMap::new(),
        }
    }

    /// 创建新 peer 状态（如已存在则重置）
    pub fn create_peer(&mut self, peer_id: &str, mode: ConnectionMode) {
        self.peers.insert(
            peer_id.to_string(),
            PeerState::new(peer_id.to_string(), mode),
        );
    }

    /// 获取 peer 状态
    pub fn get(&self, peer_id: &str) -> Option<&PeerState> {
        self.peers.get(peer_id)
    }

    /// 获取 peer 状态（可变）
    pub fn get_mut(&mut self, peer_id: &str) -> Option<&mut PeerState> {
        self.peers.get_mut(peer_id)
    }

    /// 删除 peer 并返回其状态
    pub fn remove(&mut self, peer_id: &str) -> Option<PeerState> {
        self.peers.remove(peer_id)
    }

    /// 设置连接阶段
    pub fn set_phase(&mut self, peer_id: &str, phase: ConnectionPhase) {
        if let Some(peer) = self.peers.get_mut(peer_id) {
            peer.phase = phase;
        }
    }

    /// 获取连接阶段
    pub fn get_phase(&self, peer_id: &str) -> ConnectionPhase {
        self.peers
            .get(peer_id)
            .map(|p| p.phase)
            .unwrap_or(ConnectionPhase::Idle)
    }

    /// 暂存 ICE 候选（Trickle ICE：offer 到达前收到的候选）
    pub fn add_pending_ice(&mut self, peer_id: &str, candidate: IceCandidateData) {
        if let Some(peer) = self.peers.get_mut(peer_id) {
            peer.pending_ice.push(candidate);
        }
    }

    /// 取出并清空暂存的 ICE 候选（setRemoteDescription 后调用）
    pub fn flush_pending_ice(&mut self, peer_id: &str) -> Vec<IceCandidateData> {
        self.peers
            .get_mut(peer_id)
            .map(|p| std::mem::take(&mut p.pending_ice))
            .unwrap_or_default()
    }

    /// 添加手动模式 ICE 候选（JTC1）
    pub fn add_manual_ice(&mut self, peer_id: &str, candidate: IceCandidateData) {
        if let Some(peer) = self.peers.get_mut(peer_id) {
            peer.manual_ice.push(candidate);
        }
    }

    /// 取出所有手动 ICE 候选
    pub fn take_manual_ice(&mut self, peer_id: &str) -> Vec<IceCandidateData> {
        self.peers
            .get_mut(peer_id)
            .map(|p| std::mem::take(&mut p.manual_ice))
            .unwrap_or_default()
    }

    /// 检查是否有 peer 超时
    pub fn check_timeouts(&self) -> Vec<String> {
        self.peers
            .iter()
            .filter(|(_, state)| {
                state.phase != ConnectionPhase::Connected
                    && state.phase != ConnectionPhase::Failed
                    && state.is_timed_out()
            })
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// peer 是否存在
    pub fn contains(&self, peer_id: &str) -> bool {
        self.peers.contains_key(peer_id)
    }

    /// 所有未失败/未断开的 peer ID
    pub fn active_peer_ids(&self) -> Vec<String> {
        self.peers
            .iter()
            .filter(|(_, s)| {
                s.phase != ConnectionPhase::Failed
            })
            .map(|(id, _)| id.clone())
            .collect()
    }
}
