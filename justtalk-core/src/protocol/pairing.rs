//! JTC1/JTC2 配对协议实现。
//!
//! JTC2 (v4, 扫码配对主力):
//!   格式: `JTC2:base64(version(1) + token(16) + timestamp(8) + peerIdLen(1) + peerId(N) + nameLen(1) + name(N) + sigAddrLen(1) + sigAddr(N))`
//!   字节数: ~40-120 字节，QR Version 4-5 可容。
//!   5 分钟过期校验。
//!
//! JTC1 (手动 SDP 交换降级):
//!   格式: `JTC1:` + base64(zlib(json))  (offer 侧)
//!         `JTC1:` + base64(gzip(json))  (answer 侧)
//!   含完整 SDP + ICE 候选列表。

use base64::{engine::general_purpose::URL_SAFE as BASE64_URL, Engine};
use serde::{Deserialize, Serialize};

/// JTC2 配对码。
///
/// 5 分钟有效期，扫码端校验。
#[derive(Debug, Clone)]
pub struct PairingCode {
    pub token: String,
    pub peer_id: String,
    pub display_name: String,
    pub signaling_server: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// JTC2 有效期（秒）
pub const JTC2_EXPIRY_SECONDS: i64 = 300;

/// JTC2 当前协议版本
const JTC2_VERSION: u8 = 4;

/// Token 固定长度（字节）
const TOKEN_LEN: usize = 16;

impl PairingCode {
    /// 创建新的配对码（当前时间）
    pub fn create(
        token: String,
        peer_id: String,
        display_name: String,
        signaling_server: Option<String>,
    ) -> Self {
        Self {
            token,
            peer_id,
            display_name,
            signaling_server,
            created_at: chrono::Utc::now(),
        }
    }

    /// 是否已过期
    pub fn is_expired(&self) -> bool {
        let elapsed = chrono::Utc::now()
            .signed_duration_since(self.created_at)
            .num_seconds();
        elapsed > JTC2_EXPIRY_SECONDS
    }

    /// 距过期还剩多少秒（负数表示已过期）
    pub fn remaining_seconds(&self) -> i64 {
        JTC2_EXPIRY_SECONDS
            - chrono::Utc::now()
                .signed_duration_since(self.created_at)
                .num_seconds()
    }

    /// 编码为 JTC2 字符串 (v4)。
    pub fn encode(&self) -> String {
        let mut bytes: Vec<u8> = Vec::new();

        // Version byte
        bytes.push(JTC2_VERSION);

        // Token: 16 bytes
        let token_bytes = self.token.as_bytes();
        bytes.extend(token_bytes.iter().take(TOKEN_LEN));

        // Timestamp: 8 bytes big-endian (milliseconds since epoch)
        let ts = self.created_at.timestamp_millis();
        bytes.extend_from_slice(&ts.to_be_bytes());

        // Peer ID: length byte + UTF-8 bytes
        let peer_bytes = self.peer_id.as_bytes();
        bytes.push(peer_bytes.len() as u8);
        bytes.extend_from_slice(peer_bytes);

        // Display name: length byte + UTF-8 bytes
        let name_bytes = self.display_name.as_bytes();
        bytes.push(name_bytes.len() as u8);
        bytes.extend_from_slice(name_bytes);

        // Signaling server (optional): length byte + bytes
        if let Some(ref addr) = self.signaling_server {
            let sig_bytes = addr.as_bytes();
            bytes.push(sig_bytes.len() as u8);
            bytes.extend_from_slice(sig_bytes);
        } else {
            bytes.push(0);
        }

        format!("JTC2:{}", BASE64_URL.encode(&bytes))
    }

