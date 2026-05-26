# JustChat — 项目开发计划书 (v4.0)

## 概述

JustChat 是一款以个人主机间直接通信为核心的聊天软件。目标场景：两个朋友之间的文字聊天 → 多人语音开黑。

核心理念：能 P2P 就不走服务器，能直接就不绕路。

### 版本路线

| 版本 | 内容 | 目标时间 | 状态 |
|------|------|---------|------|
| v0.0.1 | P2P 文字聊天（1v1）全 Dart 实现 + JTC2 | 2026-05 | ✅ 已发布 |
| v0.0.2 | 修复 JTC2 死锁、CI/CD 三端构建 | 2026-05 | ✅ 当前调试版本 |
| v0.0.3 | **架构迁移：P2P 逻辑从 Dart 迁入 Rust justtalk-core** | 2026-05 | 🔄 进行中 |
| v0.2 | 端到端加密 (libsignal) | 待定 | ❌ 计划中 |
| v0.3 | 多人文字群聊 | 待定 | ❌ 计划中 |
| v0.5 | 多人语音聊天 | 待定 | ❌ 计划中 |
| v1.0 | 产品化 | 待定 | ❌ 计划中 |

### v0.0.3 架构迁移（已完成核心）

P2P 业务逻辑从 Flutter/Dart 移到 Rust justtalk-core 引擎层：

| 层 | v0.0.2 (旧) | v0.0.3 (新) |
|----|-----------|-----------|
| **UI** | Flutter pages + 内联业务逻辑 | Flutter pages（纯 Widget） |
| **状态** | ChatState 561行（ChangeNotifier + 全部逻辑） | ChatState ~200行（只持有 UI 数据 + 事件监听） |
| **WebRTC** | P2pService 701行（含状态机 + 信令客户端） | WebrtcAdapter ~160行（纯 flutter_webrtc 适配，无业务逻辑） |
| **配对** | PairingCode 175行（Dart JTC2 编解码） | Rust protocol/pairing.rs（JTC1/JTC2 完整实现，二进制兼容） |
| **协议** | 分散在 Dart 各处（JSON 手动拼接） | Rust protocol/signaling.rs（匹配实际服务器协议） |
| **信令** | Dart WebSocket client | Rust signaling_client.rs（tokio-tungstenite） |
| **存储** | SharedPreferences（Dart） | Rust JSON 文件存储（MessageStore + ContactStore + SettingsStore） |
| **引擎** | 无（ChatState 兼任） | Rust P2pEngine（整合所有子系统） |
| **FFI** | 无 | Rust api.rs（C FFI，JSON 序列化跨边界） |

**Rust 模块清单（30 个测试全部通过）：**
- `protocol/` — webrtc_types, signaling（重写）, pairing（JTC1/JTC2）, message, room
- `network/` — signaling_client（tokio-tungstenite 实现）
- `engine/` — P2pEngine, peer_manager, state_machine, pairing_flow
- `storage/` — MessageStore, ContactStore, SettingsStore（JSON 文件）
- `identity/` — KeyPair（ed25519，已完整）
- `crypto/` — MessageEncryptor trait + PlainEncryptor

- GitHub: https://github.com/Dreamy-MoLing/JustChat
- Release: https://github.com/Dreamy-MoLing/JustChat/releases/tag/v0.1.0
- CI/CD: push tag `v*.*.*` 自动三端构建

---

## 一、技术选型

Flutter + WebRTC DataChannel 架构。Provider + ChangeNotifier 状态管理。

**Flutter 依赖**: flutter_webrtc, provider, web_socket_channel, mobile_scanner, qr_flutter, share_plus, app_links, shared_preferences, google_fonts, uuid, intl

**Rust 依赖**: serde, warp, ed25519-dalek, tokio, futures-util, parking_lot

---

## 二、项目结构

```
JustTalk/                           # 工作区根目录
├── justtalk-flutter/               # Flutter 应用 (包名: justchat)
├── justtalk-core/                  # Rust 核心库 (预留)
├── justtalk-signaling/             # Rust 信令服务器
├── research/                       # 调研笔记
├── .github/workflows/              # CI/CD
├── CLAUDE.md                       # Claude Code 约束
├── ARCHITECTURE.md                 # 架构文档
├── CODING_CONVENTIONS.md           # 编码规范
├── plan.md                         # 本文件
└── README.md                       # 项目总览
```

---

## 三、通信协议（双协议栈）

### 3.1 JTC2 — 扫码配对协议（v0.1 主协议）

**设计目标：** 二维码从 2-4KB 降到 40-120 字节（Version 4-5，任意二维码扫描器可用）。

**格式:** `JTC2:base64(version(1) + token(16) + nameLen(1) + name(N) + sigAddrLen(1) + sigAddr(N))`

**流程:** A 展示 QR → B 扫码 → 解码获取昵称 → 自动创建联系人 → 信令连接 → P2P DataChannel

**优点：** 好友昵称即时可见；一码到位无需应答码。

### 3.2 JTC1 — 手动 SDP 交换协议（降级方案）

连接码格式：`JTC1:` + base64(gzip(json))，含完整 SDP offer/answer + ICE candidates。
用于无信令服务器场景。

### 3.3 信令协议（JSON over WebSocket）

