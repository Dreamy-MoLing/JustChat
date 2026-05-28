//! 连接码类型检测与路由。

/// 连接码类型
pub enum CodeType {
    Jtc1,
    Jtc2,
    Unknown,
}

/// 检测连接码类型
pub fn detect_code_type(code: &str) -> CodeType {
    if code.starts_with("JTC2:") {
        CodeType::Jtc2
    } else if code.starts_with("JTC1:") {
        CodeType::Jtc1
    } else {
        CodeType::Unknown
    }
}
