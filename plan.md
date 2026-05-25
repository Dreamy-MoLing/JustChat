# JustTalk — 项目开发计划书

## 概述

JustTalk 是一款以个人主机间直接通信为核心的聊天软件。目标场景：两个朋友之间的文字聊天 → 多人语音开黑。

核心理念：能 P2P 就不走服务器，能直接就不绕路。

### 版本路线

| 版本 | 内容 | 目标时间 |
|------|------|---------|
| v0.1 | P2P 文字聊天（1v1） | 里程碑 1 |
| v0.2 | 加密接口 + 端到端加密 | 里程碑 2 |
| v0.3 | 多人文字群聊 | 里程碑 3 |
| v0.5 | 多人语音聊天（开黑场景）| 里程碑 4 |
| v1.0 | 产品化：安装包、自更新、跨平台 | 里程碑 5 |

---

## 一、技术选型

### 1.1 客户端：Flutter

**选择 Flutter 的原因：**
- 舰长要求 **Windows + Android + iOS 三端兼容**
- Flutter 是唯一能从同一代码库同时覆盖三端的成熟方案
- 舰长已有 Flutter 项目经验（Flutter_items），学习成本低

| 方案 | Windows | Android | iOS | 适合度 |
|------|---------|---------|-----|--------|
| **Flutter** | ✅ | ✅ | ✅ | ★★★★★ |
| React Native | ❌(非原生) | ✅ | ✅ | ★★★ |
| Tauri 2.0 | ✅ | ⚠️(早期) | ⚠️(早期) | ★★ |