信令服务器路由（`justtalk-signaling/src/main.rs`）:

| 命令 | 方向 | 说明 |
|------|------|------|
| register | → | 注册 peer_id + pubkey |
| registered | ← | 注册确认 |
| peer_online | ← (广播) | 新 peer 上线 |
| peer_offline | ← (广播) | peer 断开 |
| connect | → | 请求连接 target_id |
| connect_req | ← | 连接请求转发 |
| accept_connect | → | 接受连接 |
| pair_intent | → | 设置 display_name |
| connect_via_pair | → | 扫码后触发配对连接 |
| pair_connect | ← | 配对连接通知 |
| sdp_offer | ⇄ | SDP Offer 转发 |
| ice_candidate | ⇄ | ICE Candidate 转发 |
| ping/pong | ⇄ | 心跳 |

### 3.4 消息格式

当前使用 JSON 明文通过 DataChannel 直接传输。v0.2 将切换到 MessagePack (Envelope 结构)。

---

## 四、开发任务分解

### v0.1 — P2P 文字聊天（1v1） ✅ v0.1.0 已发布

| # | 任务 | 状态 | 备注 |
|---|------|------|------|
| 1-4 | justtalk-core 库（骨架/身份/协议/加密） | ✅ | 未实际使用，为 v0.2 预留 |
| 5 | 信令服务器（Warp WebSocket + SDP/ICE 转发） | ✅ | 含 pair_intent / connect_via_pair |
| 6 | Flutter UI（联系人、聊天、设置、通知、教程） | ✅ | 5 个页面 + 3 个 model |
| 7 | P2pService（WebRTC + JTC1 + JTC2 + 信令） | ✅ | 双协议栈 |
| 8 | ChatState 集成 P2pService | ✅ | |
| 9 | 手动 SDP 交换 UI | ✅ | |
| 10 | 信令模式 UI（自动连接） | ✅ | |
| 11 | JTC2 扫码配对协议（PairingCode 编解码） | ✅ | |
| 12 | JTC2 集成到 ChatState + P2pService | ✅ | |
| 13 | JTC2 UI（二维码、教程、扫码自动建联系人） | ✅ | |
| 14 | 消息持久化（StorageService + SharedPreferences） | ✅ | |
| 15 | 构建验证 + flutter analyze 零警告 | ✅ | Android/Linux 通过 |
| 16 | 深链接 (justchat://connect) | ✅ | main.dart 内实现 |
| 17 | 通知系统 (右上角图标 + 通知页面) | ✅ | |
| 18 | CI/CD (GitHub Actions 三端构建) | ✅ | |
| 19 | iOS Info.plist 修正显示名 | ✅ | Justtalk → JustChat |

### v0.1 收尾 — 体验打磨（下版本优先，按优先级排序）

| 优先级 | 功能 | 说明 |
|--------|------|------|
| ★★★ | **局域网自动发现（mDNS）** | 宅家/校园网下自动发现好友，零配置。`multicast_dns` 包实现 |
| ★★★ | **双向扫码验证** | A 扫 B → 提示 B 也扫 A → 互认身份。防冒充 |
| ★★☆ | **消息发送状态** | 已发送/已送达/已读三态 |
| ★★☆ | **消息时间线** | 按日期分组 + 时间戳 |
| ★☆☆ | **图片/文件传输** | DataChannel 分块传输 |
| ★☆☆ | **消息编辑/撤回** | 系统消息协议，需消息 ID 追踪 |
| ★☆☆ | **置顶联系人** | 列表排序 |

### v0.2 — 端到端加密

| # | 任务 | 状态 |
|---|------|------|
| 1 | 接入 libsignal，实现 SignalEncryptor | ❌ |
| 2 | 预密钥束（PreKeyBundle）生成和分发 | ❌ |
| 3 | Double Ratchet 会话管理 | ❌ |
| 4 | 消息存储加密 | ❌ |
| 5 | 升级 v0.1 协议到加密通道（向后兼容） | ❌ |

### v0.3 — 多人文字群聊

| # | 任务 | 状态 |
|---|------|------|
| 1 | Mesh 多连接管理 | ❌ |
| 2 | 房间协议（create/join/leave） | ❌ |
| 3 | 群聊 UI | ❌ |

### v0.5 — 多人语音聊天

| # | 任务 | 状态 |
|---|------|------|
| 1 | 音频采集/Opus 编码 | ❌ |
| 2 | WebRTC 数据通道音频流 | ❌ |
| 3 | P2P Mesh 连接管理 | ❌ |
| 4 | 低延迟音频播放 | ❌ |
| 5 | 房间管理 | ❌ |

---

## 五、风险

| 风险 | 影响 | 对策 |
|------|------|------|
| JTC2 STUN-only 降级不稳定 | 对称 NAT 完全失败 | 信令服务器优先部署；TURN 兜底 |
| mDNS 不跨子网 | 多 AP 下发现失败 | 手动 IP 输入备选 |
| 消息丢失 | 连接关闭时消息丢失 | 消息确认 + 重传 + pending 队列 |
| iOS 签名需 $99/年 | 无法分发 IPA | CI 构建 unsigned .app + 文档引导 |

---

*计划版本: v4.0*
*更新日期: 2026-05-26*
*维护者: 舰长*
