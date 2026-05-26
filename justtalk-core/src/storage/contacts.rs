//! 联系人持久化 — 单文件 JSON 存储。
//!
//! 格式: `{storage_path}/contacts.json` — JSON 数组。

use std::fs;
use std::path::PathBuf;

use crate::protocol::webrtc_types::ContactData;

/// 联系人存储
#[derive(Debug, Clone)]
pub struct ContactStore {
    file_path: PathBuf,
}

impl ContactStore {
    /// 创建联系人存储实例
    pub fn new(base_path: PathBuf) -> Self {
        Self {
            file_path: base_path.join("contacts.json"),
        }
    }

    /// 加载所有联系人
    pub fn load_all(&self) -> crate::Result<Vec<ContactData>> {
        if !self.file_path.exists() {
            return Ok(Vec::new());
        }
        let content = fs::read_to_string(&self.file_path)
            .map_err(|e| crate::Error::Storage(format!("读取联系人文件失败: {e}")))?;
        Ok(serde_json::from_str(&content).unwrap_or_else(|_| {
            tracing::warn!("联系人文件损坏，返回空列表");
            Vec::new()
        }))
    }

    /// 保存所有联系人
    pub fn save_all(&self, contacts: &[ContactData]) -> crate::Result<()> {
        let json = serde_json::to_string_pretty(contacts)
            .map_err(|e| crate::Error::Storage(format!("序列化联系人失败: {e}")))?;
        fs::write(&self.file_path, json)
            .map_err(|e| crate::Error::Storage(format!("写入联系人文件失败: {e}")))?;
        Ok(())
    }

    /// 添加或更新联系人
    pub fn upsert(&self, contact: &ContactData) -> crate::Result<()> {
        let mut contacts = self.load_all()?;
        if let Some(existing) = contacts.iter_mut().find(|c| c.peer_id == contact.peer_id) {
            *existing = contact.clone();
        } else {
            contacts.push(contact.clone());
        }
        self.save_all(&contacts)
    }

    /// 删除联系人
    pub fn remove(&self, peer_id: &str) -> crate::Result<()> {
        let mut contacts = self.load_all()?;
        contacts.retain(|c| c.peer_id != peer_id);
        self.save_all(&contacts)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn make_contact(id: &str, name: &str, online: bool) -> ContactData {
        ContactData {
            peer_id: id.into(),
            display_name: name.into(),
            online,
            last_seen_ms: None,
        }
    }

    #[test]
    fn save_and_load() {
        let dir = TempDir::new().unwrap();
        let store = ContactStore::new(dir.path().to_path_buf());

        let contacts = vec![make_contact("peer1", "Alice", true)];
        store.save_all(&contacts).unwrap();

        let loaded = store.load_all().unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].display_name, "Alice");
    }

    #[test]
    fn upsert_new() {
        let dir = TempDir::new().unwrap();
        let store = ContactStore::new(dir.path().to_path_buf());

        store.upsert(&make_contact("peer1", "Bob", false)).unwrap();
        assert_eq!(store.load_all().unwrap().len(), 1);

        store
            .upsert(&make_contact("peer1", "Bob Updated", true))
            .unwrap();
        let loaded = store.load_all().unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0].display_name, "Bob Updated");
    }

    #[test]
    fn remove_contact() {
        let dir = TempDir::new().unwrap();
        let store = ContactStore::new(dir.path().to_path_buf());

        store.upsert(&make_contact("a", "A", false)).unwrap();
        store.upsert(&make_contact("b", "B", false)).unwrap();
        assert_eq!(store.load_all().unwrap().len(), 2);

        store.remove("a").unwrap();
        assert_eq!(store.load_all().unwrap().len(), 1);
    }
}
