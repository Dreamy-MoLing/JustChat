//! Dart↔Rust FFI 接口层。
//!
//! 使用 JSON 字符串跨 FFI 边界传输复杂类型。
//! 引擎内部缓冲区存储事件和命令，poll 函数读取。

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::OnceLock;

use parking_lot::Mutex;

use crate::engine::P2pEngine;

static ENGINE: OnceLock<Mutex<Option<P2pEngine>>> = OnceLock::new();
static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn runtime() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| tokio::runtime::Runtime::new().expect("failed to create tokio runtime"))
}

fn get_engine() -> &'static Mutex<Option<P2pEngine>> {
    ENGINE.get_or_init(|| Mutex::new(None))
}

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

unsafe fn from_c_str<'a>(ptr: *const c_char) -> &'a str {
    if ptr.is_null() { return ""; }
    unsafe { CStr::from_ptr(ptr) }.to_str().unwrap_or("")
}

// ── FFI functions ──

#[unsafe(no_mangle)]
pub extern "C" fn jt_engine_init(storage_path: *const c_char) -> *mut c_char {
    let path = unsafe { from_c_str(storage_path) };
    let eng = P2pEngine::new(PathBuf::from(path));
    let peer_id = eng.my_peer_id();
    let display_name = eng.display_name();
    *get_engine().lock() = Some(eng);
    let r = serde_json::json!({"ok":true,"peer_id":peer_id,"display_name":display_name});
    to_c_string(r.to_string())
}

