# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

JustChat — P2P 文字聊天应用，扫码即连，无需账号。包名: `justchat`，工作区目录名: `JustTalk`。

| 属性 | 值 |
|------|-----|
| Flutter SDK | ^3.44.0 (stable) |
| Dart SDK | ^3.9.0 |
| Rust | edition 2024 |
| 当前版本 | v0.1.0 (已发布) |
| GitHub | https://github.com/Dreamy-MoLing/JustChat |

## 常用命令

```bash
# Flutter（在 justtalk-flutter/ 下执行）
cd justtalk-flutter
flutter pub get
flutter analyze                     # 必须零警告才能提交
flutter test                        # 运行测试
flutter run -d linux                # Linux 桌面开发
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 flutter build apk --release
flutter build linux --debug
flutter build windows --release     # 需 Windows 宿主
flutter build ios --release --no-codesign

# Rust（工作区根目录）
cargo build                         # 构建整个工作区
cargo test                          # 运行所有 Rust 测试
cargo run -p justtalk-signaling     # 启动信令服务器 (0.0.0.0:3000)
```

## 架构大图

```
Flutter App (justtalk-flutter/)
├── UI Layer (pages/)          HomePage, ChatPage, SettingsPage, NotificationsPage, QrScannerPage, InfoPage
├── State (models/)            ChatState, NotificationState (ChangeNotifier + Provider)
└── Services (services/)       P2pService (WebRTC + 信令), StorageService (SharedPreferences)
         │
         ├── WebSocket ──────► Rust 信令服务器 (justtalk-signaling/, Warp, :3000)
         └── WebRTC DataChannel ─── P2P 直连 (STUN/TURN)
```

**状态管理**: `MultiProvider` 注入 `ChatState` + `NotificationState` 全局单例。`Consumer<T>` 放在需要响应变化的最小 Widget 上。`context.read<T>()` 读取（不监听），`context.watch<T>()` 监听重绘。数据修改后必须调 `notifyListeners()`。只有这两个类使用 `ChangeNotifier`，新建状态类前先问能否复用 `ChatState`。

**持久化**: `SharedPreferences`，key 前缀 `messages_{peerId}`、`contacts`、`settings`。

**主题**: Material 3，`JustChatApp.teal` (#0D9488) + `JustChatApp.cream` (#FFF8E1)，圆角 12-24px。字体走 `GoogleFonts.notoSansTextTheme()`。

## 通信协议

**双协议栈，自动降级：**

| 协议 | 用途 | 格式 |
|------|------|------|
| JTC2 | 扫码配对（主力） | `JTC2:base64(version + token + name + sigAddr)`，80字节，QR Version 4-5 |
| JTC1 | 手动 SDP 交换（降级） | `JTC1:` + base64(gzip(json))，含完整 SDP + ICE |

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
- 优先 `anyhow::Result`，日志用 `tracing` crate
- 信令消息体用 `serde_json::Value` 动态字段

## 当前版本边界

### v0.1.0 已实现
JTC2 扫码配对、JTC1 手动 SDP、WebRTC DataChannel 1v1 文字聊天、信令服务器、消息持久化、通知系统、联系人管理、深链接

### 下版本优先
mDNS 局域网发现、双向扫码验证、消息发送状态、消息时间线、图片/文件传输

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
