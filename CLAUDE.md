# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

JustChat — P2P 文字聊天应用，扫码即连，无需账号。包名: `justchat`，工作区目录名: `JustTalk`。

| 属性 | 值 |
|------|-----|
| Flutter SDK | ^3.41.0 (pubspec 约束，本地安装 3.44) |
| Dart SDK | ^3.9.0 |
| Rust | edition 2024 |
| 当前版本 | v0.0.3-dev (架构迁移中) |
| GitHub | https://github.com/Dreamy-MoLing/JustChat |

## 常用命令

```bash
# Flutter（在 justtalk-flutter/ 下执行）
cd justtalk-flutter
flutter pub get
flutter analyze                     # 必须零警告才能提交
flutter test                        # 运行测试
flutter run -d linux                # Linux 桌面开发
flutter run -d android              # Android 开发（需连接设备或模拟器）
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 flutter build apk --release
flutter build linux --debug
flutter build windows --release     # 需 Windows 宿主
flutter build ios --release --no-codesign

# Rust（工作区根目录）
cargo build                         # 构建整个工作区
cargo test                          # 运行所有 Rust 测试
cargo run -p justtalk-signaling     # 启动信令服务器 (0.0.0.0:3000)
```

## 架构大图 (v0.0.3)

```
Flutter App (justtalk-flutter/)      Rust justtalk-core (引擎)
────────────────────────────        ──────────────────────────
UI Pages (纯 Widget)                P2pEngine (核心引擎)
  │                                    │
ChatState (薄状态持有, ~200行)         ├── signaling_client (WS)
  │                                    ├── state_machine (WebRTC编排)
  │  ┌─ WebrtcAdapter (~160行)        ├── peer_manager
  │  │  纯 flutter_webrtc 适配         ├── pairing_flow (JTC1/JTC2)
  │  │  零业务逻辑                     ├── KeyPair (ed25519)
  │  └─ WebrtcCommand ◄────────────── ├── MessageEncryptor
  │     (平台API调用)                  ├── MessageStore (JSON)
  └─ P2pEvent ─────────────────────── ├── ContactStore (JSON)
       (状态变更)                      └── SettingsStore (JSON)
         │                                    │
         ├── WebSocket ───────────► Rust 信令服务器 (:3000)
         └── WebRTC DataChannel ─── P2P 直连 (STUN/TURN)
```

**命令/事件模式**: Rust 引擎通过 `WebrtcCommand` stream 告诉 Dart 执行什么 WebRTC 操作（创建 PC、设置 SDP、发送消息），Dart 完成后回调 Rust。Rust 通过 `P2pEvent` stream 推送状态变化给 Dart UI。

**Flutter 侧关键文件**:
- `lib/models/chat_state.dart` — 薄状态持有者，监听 P2pEvent 流，UI 数据模型
- `lib/services/webrtc_adapter.dart` — 纯 flutter_webrtc 适配器，零业务逻辑
- `lib/services/engine_bridge.dart` — Dart↔Rust FFI 桥接（当前为本地 fallback）
- `lib/pages/` — 6 个页面，纯 UI

**Rust 侧关键文件**:
- `justtalk-core/src/engine/mod.rs` — P2pEngine 主体
- `justtalk-core/src/engine/state_machine.rs` — WebRTC 状态机
- `justtalk-core/src/network/signaling_client.rs` — 信令 WS 客户端
- `justtalk-core/src/protocol/pairing.rs` — JTC1/JTC2 编解码
- `justtalk-core/src/api.rs` — Dart FFI 接口（C ABI + JSON）

**状态管理**: `MultiProvider` 注入 `ChatState` + `NotificationState` 全局单例。`Consumer<T>` 放在需要响应变化的最小 Widget 上。`context.read<T>()` 读取（不监听），`context.watch<T>()` 监听重绘。

**持久化**: Rust JSON 文件，`{storage_path}/messages/{peer_id}.json` + `contacts.json` + `settings.json`。

**主题**: Material 3，`JustChatApp.teal` (#0D9488) + `JustChatApp.cream` (#FFF8E1)，圆角 12-24px。字体走 `GoogleFonts.notoSansTextTheme()`。

## 通信协议

**双协议栈，自动降级：**

| 协议 | 用途 | 格式 |
|------|------|------|
| JTC2 | 扫码配对（主力） | `JTC2:base64(version + token + name + sigAddr)`，80字节，QR Version 4-5 |
| JTC1 | 手动 SDP 交换（降级） | `JTC1:` + base64(gzip/json)，含完整 SDP + ICE |

**信令协议**: JSON over WebSocket，命令: `register` → `pair_intent` → `connect_via_pair` → `sdp_offer`/`ice_candidate` 转发 → `ping`/`pong` 心跳。

**消息格式**: 当前 JSON 明文 over DataChannel。v0.2 升级 MessagePack + 端到端加密。

详见 [ARCHITECTURE.md](ARCHITECTURE.md) 和 [plan.md](plan.md)。

## 编码规则

### 命名
- Dart 文件: snake_case，类: PascalCase，方法/变量: camelCase，私有: `_` 前缀
- Rust 文件/函数: snake_case，类型: PascalCase
- 中文注释，英文变量/函数名

### Widget
- 嵌套超过 5 层 → 抽取独立 Widget
- build 方法超过 200 行 → 抽取
- 异步回调中检查 `context.mounted`
- 所有 Widget 尽可能声明 `const` 构造器

### Git
- 提交格式: `type: short description`（feat/fix/refactor/docs/ci/chore）
- 不直接提交到 main，使用 feature 分支 + PR
- 推送 tag `v*.*.*` 触发 CI/CD 三端构建

### 安全
- WebSocket 消息体上限 64KB，peer_id 长度限制 128 字符
- API key / token 用 GitHub Secrets，不硬编码

### Rust
- 优先使用 `anyhow::Result`（或 crate 自定义 Error），日志用 `tracing` crate
- 信令消息体用 `serde_json::Value` 动态字段

## 当前版本边界

### v0.0.3 架构迁移
P2P 业务逻辑从 Dart 迁入 Rust justtalk-core。Flutter 只做 UI。30 个 Rust 测试通过。

### 下版本优先
调试信令连接稳定性、LLM 集成、消息可靠送达

### v0.2+ 规划
端到端加密 (libsignal)、多人文字群聊、多人语音聊天

## CI/CD

推送 `v*.*.*` tag → Actions 自动构建 APK (ubuntu) + Windows ZIP + iOS .app/IPA (macos)。

## 关键文档

| 文档 | 内容 |
|------|------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | 完整架构图、数据流、状态模型 |
| [CODING_CONVENTIONS.md](CODING_CONVENTIONS.md) | 详细编码规范 |
| [plan.md](plan.md) | 版本路线图、任务分解、风险 |
| [README.md](README.md) | 项目总览、快速开始、iOS 签名指南 |
