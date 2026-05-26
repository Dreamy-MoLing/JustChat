//! 消息持久化 — JSON 文件存储。
//!
//! 格式: `{storage_path}/messages/{peer_id}.json`
//! 每个文件是一个 JSON 数组，按时间顺序排列。

use std::fs;
use std::path::PathBuf;

use crate::protocol::webrtc_types::ChatMessageData;

/// 消息存储
#[derive(Debug, Clone)]
pub struct MessageStore {
    /// 存储根目录
    base_path: PathBuf,
}

impl MessageStore {
    /// 创建消息存储实例
    pub fn new(base_path: PathBuf) -> Self {
        Self { base_path }
    }

    /// 确保消息目录存在
    fn ensure_dir(&self) -> std::io::Result<()> {
        let dir = self.base_path.join("messages");
        fs::create_dir_all(&dir)?;
        Ok(())
    }

    /// 获取某个 peer 的消息文件路径
    fn peer_file(&self, peer_id: &str) -> PathBuf {
        self.base_path
            .join("messages")
            .join(format!("{peer_id}.json"))
    }

    /// 保存一条消息（追加到 peer 的消息列表末尾）
    pub fn save_message(&self, peer_id: &str, msg: &ChatMessageData) -> crate::Result<()> {
        self.ensure_dir()
            .map_err(|e| crate::Error::Storage(format!("创建消息目录失败: {e}")))?;
        let file_path = self.peer_file(peer_id);

        // 读取现有多条消息
        let mut messages: Vec<ChatMessageData> = if file_path.exists() {
            let content =
                fs::read_to_string(&file_path).unwrap_or_else(|_| "[]".to_string());
            serde_json::from_str(&content).unwrap_or_default()
        } else {
            Vec::new()
        };

        // 去重：同 ID 不重复添加
        if !messages.iter().any(|m| m.id == msg.id) {
            messages.push(msg.clone());
        }

        let json = serde_json::to_string_pretty(&messages)
            .map_err(|e| crate::Error::Storage(format!("序列化消息失败: {e}")))?;

        fs::write(&file_path, json)
            .map_err(|e| crate::Error::Storage(format!("写入消息文件失败: {e}")))?;

        Ok(())
    }

    /// 加载某个 peer 的所有消息
    pub fn load_messages(&self, peer_id: &str) -> crate::Result<Vec<ChatMessageData>> {
        let file_path = self.peer_file(peer_id);
        if !file_path.exists() {
            return Ok(Vec::new());
        }
        let content = fs::read_to_string(&file_path)
            .map_err(|e| crate::Error::Storage(format!("读取消息文件失败: {e}")))?;
        Ok(serde_json::from_str(&content).unwrap_or_else(|_| {
            tracing::warn!("消息文件损坏，返回空列表: {file_path:?}");
            Vec::new()
        }))
    }

    /// 删除某个 peer 的所有消息
    pub fn delete_peer_messages(&self, peer_id: &str) -> crate::Result<()> {
        let file_path = self.peer_file(peer_id);
        if file_path.exists() {
            fs::remove_file(&file_path)
                .map_err(|e| crate::Error::Storage(format!("删除消息文件失败: {e}")))?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn save_and_load() {
        let dir = TempDir::new().unwrap();
        let store = MessageStore::new(dir.path().to_path_buf());

        let msg = ChatMessageData {
            id: "msg1".into(),
            sender_id: "peer_a".into(),
            content: "你好".into(),
            timestamp_ms: 1716700000000,
            is_mine: true,
        };

        store.save_message("peer_b", &msg).unwrap();
        let loaded = store.load_messages("peer_b").unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].content, "你好");
    }

    #[test]
    fn dedup_same_id() {
        let dir = TempDir::new().unwrap();
        let store = MessageStore::new(dir.path().to_path_buf());

        let msg = ChatMessageData {
            id: "dup_id".into(),
            sender_id: "a".into(),
            content: "test".into(),
            timestamp_ms: 0,
            is_mine: false,
        };

        store.save_message("peer1", &msg).unwrap();
        store.save_message("peer1", &msg).unwrap(); // 重复
        assert_eq!(store.load_messages("peer1").unwrap().len(), 1);
    }

    #[test]
    fn empty_peer() {
        let dir = TempDir::new().unwrap();
        let store = MessageStore::new(dir.path().to_path_buf());
        assert!(store.load_messages("nonexistent").unwrap().is_empty());
    }
}