**Flutter 技术细节：**
- UI: Material 3 + google_fonts (Noto Sans 中文优化)
- 状态管理: Provider（轻量，够用）
- P2P 引擎: flutter_webrtc + web_socket_channel
- 主题: 青色(#0D9488) + 淡黄(#FFF8E1)，圆角 12-18px，Material 3 动效

### 1.2 P2P 网络层：WebRTC Data Channel

**核心问题：两个普通家庭的电脑如何直接通信？**

两个用户都在 NAT 后面（路由器），不能直接 TCP 连接。

**连接方式（双模式）：**

1. **手动 SDP 交换**（默认，零服务器）
   - 用户 A 生成连接码（SDP offer + ICE candidates，base64 编码）
   - 通过微信/QQ/面对面等方式发送给 B
   - B 输入连接码，生成应答码
   - A 输入应答码，P2P 连接建立
   - 隐私性最强：无任何中间人

2. **信令服务器**（可选，自动化）
   - 一方运行 justtalk-signaling 程序
   - 自动转发 SDP/ICE，无需手动操作
   - 适合频繁连接的场景

**NAT 穿透方案：**
- STUN: 获取公网 IP:Port（成功率 >80%）
- ICE 框架: 整体成功率 90-96%
- TURN: 中继兜底（v0.1 暂不实现，后续加 coturn）

### 1.3 信令服务器：Rust + Warp + WebSocket

**为什么需要信令服务器？**

P2P 不等于不需要服务器。两个客户端建立连接前，需要：
- 交换各自的公网地址（SDP 信息）
- 协商加密密钥
- 获取在线好友列表

**信令服务器只负责协调，不中转数据。** 聊天数据直接走 P2P 通道。

```
  用户 A                   信令服务器                  用户 B
    │                         │                         │
    │─── req_connect(B) ────▶│                         │
    │                         │─── notify_connect(A) ──▶│
    │                         │◀─── accept() ──────────│
    │◀── peer_info(B) ──────│                         │
    │                         │                         │
    │◄══════ P2P hole punching ──────────────────────►│
    │◄══════ 直接加密通信 ────────────────────────────►│
```

**技术细节：**
- WebSocket 长连接（保持在线状态）
- JSON 编码
- 支持心跳保活
- 无数据库依赖（内存状态）

### 1.4 语音聊天：WebRTC（webrtc-rs）— v0.5

**场景分析：游戏开黑，3-5 人语音。**

**架构选择：**

| 架构 | 延迟 | 服务器成本 | 适合人数 | 适合 JustTalk？ |
|------|------|-----------|---------|----------------|
| P2P Mesh | ★★★★★ | 零 | 2-4人 | v0.5 首选 |
| SFU | ★★★★ | 中 | 5-50人 | v0.5 升级选 |
| MCU | ★★★ | 高 | 50+ | 过度设计 |

**技术选型：**
- **webrtc-rs** — Rust 的 WebRTC 实现
- Opus 编码（32kbps 语音模式，低延迟）
- 无需视频（纯音频，简化 DTLS 握手）

### 1.5 加密：Signal Protocol (libsignal) — v0.2

**为什么不是自己写加密？**

加密不是会了 AES 就能写的。Key management、forward secrecy、group messaging 全是坑。

**Signal Protocol 提供：**
- Double Ratchet：每条消息用不同密钥
- 前向保密（Forward Secrecy）
- 后向保密（Post-Compromise Security）
- libsignal 已在数十亿设备上验证

**接口设计（v0.1 预留，v0.2 实现）：**

```rust
pub trait MessageEncryptor: Send + Sync {
    fn encrypt(&self, plaintext: &[u8]) -> Result<Vec<u8>, CryptoError>;
    fn decrypt(&self, ciphertext: &[u8]) -> Result<Vec<u8>, CryptoError>;
}
```

## 二、项目结构

```
JustTalk/
├── justtalk-core/           # Rust 库 — 所有核心逻辑
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs           # 入口，导出模块
│       ├── protocol/        # 网络协议定义
│       │   ├── message.rs   # 聊天消息结构（MessagePack）
│       │   ├── signaling.rs # 信令协议（JSON over WebSocket）
│       │   └── room.rs      # 多人房间协议
│       ├── crypto/          # 加密层
│       │   ├── traits.rs    # MessageEncryptor trait
│       │   └── plain.rs     # v0.1 明文透传
│       ├── network/         # P2P 网络
│       │   ├── p2p.rs       # P2P 连接抽象
│       │   └── signaling_client.rs # 信令客户端
│       ├── identity/        # 身份系统
│       │   └── keypair.rs   # Ed25519 密钥对
│       └── storage/         # 本地存储
│           └── messages.rs  # 聊天记录存储
│
├── justtalk-signaling/      # 信令服务器（可单独部署）
│   ├── Cargo.toml
│   └── src/
│       └── main.rs          # Warp HTTP/WS 服务
│
├── justtalk-flutter/        # Flutter 跨平台应用
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart        # App 入口
│   │   ├── models/
│   │   │   ├── chat_state.dart      # 核心状态（ChangeNotifier）
│   │   │   └── notification_state.dart
│   │   ├── pages/
│   │   │   ├── home_page.dart       # 联系人列表 + 连接码 UI
│   │   │   ├── chat_page.dart       # 聊天界面
│   │   │   ├── settings_page.dart   # 设置页面
│   │   │   ├── info_page.dart       # 使用教程
│   │   │   └── notifications_page.dart
│   │   └── services/
│   │       └── p2p_service.dart     # WebRTC + 信令 + 手动 SDP 交换
│   ├── android/
│   ├── ios/
│   └── windows/
│
├── plan.md                  # 本文件
└── research/                # 调研笔记
    ├── p2p-nat-traversal.md
    ├── encryption-patterns.md
    └── voice-architecture.md
```

## 三、通信协议

### 3.1 消息格式（MessagePack 编码）

```rust
struct Envelope {
    version: u8,           // 协议版本
    msg_type: MessageType, // 消息类型
    sender_id: PeerId,     // 发送者 ID
    timestamp: u64,        // Unix 毫秒时间戳
    payload: Vec<u8>,      // 加密后的内容
}

enum MessageType {
    Text,           // 文字消息
    System,         // 系统通知（上线、离线）
    VoiceFrame,     // 语音帧
    KeyExchange,    // 密钥交换
    Presence,       // 在线状态变更
}
```

### 3.2 信令协议（JSON over WebSocket）

```
客户端 → 服务器:
  {"cmd": "register",     "peer_id": "...", "pubkey": "..."}
  {"cmd": "connect",      "target_id": "..."}
  {"cmd": "accept_connect","target_id": "..."}
  {"cmd": "sdp_offer",    "target_id": "...", "sdp": "..."}
  {"cmd": "ice_candidate","target_id": "...", "candidate": "..."}
  {"cmd": "ping"}

服务器 → 客户端:
  {"cmd": "registered",   "success": true, "peer_id": "..."}
  {"cmd": "peer_online",  "peer_id": "..."}
  {"cmd": "peer_offline", "peer_id": "..."}
  {"cmd": "connect_req",  "from_id": "..."}
  {"cmd": "sdp_offer",    "from_id": "...", "sdp": "..."}
  {"cmd": "ice_candidate","from_id": "...", "candidate": "..."}
  {"cmd": "pong"}
```

### 3.3 手动 SDP 交换格式

连接码格式：`JTC1:` + base64(gzip(json))

```json
{
  "sdp": {"type": "offer", "sdp": "..."},
  "candidates": [
    {"candidate": "...", "sdpMid": "0", "sdpMLineIndex": 0}
  ]
}
```

## 四、开发任务分解

### v0.1 — P2P 文字聊天（1v1）

| # | 任务 | 状态 |
|---|------|------|
| 1 | justtalk-core 库骨架 | ✅ |
| 2 | 身份系统（Ed25519 密钥对生成） | ✅ |
| 3 | 消息协议（Envelope + MessagePack） | ✅ |
| 4 | 明文加密层（PlainEncryptor） | ✅ |
| 5 | 信令服务器（Warp + WebSocket + SDP/ICE 转发） | ✅ |
| 6 | Flutter UI（联系人列表、聊天、设置） | ✅ |
| 7 | P2pService（WebRTC + 手动 SDP 交换） | ✅ |
| 8 | ChatState 集成 P2pService | ✅ |
| 9 | 手动 SDP 交换 UI（生成/输入连接码） | ✅ |
| 10 | 信令模式 UI（自动连接） | ✅ |

**验收标准：**
两台电脑通过手动 SDP 交换或信令服务器，连接成功后能互发文字消息。

### v0.2 — 端到端加密

| # | 任务 |
|---|------|
| 1 | 接入 libsignal，实现 SignalEncryptor |
| 2 | 预密钥束（PreKeyBundle）生成和分发 |
| 3 | Double Ratchet 会话管理 |
| 4 | 消息存储加密（SQLCipher 或 age 加密） |
| 5 | 升级 v0.1 协议到加密通道（向后兼容） |

### v0.5 — 多人语音聊天

| # | 任务 |
|---|------|
| 1 | 音频采集（cpal 库，跨平台麦克风） |
| 2 | Opus 编码/解码（32kbps 语音模式） |
| 3 | WebRTC 数据通道（webrtc-rs） |
| 4 | P2P Mesh 连接管理（多对多 ICE） |
| 5 | 音频播放（低延迟缓冲区） |
| 6 | 房间管理（创建/加入/离开） |

## 五、关键风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| NAT 穿透失败 | 用户无法聊天 | TURN 中继兜底（v0.2+） |
| 对称 NAT（企业/校园网） | P2P 100% 失败 | TURN 中继必备 |
| 手动 SDP 交换太麻烦 | 用户体验差 | 信令服务器作为自动化备选 |
| 跨平台音频兼容性 | Mac 麦克风权限等问题 | cpal 库已验证支持多平台 |

## 六、依赖清单

### Rust crates（Cargo.toml 核心依赖）

```toml
# 网络
tokio = { version = "1", features = ["full"] }

# 序列化
serde = { version = "1", features = ["derive"] }
rmp-serde = "1"   # MessagePack
serde_json = "1"

# 身份
ed25519-dalek = "2"
rand = "0.8"

# 信令服务器
warp = "0.3"
futures-util = "0.3"
uuid = { version = "1", features = ["v4"] }
```

### Flutter 依赖（pubspec.yaml）

```yaml
dependencies:
  flutter_webrtc: ^0.12.0
  provider: ^6.1.2
  web_socket_channel: ^3.0.2
  google_fonts: ^6.2.1
  shared_preferences: ^2.3.5
  path_provider: ^2.1.5
  uuid: ^4.5.1
  intl: ^0.20.2
```

## 七、部署拓扑

```
模式一：手动 SDP 交换（零服务器）

  用户 A                          用户 B
    │                               │
    │── 生成连接码 ──▶ (外部渠道) ──▶│ 输入连接码
    │                               │── 生成应答码 ──▶
    │◀── 输入应答码 ─ (外部渠道) ◀──│
    │                               │
    │◄══════ P2P 直接通信 ═════════►│


模式二：信令服务器

                     ┌──────────────┐
                     │ 信令服务器    │  (任一方主机运行)
                     │ WebSocket     │
                     │ 端口: 3000    │
                     └──┬───────────┘
                        │
              ┌─────────┼─────────┐
              │                   │
         ┌────▼───┐          ┌───▼────┐
         │ 用户 A  │          │ 用户 B  │
         │ Flutter │          │ Flutter │
         └─────────┘          └─────────┘
              │                      │
              └──── P2P 直接通信 ────┘
```

## 八、开发环境搭建

```bash
# 1. Rust 工具链
rustup default stable

# 2. Flutter 工具链
# 安装 Flutter SDK 3.41+
flutter doctor

# 3. 运行信令服务器
cargo run -p justtalk-signaling

# 4. 运行 Flutter 应用
cd justtalk-flutter
flutter run -d windows   # Windows
flutter run -d android   # Android
flutter run -d ios       # iOS

# 5. 运行测试
cargo test               # Rust 测试
cd justtalk-flutter && flutter test  # Flutter 测试
```

---

*计划版本: v2.0*
*更新日期: 2026-05-25*
*维护者: 舰长*
