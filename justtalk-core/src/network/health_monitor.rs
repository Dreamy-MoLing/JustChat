//! 心跳监控器 — 检测信令连接是否健康。
//!
//! 通过定期发送 Ping 和检测 Pong 超时来判断连接是否存活。

use std::time::{Duration, Instant};

/// 心跳监控器
pub struct HealthMonitor {
    /// Ping 发送间隔
    ping_interval: Duration,
    /// Pong 超时时间
    pong_timeout: Duration,
    /// 最后一次收到 Pong 的时间
    last_pong: Option<Instant>,
    /// 最后一次发送 Ping 的时间
    ping_sent_at: Option<Instant>,
    /// 是否已连接
    connected: bool,
}

impl HealthMonitor {
    pub fn new() -> Self {
        Self {
            ping_interval: Duration::from_secs(30),
            pong_timeout: Duration::from_secs(10),
            last_pong: None,
            ping_sent_at: None,
            connected: false,
        }
    }

    /// 连接成功时调用
    pub fn on_connected(&mut self) {
        self.connected = true;
        self.last_pong = Some(Instant::now());
        self.ping_sent_at = None;
    }

    /// 断开时调用
    pub fn on_disconnected(&mut self) {
        self.connected = false;
        self.ping_sent_at = None;
    }

    /// 检查是否需要发送 ping
    pub fn should_send_ping(&self) -> bool {
        if !self.connected {
            return false;
        }
        match self.last_pong {
            Some(last) => last.elapsed() >= self.ping_interval,
            None => true,
        }
    }

    /// 记录 ping 已发送
    pub fn on_ping_sent(&mut self) {
        self.ping_sent_at = Some(Instant::now());
    }

    /// 收到 pong 时调用
    pub fn on_pong_received(&mut self) {
        self.last_pong = Some(Instant::now());
        self.ping_sent_at = None;
    }

    /// 收到任意消息时调用（重置 pong 计时）
    pub fn on_message_received(&mut self) {
        self.last_pong = Some(Instant::now());
        self.ping_sent_at = None;
    }

    /// 检查 pong 是否超时
    pub fn is_pong_timeout(&self) -> bool {
        if !self.connected {
            return false;
        }
        match self.ping_sent_at {
            Some(sent) => sent.elapsed() > self.pong_timeout,
            None => false,
        }
    }

    /// 检查连接是否健康
    pub fn is_healthy(&self) -> bool {
        self.connected && !self.is_pong_timeout()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initial_state_not_connected() {
        let hm = HealthMonitor::new();
        assert!(!hm.should_send_ping());
        assert!(!hm.is_pong_timeout());
        assert!(!hm.is_healthy());
    }

    #[test]
    fn test_connected_should_send_ping() {
        let mut hm = HealthMonitor::new();
        hm.on_connected();
        // 连接后立即应该发送 ping（因为 last_pong 刚设置）
        // 但 ping_interval 是 30s，所以不应该立即发送
        assert!(!hm.should_send_ping());
    }

    #[test]
    fn test_pong_received_resets_timeout() {
        let mut hm = HealthMonitor::new();
        hm.on_connected();
        hm.on_ping_sent();
        assert!(hm.is_pong_timeout() == false); // 刚发送，还没超时
        hm.on_pong_received();
        assert!(!hm.is_pong_timeout());
    }

    #[test]
    fn test_disconnected_not_healthy() {
        let mut hm = HealthMonitor::new();
        hm.on_connected();
        hm.on_disconnected();
        assert!(!hm.is_healthy());
    }
}