    /// 从 JTC2 字符串解码（兼容 v2/v3/v4）。
    ///
    /// v4 含时间戳，解码后自动校验 5 分钟有效期。
    /// v2/v3 无时间戳，跳过过期校验。
    pub fn decode(code: &str) -> crate::Result<Self> {
        if !code.starts_with("JTC2:") {
            return Err(crate::Error::Protocol("Not a JTC2 code".into()));
        }

        let raw = BASE64_URL
            .decode(&code[5..])
            .map_err(|e| crate::Error::Protocol(format!("Base64 decode failed: {e}")))?;

        if raw.is_empty() {
            return Err(crate::Error::Protocol("Empty token data".into()));
        }

        let version = raw[0];
        if version < 2 || version > 4 {
            return Err(crate::Error::Protocol(format!(
                "Unsupported version: {version}"
            )));
        }

        let mut pos: usize = 1;

        // Token: 16 bytes
        if pos + TOKEN_LEN > raw.len() {
            return Err(crate::Error::Protocol("Truncated token".into()));
        }
        let token = String::from_utf8_lossy(&raw[pos..pos + TOKEN_LEN]).to_string();
        pos += TOKEN_LEN;

        // Timestamp (v4+): 8 bytes big-endian int64 (milliseconds)
        let created_at = if version >= 4 {
            if pos + 8 > raw.len() {
                return Err(crate::Error::Protocol("Truncated timestamp".into()));
            }
            let mut ts_bytes = [0u8; 8];
            ts_bytes.copy_from_slice(&raw[pos..pos + 8]);
            let ts_ms = i64::from_be_bytes(ts_bytes);
            pos += 8;

            let created_at = chrono::DateTime::from_timestamp_millis(ts_ms)
                .ok_or_else(|| crate::Error::Protocol("Invalid timestamp".into()))?;

            // 校验 5 分钟有效期
            let elapsed = chrono::Utc::now()
                .signed_duration_since(created_at)
                .num_seconds();
            if elapsed > JTC2_EXPIRY_SECONDS {
                return Err(crate::Error::Protocol(format!(
                    "Pairing code expired ({elapsed}s)"
                )));
            }

            created_at
        } else {
            chrono::Utc::now() // v2/v3 无时间戳，用当前时间占位
        };

        // Peer ID (v3+) or fallback
        let peer_id = if version >= 3 {
            if pos >= raw.len() {
                return Err(crate::Error::Protocol("Missing peerId length".into()));
            }
            let peer_len = raw[pos] as usize;
            pos += 1;
            if pos + peer_len > raw.len() {
                return Err(crate::Error::Protocol("Truncated peerId".into()));
            }
            let id = String::from_utf8_lossy(&raw[pos..pos + peer_len]).to_string();
            pos += peer_len;
            id
        } else {
            format!("pair_{token}")
        };

        // Display name
        if pos >= raw.len() {
            return Err(crate::Error::Protocol("Missing name length".into()));
        }
        let name_len = raw[pos] as usize;
        pos += 1;
        if pos + name_len > raw.len() {
            return Err(crate::Error::Protocol("Truncated name".into()));
        }
        let display_name = String::from_utf8_lossy(&raw[pos..pos + name_len]).to_string();
        pos += name_len;

        // Signaling server
        let signaling_server = if pos < raw.len() {
            let sig_len = raw[pos] as usize;
            pos += 1;
            if sig_len > 0 && pos + sig_len <= raw.len() {
                Some(String::from_utf8_lossy(&raw[pos..pos + sig_len]).to_string())
            } else {
                None
            }
        } else {
            None
        };

        Ok(Self {
            token,
            peer_id,
            display_name,
            signaling_server,
            created_at,
        })
    }

    /// 生成 16 字节随机 token（hex 编码）
    pub fn generate_token() -> String {
        use rand::RngCore;
        let mut bytes = [0u8; TOKEN_LEN];
        rand::rngs::OsRng.fill_bytes(&mut bytes);
        hex::encode(bytes)
    }
}

// ── JTC1 编解码 ──

/// JTC1 连接数据（完整 SDP + ICE 候选列表）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Jtc1ConnectionData {
    pub sdp: serde_json::Value,
    pub candidates: Vec<serde_json::Value>,
}

/// 编码 JTC1 offer 字符串。
/// 流程: json → zlib 压缩 → base64url → 前缀 "JTC1:"
pub fn encode_jtc1_offer(data: &Jtc1ConnectionData) -> crate::Result<String> {
    use flate2::write::ZlibEncoder;
    use flate2::Compression;
    use std::io::Write;

    let json = serde_json::to_string(data)
        .map_err(|e| crate::Error::Protocol(format!("JSON serialize: {e}")))?;

    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(json.as_bytes())
        .map_err(|e| crate::Error::Protocol(format!("Zlib compress: {e}")))?;
    let compressed = encoder
        .finish()
        .map_err(|e| crate::Error::Protocol(format!("Zlib finish: {e}")))?;

    Ok(format!("JTC1:{}", BASE64_URL.encode(&compressed)))
}

/// 编码 JTC1 answer 字符串。
/// 流程: json → gzip 压缩 → base64 → 前缀 "JTC1:"
pub fn encode_jtc1_answer(data: &Jtc1ConnectionData) -> crate::Result<String> {
    use flate2::write::GzEncoder;
    use flate2::Compression;
    use std::io::Write;

    let json = serde_json::to_string(data)
        .map_err(|e| crate::Error::Protocol(format!("JSON serialize: {e}")))?;

    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(json.as_bytes())
        .map_err(|e| crate::Error::Protocol(format!("Gzip compress: {e}")))?;
    let compressed = encoder
        .finish()
        .map_err(|e| crate::Error::Protocol(format!("Gzip finish: {e}")))?;

    use base64::{engine::general_purpose::STANDARD as BASE64_STD, Engine};
    Ok(format!("JTC1:{}", BASE64_STD.encode(&compressed)))
}

