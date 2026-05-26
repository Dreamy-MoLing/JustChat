//! 设置持久化 — 单文件 JSON 存储。
//!
//! 格式: `{storage_path}/settings.json` — JSON 对象（string → string 键值对）。

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// 设置存储
#[derive(Debug, Clone)]
pub struct SettingsStore {
    file_path: PathBuf,
}

/// 设置键名常量
pub const KEY_DISPLAY_NAME: &str = "displayName";
pub const KEY_AUTO_CONNECT: &str = "autoConnect";
pub const KEY_NOTIFICATIONS_ENABLED: &str = "notificationsEnabled";
pub const KEY_SIGNALING_SERVER: &str = "signalingServer";

impl SettingsStore {
    /// 创建设置存储实例
    pub fn new(base_path: PathBuf) -> Self {
        Self {
            file_path: base_path.join("settings.json"),
        }
    }

    /// 加载所有设置
    pub fn load_all(&self) -> crate::Result<HashMap<String, String>> {
        if !self.file_path.exists() {
            return Ok(HashMap::new());
        }
        let content = fs::read_to_string(&self.file_path)
            .map_err(|e| crate::Error::Storage(format!("读取设置文件失败: {e}")))?;
        Ok(serde_json::from_str(&content).unwrap_or_else(|_| {
            tracing::warn!("设置文件损坏，返回空映射");
            HashMap::new()
        }))
    }

    /// 保存所有设置
    pub fn save_all(&self, settings: &HashMap<String, String>) -> crate::Result<()> {
        let json = serde_json::to_string_pretty(settings)
            .map_err(|e| crate::Error::Storage(format!("序列化设置失败: {e}")))?;
        fs::write(&self.file_path, json)
            .map_err(|e| crate::Error::Storage(format!("写入设置文件失败: {e}")))?;
        Ok(())
    }

    /// 获取单个设置
    pub fn get(&self, key: &str) -> crate::Result<Option<String>> {
        let settings = self.load_all()?;
        Ok(settings.get(key).cloned())
    }

    /// 设置单个键值对
    pub fn set(&self, key: &str, value: &str) -> crate::Result<()> {
        let mut settings = self.load_all()?;
        settings.insert(key.to_string(), value.to_string());
        self.save_all(&settings)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn get_set() {
        let dir = TempDir::new().unwrap();
        let store = SettingsStore::new(dir.path().to_path_buf());

        store.set("displayName", "舰长").unwrap();
        assert_eq!(store.get("displayName").unwrap(), Some("舰长".into()));
        assert_eq!(store.get("nonexistent").unwrap(), None);
    }

    #[test]
    fn load_empty() {
        let dir = TempDir::new().unwrap();
        let store = SettingsStore::new(dir.path().to_path_buf());
        assert!(store.load_all().unwrap().is_empty());
    }
}
