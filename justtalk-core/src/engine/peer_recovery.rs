//! P2P 恢复逻辑 — 信令重连后恢复现有 peer 连接。
//!
//! 通过重新发起 connect 命令来触发 ICE restart。

use crate::protocol::signaling::SignalingCommand;

/// P2P 恢复逻辑
pub struct PeerRecovery;

impl PeerRecovery {
    pub fn new() -> Self {
        Self
    }

    /// 生成恢复命令
    pub fn recover_peers(&self, peer_ids: Vec<String>) -> Vec<SignalingCommand> {
        peer_ids
            .into_iter()
            .map(|id| SignalingCommand::Connect {
                target_id: id,
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_recover_peers_generates_connect_commands() {
        let recovery = PeerRecovery::new();
        let peers = vec!["peer1".to_string(), "peer2".to_string()];
        let commands = recovery.recover_peers(peers);
        assert_eq!(commands.len(), 2);
    }

    #[test]
    fn test_recover_empty_peers() {
        let recovery = PeerRecovery::new();
        let commands = recovery.recover_peers(vec![]);
        assert!(commands.is_empty());
    }
}