/// 解码 JTC1 字符串（自动检测 zlib/gzip 压缩）。
pub fn decode_jtc1(code: &str) -> crate::Result<Jtc1ConnectionData> {
    if !code.starts_with("JTC1:") {
        return Err(crate::Error::Protocol("Not a JTC1 code".into()));
    }

    let raw = &code[5..];

    // 先尝试 base64url + zlib (offer 格式)
    if let Ok(compressed) = BASE64_URL.decode(raw) {
        use std::io::Read;
        let mut decoder = flate2::read::ZlibDecoder::new(&compressed[..]);
        let mut json = String::new();
        if decoder.read_to_string(&mut json).is_ok() {
            if let Ok(data) = serde_json::from_str(&json) {
                return Ok(data);
            }
        }
    }

    // 再尝试 base64 + gzip (answer 格式)
    use base64::{engine::general_purpose::STANDARD as BASE64_STD, Engine};
    if let Ok(compressed) = BASE64_STD.decode(raw) {
        use std::io::Read;
        let mut decoder = flate2::read::GzDecoder::new(&compressed[..]);
        let mut json = String::new();
        decoder
            .read_to_string(&mut json)
            .map_err(|e| crate::Error::Protocol(format!("Gzip decompress: {e}")))?;
        return serde_json::from_str(&json)
            .map_err(|e| crate::Error::Protocol(format!("JSON deserialize: {e}")));
    }

    Err(crate::Error::Protocol("Invalid JTC1 code".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jtc2_roundtrip_v4() {
        let code = PairingCode::create(
            "abcd1234abcd1234".into(),
            "peer_test123".into(),
            "测试用户".into(),
            Some("ws://192.168.1.1:3000/ws".into()),
        );

        let encoded = code.encode();
        assert!(encoded.starts_with("JTC2:"), "编码结果应以 JTC2: 开头");
        assert!(encoded.len() <= 150, "编码后应 ≤ 150 字节");

        let decoded = PairingCode::decode(&encoded).expect("回环解码失败");
        assert_eq!(decoded.token, "abcd1234abcd1234");
        assert_eq!(decoded.peer_id, "peer_test123");
        assert_eq!(decoded.display_name, "测试用户");
        assert_eq!(
            decoded.signaling_server.as_deref(),
            Some("ws://192.168.1.1:3000/ws")
        );
    }

    #[test]
    fn jtc2_no_signaling_server() {
        let code = PairingCode::create(
            "test000000000000".into(),
            "peer1".into(),
            "Alice".into(),
            None,
        );
        let encoded = code.encode();
        let decoded = PairingCode::decode(&encoded).expect("回环解码失败");
        assert!(decoded.signaling_server.is_none());
    }

    #[test]
    fn jtc2_encode_produces_identical_output() {
        // 验证相同输入产生相同输出（用于交叉测试）
        let now = chrono::Utc::now();
        let code = PairingCode {
            token: "0123456789abcdef".into(),
            peer_id: "peer_h2x3k4m5".into(),
            display_name: "舰长".into(),
            signaling_server: Some("ws://192.168.1.100:3000/ws".into()),
            created_at: now,
        };
        let encoded = code.encode();
        // 只验证结构正确性，不验证具体 base64 值
        assert!(encoded.starts_with("JTC2:"));

        let decoded = PairingCode::decode(&encoded).expect("回环解码失败");
        assert_eq!(decoded.token, "0123456789abcdef");
        assert_eq!(decoded.peer_id, "peer_h2x3k4m5");
    }

    #[test]
    fn jtc1_offer_roundtrip() {
        let data = Jtc1ConnectionData {
            sdp: serde_json::json!({"type": "offer", "sdp": "v=0\r\n..."}),
            candidates: vec![serde_json::json!({"candidate": "candidate:1"})],
        };
        let encoded = encode_jtc1_offer(&data).expect("编码失败");
        assert!(encoded.starts_with("JTC1:"));

        let decoded = decode_jtc1(&encoded).expect("解码失败");
        assert_eq!(decoded.sdp["type"], "offer");
        assert_eq!(decoded.candidates.len(), 1);
    }

    #[test]
    fn jtc1_answer_roundtrip() {
        let data = Jtc1ConnectionData {
            sdp: serde_json::json!({"type": "answer", "sdp": "v=0\r\n..."}),
            candidates: vec![],
        };
        let encoded = encode_jtc1_answer(&data).expect("编码失败");
        assert!(encoded.starts_with("JTC1:"));

        let decoded = decode_jtc1(&encoded).expect("解码失败");
        assert_eq!(decoded.sdp["type"], "answer");
    }
}
