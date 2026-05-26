//! 本地数据持久化。
//!
//! 所有文件存储在 `{storage_path}/` 下：
//! - `messages/{peer_id}.json` — 聊天消息
//! - `contacts.json` — 联系人
//! - `settings.json` — 设置

pub mod messages;
pub mod contacts;
pub mod settings;

pub use messages::MessageStore;
pub use contacts::ContactStore;
pub use settings::SettingsStore;
