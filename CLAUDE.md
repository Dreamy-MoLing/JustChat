# CLAUDE.md

项目根约束文件 — Claude Code 在本仓库工作时的指引。

## 项目概述

JustChat — P2P 文字聊天应用。扫码即连，无需账号。

| 属性 | 值 |
|------|-----|
| Flutter SDK | ^3.44.0 (stable) |
| Dart SDK | ^3.9.0 |
| Rust | edition 2024 |
| 当前版本 | v0.1.0 (已发布) |
| GitHub | https://github.com/Dreamy-MoLing/JustChat |
| CI/CD | `.github/workflows/release.yml` — 打 tag v* 自动三端构建 |

## 目录结构

```
JustTalk/                               # 工作区根目录
├── justtalk-flutter/                   # Flutter 跨平台应用
│   ├── lib/
│   │   ├── main.dart                   # App 入口 + 深链接处理 + 主题定义
│   │   ├── models/
│   │   │   ├── chat_state.dart         # 核心状态: 联系人/消息/P2P/设置 (ChangeNotifier)
│   │   │   ├── notification_state.dart # 通知列表、未读计数 (ChangeNotifier)
│   │   │   └── pairing_code.dart       # JTC2 短 token 编解码
│   │   ├── pages/
│   │   │   ├── home_page.dart          # 联系人列表 + 抽屉 + 通知 + 添加联系人
│   │   │   ├── chat_page.dart          # 聊天界面 (消息气泡、输入框)
│   │   │   ├── info_page.dart          # 使用教程 (4步)
│   │   │   ├── notifications_page.dart # 通知列表页
│   │   │   ├── qr_scanner_page.dart    # JTC2 扫码页
│   │   │   └── settings_page.dart      # 设置 (显示名/信令/通知开关)
│   │   └── services/
│   │       ├── p2p_service.dart        # WebRTC 连接 + 信令 + 手动 SDP 交换
│   │       └── storage_service.dart    # SharedPreferences 持久化 (消息/联系人)
│   ├── test/
│   │   └── widget_test.dart            # 基础渲染测试
│   ├── android/                        # Android 平台
│   ├── ios/                            # iOS 平台
│   ├── windows/                        # Windows 平台
│   └── linux/                          # Linux 平台
├── justtalk-core/                      # Rust 核心库 (v0.2+ 使用)
│   └── src/
│       ├── crypto/   (plain.rs, traits.rs)
│       ├── identity/ (keypair.rs)
│       ├── network/  (p2p.rs, signaling_client.rs)
│       ├── protocol/ (message.rs, room.rs, signaling.rs)
│       └── storage/  (messages.rs)
├── justtalk-signaling/                 # Rust 信令服务器
│   └── src/main.rs                     # Warp HTTP/WS, 端口 3000
├── research/                           # 调研笔记 (P2P NAT/加密/语音)
├── .github/workflows/
│   └── release.yml                     # CI/CD: 三端并行构建
├── CLAUDE.md                           # 本文件
├── plan.md                             # 版本路线图
├── ARCHITECTURE.md                     # 架构设计文档
├── CODING_CONVENTIONS.md               # 编码规范
└── README.md                           # 项目总览 + 快速开始
```

## 常用命令

### Flutter

```bash
cd justtalk-flutter
flutter pub get
flutter analyze                     # 必须零警告才能提交
flutter test                        # 运行测试
flutter run -d linux                # Linux 桌面
flutter build apk --release         # Android APK
flutter build linux --debug         # Linux 桌面构建
flutter build windows --release     # Windows (需 Windows 宿主)
flutter build ios --release --no-codesign  # iOS unsigned
```

### Rust

```bash
cargo build                         # 构建整个工作区
cargo test                          # 运行所有 Rust 测试
cargo run -p justtalk-signaling     # 启动信令服务器 (0.0.0.0:3000)
```

## 通信协议 (双协议栈)

### JTC2 — 扫码配对 (v0.1 主协议)

80 字节短 token，编码在 Version 4-5 QR 码中，任意扫码器可用。

```
格式: JTC2:base64(version(1) + token(16) + nameLen(1) + name(N) + sigAddrLen(1) + sigAddr(N))
流程: A 展示 QR → B 扫码 → 解码获取昵称 → 自动创建联系人 → 信令连接
```

### JTC1 — 手动 SDP 交换 (降级方案)

连接码格式: `JTC1:` + base64(gzip(json))，含完整 SDP offer/answer + ICE candidates。
用于无信令服务器场景。

## 信令协议 (JSON over WebSocket)

注册 → `register` → 返回 `registered` + 广播 `peer_online`
配对 → `pair_intent` (存 display_name) → `connect_via_pair` (转发给目标 peer)
连接 → `connect` / `accept_connect` → `sdp_offer` → `ice_candidate`
心跳 → `ping` / `pong`

## 关键架构决策

1. **Provider + ChangeNotifier** 状态管理（非 Riverpod/Bloc），保持轻量
2. **SharedPreferences** 持久化（非 SQLite），v0.1 数据量小，够用
3. **双协议栈**: JTC2（扫码/信令） + JTC1（手动/零服务器），自动降级
4. **Rust 核心库当前未使用** — 为 v0.2 加密等预留，所有 v0.1 逻辑在 Dart 侧
5. **Material 3 主题**: teal (#0D9488) + cream (#FFF8E1)，圆角 12-24px
6. **配色常量** 在 `main.dart` 的 `JustChatApp` 类中定义（teal, cream, tealLight 等）

## 当前版本边界

### v0.1.0 已实现
- [x] JTC2 扫码配对 + 自动创建联系人
- [x] JTC1 手动 SDP 交换
- [x] WebRTC DataChannel 1对1文字聊天
- [x] 信令服务器 (pair_intent / connect_via_pair 路由)
- [x] 消息持久化 (SharedPreferences)
- [x] 通知系统 (好友申请 / 更新 / 新消息)
- [x] 联系人管理 + 在线状态
- [x] 深链接 (justchat://connect?code=...)

### v0.1.0 未包含 (下版本优先)
- [ ] 局域网 mDNS 自动发现
- [ ] 双向扫码验证 (Briar 风格)
- [ ] 消息发送状态 (已发送/已送达/已读)
- [ ] 消息时间线 (按日期分组)
- [ ] 图片/文件传输
- [ ] 消息编辑/撤回

### v0.2+ 规划
- [ ] 端到端加密 (libsignal)
- [ ] 多人文字群聊
- [ ] 多人语音聊天

## 质量要求

- `flutter analyze` 必须零警告才能提交
- Dart 使用 `dart format` 风格
- Widget 树保持适度深度，超长时抽取独立 Widget
- 中文注释，英文变量/函数名
- 提交前运行 test 验证基础渲染

## CI/CD

推送 `v*.*.*` 标签 → Actions 自动构建:

| 产物 | Runner |
|------|--------|
| APK (universal + split) | ubuntu-latest |
| Windows ZIP (exe+DLLs) | windows-latest |
| iOS .app (unsigned) | macos-latest |
| iOS IPA (signed, 可选) | macos-latest |

iOS 签名需先配置 GitHub Variables/Secrets，详见 README.md。
