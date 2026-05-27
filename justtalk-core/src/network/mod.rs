//! 网络传输 — 信令客户端、重连管理、心跳监控。
//!
//! P2P 连接管理已迁移到 `crate::engine` 模块。

pub mod signaling_client;
pub mod reconnect_manager;
pub mod health_monitor;

pub use signaling_client::{SignalingClient, SignalingConfig, SignalingEvent};
pub use reconnect_manager::{ReconnectManager, ReconnectAction, ReconnectState};
pub use health_monitor::HealthMonitor;
