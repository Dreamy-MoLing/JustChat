//! 网络传输 — 信令客户端。
//!
//! P2P 连接管理已迁移到 `crate::engine` 模块。

pub mod signaling_client;

pub use signaling_client::{SignalingClient, SignalingConfig, SignalingEvent};
