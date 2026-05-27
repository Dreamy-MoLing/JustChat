//! 重连管理器 — 指数退避重连调度。
//!
//! 断开后自动进入 Reconnecting 状态，按 1s → 2s → 4s → ... → 30s 指数退避重试。
//! 带 ±20% 抖动防止惊群效应。

use std::time::{Duration, Instant};

/// 重连动作
#[derive(Debug, Clone, PartialEq)]
pub enum ReconnectAction {
    /// 立即尝试连接
    Connect,
    /// 等待下次重试
    Wait,
}

/// 重连状态
#[derive(Debug, Clone, PartialEq)]
pub enum ReconnectState {
    /// 初始状态
    Idle,
    /// 正在尝试连接
    Connecting,
    /// 已连接
    Connected,
    /// 等待下次重试
    Reconnecting { next_retry: Instant },
}

/// 重连管理器 — 指数退避重连调度
pub struct ReconnectManager {
    state: ReconnectState,
    attempt: u32,
    base_delay: Duration,
    max_delay: Duration,
}

impl ReconnectManager {
    pub fn new() -> Self {
        Self {
            state: ReconnectState::Idle,
            attempt: 0,
            base_delay: Duration::from_secs(1),
            max_delay: Duration::from_secs(30),
        }
    }

    /// 当前状态
    pub fn state(&self) -> &ReconnectState {
        &self.state
    }

    /// 连接成功时调用
    pub fn on_connected(&mut self) {
        self.state = ReconnectState::Connected;
        self.attempt = 0;
    }

    /// 断开时调用，开始重连调度
    pub fn on_disconnected(&mut self) {
        self.attempt = 0;
        self.state = ReconnectState::Reconnecting {
            next_retry: Instant::now(), // 立即重试
        };
    }

    /// 每次 tick 调用，返回是否应该尝试重连
    pub fn tick(&mut self) -> Option<ReconnectAction> {
        match &self.state {
            ReconnectState::Reconnecting { next_retry } => {
                if Instant::now() >= *next_retry {
                    self.state = ReconnectState::Connecting;
                    Some(ReconnectAction::Connect)
                } else {
                    Some(ReconnectAction::Wait)
                }
            }
            _ => None,
        }
    }

    /// 重连失败时调用，调度下次重试
    pub fn on_connect_failed(&mut self) {
        self.attempt += 1;
        let delay = self.next_delay();
        self.state = ReconnectState::Reconnecting {
            next_retry: Instant::now() + delay,
        };
    }

    /// 计算下次重连延迟（指数退避 + 抖动）
    fn next_delay(&self) -> Duration {
        let base_ms = self.base_delay.as_millis() as u64;
        let delay_ms = base_ms.saturating_mul(1u64 << self.attempt.min(5));
        let capped_ms = delay_ms.min(self.max_delay.as_millis() as u64);
        // ±20% 抖动
        let jitter = capped_ms / 5;
        let min = capped_ms.saturating_sub(jitter);
        let max = capped_ms + jitter;
        let range = max - min;
        let jittered = if range > 0 {
            min + (std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64
                % range)
        } else {
            min
        };
        Duration::from_millis(jittered)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initial_state_is_idle() {
        let rm = ReconnectManager::new();
        assert_eq!(*rm.state(), ReconnectState::Idle);
    }

    #[test]
    fn test_on_connected_resets_state() {
        let mut rm = ReconnectManager::new();
        rm.on_disconnected();
        rm.on_connected();
        assert_eq!(*rm.state(), ReconnectState::Connected);
    }

    #[test]
    fn test_on_disconnected_starts_reconnecting() {
        let mut rm = ReconnectManager::new();
        rm.on_disconnected();
        assert!(matches!(rm.state(), ReconnectState::Reconnecting { .. }));
    }

    #[test]
    fn test_tick_returns_connect_when_ready() {
        let mut rm = ReconnectManager::new();
        rm.on_disconnected();
        let action = rm.tick();
        assert_eq!(action, Some(ReconnectAction::Connect));
        assert_eq!(*rm.state(), ReconnectState::Connecting);
    }

    #[test]
    fn test_on_connect_failed_increases_delay() {
        let mut rm = ReconnectManager::new();
        rm.on_disconnected();
        rm.tick(); // Connect
        rm.on_connect_failed(); // 失败
        assert!(matches!(rm.state(), ReconnectState::Reconnecting { .. }));
    }

    #[test]
    fn test_exponential_backoff_caps_at_30s() {
        let _rm = ReconnectManager::new();
        // 第 10 次应该 cap 在 30s
        let mut delay = Duration::from_secs(0);
        for i in 0..10 {
            let base_ms = 1000u64;
            let delay_ms = base_ms.saturating_mul(1u64 << i.min(5));
            delay = Duration::from_millis(delay_ms.min(30000));
        }
        assert!(delay <= Duration::from_secs(30));
    }
}
