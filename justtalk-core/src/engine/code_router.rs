//! 连接码类型检测与路由。

/// 连接码类型
#[derive(Debug, PartialEq)]
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_jtc2() {
        assert_eq!(detect_code_type("JTC2:abc123"), CodeType::Jtc2);
    }

    #[test]
    fn detects_jtc1() {
        assert_eq!(detect_code_type("JTC1:base64data"), CodeType::Jtc1);
    }

    #[test]
    fn detects_unknown() {
        assert_eq!(detect_code_type("INVALID"), CodeType::Unknown);
        assert_eq!(detect_code_type(""), CodeType::Unknown);
    }
}
