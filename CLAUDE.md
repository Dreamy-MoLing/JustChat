# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

JustTalk 是一个 P2P 聊天应用，Rust 后端核心 + Flutter 跨平台前端。Flutter 侧包名为 `justchat`。

**技术栈：** Rust (edition 2024) / Dart / Flutter (SDK ^3.9.0, Flutter ^3.41.0)
**目标平台：** Windows、Android、iOS
**当前版本：** v0.1.0（1对1文字聊天）

## 常用命令

### Rust 工作区

```bash
cargo build                        # 构建整个工作区
cargo test                         # 运行所有 Rust 测试
cargo run -p justtalk-signaling    # 启动信令服务器（监听 0.0.0.0:3000）
```

### Flutter 应用

```bash
cd justtalk-flutter
flutter run -d windows             # Windows 桌面运行
flutter run -d android             # Android 运行
flutter test                       # 运行测试
flutter analyze                    # 代码分析
```

## 架构

```
justtalk-core/          # Rust 核心库：协议、加密、身份、网络、存储
justtalk-signaling/     # Rust 信令服务器（Warp，WebSocket）
justtalk-flutter/       # Flutter 跨平台应用
```

### 连接方式（双模式）

1. **手动 SDP 交换**（默认，零服务器）— 用户复制粘贴连接码建立 P2P 连接
2. **信令服务器**（可选）— 一方运行 justtalk-signaling，自动转发 SDP/ICE

### Flutter 核心结构

- `services/p2p_service.dart` — WebRTC 连接 + 信令 + 手动 SDP 交换
- `models/chat_state.dart` — 核心状态，集成 P2pService
- `pages/home_page.dart` — 联系人列表 + 连接码 UI（FAB 菜单）
- `pages/chat_page.dart` — 聊天界面，使用 sendChatMessage

### 信令服务器

- Warp 框架，端口 3000
- `GET /peers` — 在线 peer 列表
- `GET /health` — 健康检查
- `WS /ws` — WebSocket：register、connect、sdp_offer、ice_candidate 路由
- 状态：`Arc<RwLock<HashMap<String, ConnectedPeer>>>`（含 per-peer mpsc sender）

## 状态管理

Flutter 使用 **Provider + ChangeNotifier**：

- `ChatState` — 联系人、消息、P2pService 集成、连接状态
- `NotificationState` — 通知列表、未读计数

## 关键依赖

- **Rust:** serde, rmp-serde (MessagePack), warp, ed25519-dalek, tokio
- **Flutter:** flutter_webrtc, provider, web_socket_channel, uuid, google_fonts