#[unsafe(no_mangle)]
pub extern "C" fn jt_poll_events() -> *mut c_char {
    let g = get_engine().lock();
    if let Some(ref eng) = *g {
        let evs: Vec<_> = eng.drain_events().iter()
            .map(|e| serde_json::to_value(e).unwrap_or_default()).collect();
        to_c_string(serde_json::to_string(&evs).unwrap_or_else(|_| "[]".into()))
    } else {
        to_c_string("[]".into())
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn jt_poll_commands() -> *mut c_char {
    let g = get_engine().lock();
    if let Some(ref eng) = *g {
        let cmds: Vec<_> = eng.drain_commands().iter()
            .map(|c| serde_json::to_value(c).unwrap_or_default()).collect();
        to_c_string(serde_json::to_string(&cmds).unwrap_or_else(|_| "[]".into()))
    } else {
        to_c_string("[]".into())
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn jt_call(method_json: *const c_char) -> *mut c_char {
    let json = unsafe { from_c_str(method_json) };
    let req: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v, Err(e) => return to_c_string(
            serde_json::json!({"ok":false,"error":format!("JSON parse:{e}")}).to_string()),
    };
    let method = req.get("method").and_then(|v| v.as_str()).unwrap_or("");
    let params = req.get("params");
    to_c_string(dispatch(method, params).to_string())
}

fn dispatch(method: &str, params: Option<&serde_json::Value>) -> serde_json::Value {
    let mut g = get_engine().lock();
    let eng = match g.as_mut() { Some(e) => e, None => return e("引擎未初始化") };
    let rt = runtime();

    match method {
        "connect_signaling" => match rt.block_on(async { eng.connect_signaling().await }) {
            Ok(()) => ok(), Err(e) => err(&e.to_string()),
        },
        "connect_to_peer" => {
            let pid = s(params, "peer_id");
            eng.connect_to_peer(pid);
            ok()
        }
        "send_message" => {
            let pid = s(params, "peer_id");
            let txt = s(params, "text");
            eng.send_message(pid, txt);
            ok()
        }
        "generate_pairing_code" => {
            let code = eng.generate_pairing_code();
            serde_json::json!({"ok":true,"data":{"code":code.encode()}})
        }
        "accept_pairing_code" => {
            let code = s(params, "code");
            match rt.block_on(async { eng.accept_pairing_code(code).await }) {
                Ok(()) => ok(), Err(ee) => err(&ee.to_string()),
            }
        }
        "accept_connection_code" => {
            let code = s(params, "code");
            match eng.accept_connection_code(code) {
                Ok(peer_id) => serde_json::json!({"ok":true,"data":{"peer_id":peer_id}}),
                Err(e) => err(&e.to_string()),
            }
        }
        "encode_jtc1_answer" => {
            let peer_id = s(params, "peer_id");
            match eng.encode_jtc1_answer_with_pending(peer_id) {
                Ok(code) => serde_json::json!({"ok":true,"data":{"code":code}}),
                Err(e) => err(&e.to_string()),
            }
        }
        "add_contact" => { eng.add_contact(s(params,"peer_id"), s(params,"display_name")); ok() }
        "remove_contact" => { eng.remove_contact(s(params,"peer_id")); ok() }
        "get_contacts" => serde_json::json!({"ok":true,"data":{"contacts":eng.get_contacts()}}),
        "get_messages" => {
            let pid = s(params, "peer_id");
            serde_json::json!({"ok":true,"data":{"messages":eng.get_messages(pid)}})
        }
        "get_peer_phase" => {
            let pid = s(params, "peer_id");
            serde_json::json!({"ok":true,"data":{"phase":eng.get_peer_phase(pid)}})
        }
        "set_display_name" => { eng.set_display_name(s(params,"name")); ok() }
        "set_signaling_server" => { eng.set_signaling_server(s(params,"url")); ok() }
        "set_active_contact" => { eng.set_active_contact(s(params,"peer_id")); ok() }
        "set_auto_connect" => { eng.set_auto_connect(b(params,"enabled")); ok() }
        "set_notifications_enabled" => { eng.set_notifications_enabled(b(params,"enabled")); ok() }
        "get_settings" => {
            let key = s(params, "key");
            match eng.get_setting(key) {
                Some(val) => serde_json::json!({"ok":true,"data":{"value":val}}),
                None => serde_json::json!({"ok":true,"data":{"value":null}}),
            }
        }
        "set_settings" => {
            let key = s(params, "key");
            let value = s(params, "value");
            eng.set_setting(key, value);
            ok()
        }
        "tick" => { eng.tick(); ok() }
        "on_peer_connection_created" => {
            eng.on_peer_connection_created(s(params,"peer_id"), b(params,"is_offer_side")); ok()
        }
        "on_local_description" => {
            eng.on_local_description(s(params,"peer_id"), s(params,"sdp"), s(params,"sdp_type")); ok()
        }
        "on_ice_candidate" => {
            eng.on_ice_candidate(s(params,"peer_id"), s(params,"candidate"),
                params.and_then(|p| p["sdp_mid"].as_str()),
                params.and_then(|p| p["sdp_m_line_index"].as_i64()).map(|i| i as i32)); ok()
        }
        "on_ice_gathering_complete" => {
            eng.on_ice_gathering_complete(s(params,"peer_id")); ok()
        }
        "on_data_channel_open" => { eng.on_data_channel_open(s(params,"peer_id")); ok() }
        "on_data_channel_message" => {
            eng.on_data_channel_message(s(params,"peer_id"), s(params,"data")); ok()
        }
        "on_ice_connection_state_change" => {
            eng.on_ice_connection_state_change(s(params,"peer_id"), s(params,"state")); ok()
        }
        "on_peer_connection_failed" => {
            eng.on_peer_connection_failed(s(params,"peer_id"), s(params,"error")); ok()
        }
        _ => serde_json::json!({"ok":false,"error":format!("未知方法: {method}")}),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn jt_free_string(ptr: *mut c_char) {
    if !ptr.is_null() { unsafe { let _ = CString::from_raw(ptr); } }
}

// ── helpers ──

fn s<'a>(params: Option<&'a serde_json::Value>, key: &str) -> &'a str {
    params.and_then(|p| p[key].as_str()).unwrap_or("")
}
fn b(params: Option<&serde_json::Value>, key: &str) -> bool {
    params.and_then(|p| p[key].as_bool()).unwrap_or(false)
}
fn ok() -> serde_json::Value { serde_json::json!({"ok":true}) }
fn err(msg: &str) -> serde_json::Value { serde_json::json!({"ok":false,"error":msg}) }
fn e(msg: &str) -> serde_json::Value { err(msg) }

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn init_engine() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let path = CString::new(dir.path().to_str().unwrap()).unwrap();
        let result_ptr = jt_engine_init(path.as_ptr());
        assert!(!result_ptr.is_null());
        let result = unsafe { CStr::from_ptr(result_ptr) }.to_str().unwrap();
        let json: serde_json::Value = serde_json::from_str(result).unwrap();
        assert_eq!(json["ok"], true);
        assert!(json["peer_id"].as_str().is_some());
        jt_free_string(result_ptr);
        dir
    }

    fn call_json(cmd_str: &str) -> serde_json::Value {
        let cmd = CString::new(cmd_str).unwrap();
        let result_ptr = jt_call(cmd.as_ptr());
        let result = unsafe { CStr::from_ptr(result_ptr) }.to_str().unwrap();
        let json: serde_json::Value = serde_json::from_str(result).unwrap();
        jt_free_string(result_ptr);
        json
    }

    #[test]
    fn engine_init_returns_valid_json() {
        let _dir = init_engine();
    }

    #[test]
    fn jt_call_get_contacts_returns_list() {
        let _dir = init_engine();
        let json = call_json(r#"{"method":"get_contacts","params":{}}"#);
        assert_eq!(json["ok"], true);
        assert!(json["data"]["contacts"].is_array());
    }

    #[test]
    fn jt_call_unknown_method_returns_error() {
        let _dir = init_engine();
        let json = call_json(r#"{"method":"nonexistent","params":{}}"#);
        assert_eq!(json["ok"], false);
        assert!(json["error"].as_str().is_some());
    }

    #[test]
    fn jt_call_invalid_json_returns_error() {
        let _dir = init_engine();
        let json = call_json("not json");
        assert_eq!(json["ok"], false);
    }

    #[test]
    fn jt_poll_events_returns_empty_when_no_events() {
        let _dir = init_engine();
        let result_ptr = jt_poll_events();
        let result = unsafe { CStr::from_ptr(result_ptr) }.to_str().unwrap();
        let json: serde_json::Value = serde_json::from_str(result).unwrap();
        assert!(json.as_array().unwrap().is_empty());
        jt_free_string(result_ptr);
    }

    #[test]
    fn jt_poll_commands_returns_empty_when_no_commands() {
        let _dir = init_engine();
        let result_ptr = jt_poll_commands();
        let result = unsafe { CStr::from_ptr(result_ptr) }.to_str().unwrap();
        let json: serde_json::Value = serde_json::from_str(result).unwrap();
        assert!(json.as_array().unwrap().is_empty());
        jt_free_string(result_ptr);
    }
}
