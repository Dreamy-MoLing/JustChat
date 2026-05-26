//! WebSocket 信令客户端 — 连接到 justtalk-signaling 服务器。
//!
//! 使用 tokio-tungstenite 实现，通过 channel 与引擎通信。

use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use parking_lot::RwLock;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;

use crate::protocol::signaling::{SignalingCommand, SignalingMessage};

/// 信令事件——引擎内部处理
#[derive(Debug, Clone)]
pub enum SignalingEvent {
    Connected,
    Disconnected,
    Message(SignalingMessage),
    Error(String),
}

/// 信令客户端配置
#[derive(Debug, Clone)]
pub struct SignalingConfig {
    pub server_url: String,
    pub peer_id: String,
    pub pubkey: String,
}

/// 信令客户端，通过 `connect()` 建立连接并返回事件接收器。
pub struct SignalingClient {
    config: SignalingConfig,
    cmd_tx: Option<mpsc::UnboundedSender<SignalingCommand>>,
    connected: Arc<RwLock<bool>>,
}

impl SignalingClient {
    pub fn new(server_url: String, peer_id: String, pubkey: String) -> Self {
        Self {
            config: SignalingConfig {
                server_url,
                peer_id,
                pubkey,
            },
            cmd_tx: None,
            connected: Arc::new(RwLock::new(false)),
        }
    }

    pub fn is_connected(&self) -> bool {
        *self.connected.read()
    }

    /// 连接到信令服务器并注册。返回事件接收器。
    pub async fn connect(
        &mut self,
    ) -> crate::Result<mpsc::UnboundedReceiver<SignalingEvent>> {
        self.disconnect();

        let url = ensure_ws_url(&self.config.server_url)?;
        let (ws, _) = tokio_tungstenite::connect_async(&url)
            .await
            .map_err(|e| crate::Error::Network(format!("WebSocket 连接失败: {e}")))?;

        let (mut ws_write, mut ws_read) = ws.split();

        let (cmd_tx, mut cmd_rx) = mpsc::unbounded_channel::<SignalingCommand>();
        let (event_tx, event_rx) = mpsc::unbounded_channel::<SignalingEvent>();

        // 发送注册消息
        let register = SignalingCommand::Register {
            peer_id: self.config.peer_id.clone(),
            pubkey: self.config.pubkey.clone(),
        };
        let register_json = register
            .to_json()
            .map_err(|e| crate::Error::Protocol(format!("序列化注册消息失败: {e}")))?;
        if register_json.len() > 65536 {
            return Err(crate::Error::Protocol("注册消息体过大".into()));
        }
        ws_write
            .send(Message::Text(register_json.into()))
            .await
            .map_err(|e| crate::Error::Network(format!("发送注册消息失败: {e}")))?;

        self.cmd_tx = Some(cmd_tx);

        let connected_w = self.connected.clone();
        let connected_r = self.connected.clone();
        let peer_id_w = self.config.peer_id.clone();
        let peer_id_r = self.config.peer_id.clone();
        let event_tx_w = event_tx.clone();
        let event_tx_r = event_tx;

        // 写循环
        tokio::spawn(async move {
            while let Some(cmd) = cmd_rx.recv().await {
                match cmd.to_json() {
                    Ok(json) => {
                        if json.len() > 65536 {
                            tracing::warn!(target = %peer_id_w, "命令过大 ({})", json.len());
                            continue;
                        }
                        if ws_write.send(Message::Text(json.into())).await.is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        tracing::error!(target = %peer_id_w, "序列化命令失败: {e}");
                    }
                }
            }
            *connected_w.write() = false;
            let _ = event_tx_w.send(SignalingEvent::Disconnected);
        });

        // 读循环
        tokio::spawn(async move {
            while let Some(result) = ws_read.next().await {
                match result {
                    Ok(Message::Text(text)) => {
                        if text.len() > 65536 {
                            tracing::warn!(target = %peer_id_r, "收到超大消息 ({})", text.len());
                            continue;
                        }
                        match SignalingMessage::from_json(&text) {
                            Ok(msg) => {
                                if matches!(msg, SignalingMessage::Registered { .. }) {
                                    let _ = event_tx_r.send(SignalingEvent::Connected);
                                }
                                let _ = event_tx_r.send(SignalingEvent::Message(msg));
                            }
                            Err(e) => {
                                tracing::warn!(target = %peer_id_r, "解析信令消息失败: {e}");
                            }
                        }
                    }
                    Ok(Message::Close(_)) => break,
                    Err(e) => {
                        let _ = event_tx_r
                            .send(SignalingEvent::Error(format!("WS 错误: {e}")));
                        break;
                    }
                    _ => {}
                }
            }
            *connected_r.write() = false;
            let _ = event_tx_r.send(SignalingEvent::Disconnected);
        });

        Ok(event_rx)
    }

    pub fn send(&self, cmd: SignalingCommand) -> crate::Result<()> {
        if let Some(ref tx) = self.cmd_tx {
            tx.send(cmd)
                .map_err(|_| crate::Error::Network("信令通道已关闭".into()))
        } else {
            Err(crate::Error::Network("未连接到信令服务器".into()))
        }
    }

    pub fn disconnect(&mut self) {
        self.cmd_tx = None;
        *self.connected.write() = false;
    }
}

impl Drop for SignalingClient {
    fn drop(&mut self) {
        self.disconnect();
    }
}

fn ensure_ws_url(url: &str) -> crate::Result<String> {
    let url = url.trim();
    if url.is_empty() {
        return Err(crate::Error::Network("信令服务器地址为空".into()));
    }
    if url.starts_with("ws://") || url.starts_with("wss://") {
        return Ok(url.to_string());
    }
    if url.ends_with("/ws") {
        return Ok(format!("ws://{url}"));
    }
    Ok(format!("ws://{url}/ws"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_auto_prefix() {
        assert_eq!(
            ensure_ws_url("localhost:3000/ws").unwrap(),
            "ws://localhost:3000/ws"
        );
        assert_eq!(
            ensure_ws_url("192.168.1.1:3000/ws").unwrap(),
            "ws://192.168.1.1:3000/ws"
        );
        assert_eq!(
            ensure_ws_url("ws://localhost:3000/ws").unwrap(),
            "ws://localhost:3000/ws"
        );
    }

    #[test]
    fn url_empty() {
        assert!(ensure_ws_url("").is_err());
    }
}
