# JustChat

P2P 文字聊天应用。扫码即连，无需账号。

**技术栈**: Flutter (Dart) + WebRTC DataChannel + Rust 信令服务器

## 快速开始

```bash
# Flutter 应用
cd justtalk-flutter
flutter pub get
flutter run -d linux     # Linux 桌面
flutter run -d android   # Android（需连接设备或模拟器）

# 信令服务器（用于扫码配对）
cargo run -p justtalk-signaling
# 监听 0.0.0.0:3000
```

## 项目结构

```
├── justtalk-flutter/       # Flutter 跨平台应用
│   └── lib/
│       ├── main.dart
│       ├── models/         # ChatState, NotificationState, PairingCode
│       ├── pages/          # HomePage, ChatPage, SettingsPage, etc.
│       └── services/       # P2pService, StorageService
├── justtalk-core/          # Rust 核心库（为 v0.2 加密预留）
├── justtalk-signaling/     # Rust 信令服务器（Warp + WebSocket）
└── .github/workflows/      # CI/CD 自动构建
```

## 版本

| 版本 | 内容 | 状态 |
|------|------|------|
| v0.1 | P2P 文字聊天 + JTC2 扫码配对 + 消息持久化 | ✅ 发布 |
| v0.2 | 端到端加密 | 计划中 |
| v0.3 | 多人文字群聊 | 计划中 |
| v0.5 | 多人语音聊天 | 计划中 |
