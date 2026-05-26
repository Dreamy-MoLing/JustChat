//! JTC1/JTC2 配对流程编排。
//!
//! 从 chat_state.dart 的配对逻辑移植而来。

use crate::protocol::pairing::{PairingCode, Jtc1ConnectionData};
use crate::protocol::webrtc_types::WebrtcCommand;

/// JTC2 配对：生成供扫码的 QR 编码字符串。
///
/// 引擎调用此函数后：
/// 1. 生成随机 token
/// 2. 编码 JTC2 字符串
/// 3. 返回配对码（引擎随后通过 signaling_client 发送 pair_intent）
pub fn prepare_jtc2_qr(
    peer_id: &str,
    display_name: &str,
    signaling_server: Option<&str>,
) -> PairingCode {
    let token = PairingCode::generate_token();
    PairingCode::create(
        token,
        peer_id.to_string(),
        display_name.to_string(),
        signaling_server.map(|s| s.to_string()),
    )
}

/// JTC2 配对：扫码方解析并验证 QR 码。
///
/// 返回解码后的配对码，包含对端 peer_id、display_name、signaling_server。
pub fn decode_jtc2_qr(code: &str) -> crate::Result<PairingCode> {
    PairingCode::decode(code)
}

/// JTC1 offer 生成：创建 offer 侧的完整 SDP+ICE 数据并编码为文本。
///
/// 此函数不直接创建 WebRTC 连接——它打包引擎已收集的 SDP 和 ICE 候选。
pub fn encode_jtc1_offer(sdp: serde_json::Value, candidates: Vec<serde_json::Value>) -> crate::Result<String> {
    let data = Jtc1ConnectionData { sdp, candidates };
    crate::protocol::pairing::encode_jtc1_offer(&data)
}

/// JTC1 answer 生成：创建 answer 侧的 SDP+ICE 数据并编码为文本。
pub fn encode_jtc1_answer(sdp: serde_json::Value, candidates: Vec<serde_json::Value>) -> crate::Result<String> {
    let data = Jtc1ConnectionData { sdp, candidates };
    crate::protocol::pairing::encode_jtc1_answer(&data)
}

/// JTC1 连接码解码：解析对端的连接码。
pub fn decode_jtc1(code: &str) -> crate::Result<Jtc1ConnectionData> {
    crate::protocol::pairing::decode_jtc1(code)
}

/// 获取 WebRTC offer 流程的起始命令（用于 JTC1）。
pub fn start_jtc1_offer_commands(peer_id: &str) -> Vec<WebrtcCommand> {
    crate::engine::state_machine::start_jtc1_offer_flow(peer_id)
}

/// 获取 WebRTC answer 流程的起始命令（用于 JTC1）。
pub fn start_jtc1_answer_commands(peer_id: &str, offer_sdp: &str) -> Vec<WebrtcCommand> {
    crate::engine::state_machine::start_jtc1_answer_flow(peer_id, offer_sdp)
}
