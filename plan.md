# JustTalk — 项目开发计划书 (v3.0)

## 概述

JustTalk 是一款以个人主机间直接通信为核心的聊天软件。目标场景：两个朋友之间的文字聊天 → 多人语音开黑。

核心理念：能 P2P 就不走服务器，能直接就不绕路。

### 版本路线

| 版本 | 内容 | 目标时间 |
|------|------|---------|
| v0.1 | P2P 文字聊天（1v1）+ JTC2 扫码配对 + 消息持久化 | 里程碑 1 ✅ 基本完成 |
| v0.2 | 加密接口 + 端到端加密 | 里程碑 2 |
| v0.3 | 多人文字群聊 | 里程碑 3 |
| v0.5 | 多人语音聊天（开黑场景） | 里程碑 4 |
| v1.0 | 产品化：安装包、自更新、跨平台 | 里程碑 5 |

---

## 一、技术选型（不变）

同 v2.0 计划。Flutter + WebRTC DataChannel 架构已确认可行。

---

## 二、当前项目结构（2026-05-25 更新）

```
JustTalk/
├── justtalk-core/               # Rust 库（当前未使用，Dart 侧已实现全部逻辑）
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── protocol/
│       ├── crypto/
│       ├── network/
│       ├── identity/
│       └── storage/
│
├── justtalk-signaling/          # Rust 信令服务器（已实现基本信令路由）
│   ├── Cargo.toml
│   └── src/
│       └── main.rs              # Warp HTTP/WS，端口 3000
│
├── justtalk-flutter/            # Flutter 跨平台应用
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart            # App 入口 + deep link 处理
│   │   ├── models/
│   │   │   ├── chat_state.dart        # 核心状态（ChangeNotifier）— 已集成消息持久化
│   │   │   ├── pairing_code.dart      # JTC2 配对码编解码
│   │   │   └── notification_state.dart
│   │   ├── pages/
│   │   │   ├── home_page.dart         # 联系人列表 + JTC2/JTC1 双模式
│   │   │   ├── chat_page.dart
│   │   │   ├── settings_page.dart
│   │   │   ├── info_page.dart         # 使用教程（已适配 JTC2）
│   │   │   ├── qr_scanner_page.dart
│   │   │   └── notifications_page.dart
│   │   └── services/
│   │       ├── p2p_service.dart       # WebRTC + JTC2 信令 + JTC1 降级
│   │       └── storage_service.dart   # SharedPreferences 持久化
│   ├── android/
│   ├── ios/
│   └── windows/
│
├── plan.md                      # 本文件
└── research/                    # 调研笔记（空）
```

## 三、通信协议（v3.0 双协议栈）

### 3.1 JTC2 — 扫码配对协议（新增，v0.1 主协议）

**设计目标：** 二维码从 2-4KB（无法扫描）降到 40-120 字节（Version 4-5，任意二维码扫描器可用）。

**核心思路：** QR 码不再携带 SDP/ICE 数据，只携带随机 token + 昵称。

```
格式: JTC2:base64(version(1) + token(16) + nameLen(1) + name(N) + sigAddrLen(1) + sigAddr(N))
示例: JTC2:AgE3cnVVOEZ5SFk4WTBfQQ0...

流程:
  用户 A (扫码展示方)              用户 B (扫码方)
    │                                │
    │── 生成 JTC2 令牌 ──→ QR 码 ──→│ 扫码
    │                                │── 解码获取昵称 → 自动创建联系人
    │                                │── 尝试通过信令服务器连接
    │◄══════ 自动 SDP 交换 ════════►│
    │◄══════ P2P DataChannel ══════►│
```

**优点：** 好友昵称即时可见，无需手动输入；一码到位无需应答码。

### 3.2 JTC1 — 手动 SDP 交换协议（保留，降级方案）

连接码格式：`JTC1:` + base64(gzip(json))，包含完整 SDP offer/answer + ICE candidates。

用于无信令服务器场景。

### 3.3 信令协议（JSON over WebSocket）—— 待扩展

当前 rust 信令服务器（justtalk-signaling）已实现：

```
register → peer_online/peer_offline  # 上下线广播
connect / accept_connect              # 连接配对
sdp_offer                             # SDP 转发
ice_candidate                         # ICE 转发
ping / pong                           # 心跳
```

**待添加：**

```
# 扫码自动配对（v0.1 第二阶段）
pair_intent                   # 注册配对意图（含 display_name）
connect_via_pair              # QR 扫码后自动触发配对
```

### 3.4 消息格式

同 v2.0：Envelope 结构 + MessagePack 编码。当前 Flutter 侧用 JSON 明文直接传输 DataChannel。

---

## 四、开发任务分解（当前状态）

### v0.1 — P2P 文字聊天（1v1）✅ 已接近完成

| # | 任务 | 状态 | 备注 |
|---|------|------|------|
| 1 | justtalk-core 库骨架 | ✅ | 未实际使用 |
| 2 | 身份系统（Ed25519 密钥对生成） | ✅ | 未实际使用 |
| 3 | 消息协议（Envelope + MessagePack） | ✅ | 未实际使用 |
| 4 | 明文加密层（PlainEncryptor） | ✅ | 未实际使用 |
| 5 | 信令服务器（Warp + WebSocket + SDP/ICE 转发） | ✅ | 基本路由已实现 |
| 6 | Flutter UI（联系人列表、聊天、设置） | ✅ | |
| 7 | P2pService（WebRTC + 手动 SDP 交换 JTC1） | ✅ | |
| 8 | ChatState 集成 P2pService | ✅ | |
| 9 | 手动 SDP 交换 UI（生成/输入连接码） | ✅ | |
| 10 | 信令模式 UI（自动连接） | ✅ | |
| 11 | JTC2 扫码配对协议（PairingCode 编解码） | ✅ | |
| 12 | JTC2 集成到 ChatState + P2pService | ✅ | generatePairingCode/acceptPairingCode/handleConnectionCode |
| 13 | JTC2 UI 更新（二维码、教程、扫码自动建联系人） | ✅ | |
| 14 | 消息持久化（StorageService + ChatState） | ✅ | SharedPreferences 完整 CRUD |
| 15 | **dart analyze lib/ + flutter build linux --debug** | ✅ | dart analyze 零警告零错误。Linux 构建通过。Android Gradle 失败（Java 25 EA 兼容性问题，与代码无关）。Windows 需 Windows 环境。 |
| 16 | **信令服务器 pair_intent + connect_via_pair 路由** | ✅ | 已添加两个命令：pair_intent（存储 display_name）、connect_via_pair（转发 pair_connect 到目标 peer）。编译通过。 |

### v0.2 — 端到端加密

| # | 任务 | 状态 |
|---|------|------|
| 1 | 接入 libsignal，实现 SignalEncryptor | ❌ |
| 2 | 预密钥束（PreKeyBundle）生成和分发 | ❌ |
| 3 | Double Ratchet 会话管理 | ❌ |
| 4 | 消息存储加密（SQLCipher 或 age 加密） | ❌ |
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
| 1 | 音频采集 | ❌ |
| 2 | Opus 编码/解码（32kbps 语音模式） | ❌ |
| 3 | WebRTC 数据通道（webrtc-rs） | ❌ |
| 4 | P2P Mesh 连接管理 | ❌ |
| 5 | 音频播放（低延迟缓冲区） | ❌ |
| 6 | 房间管理（创建/加入/离开） | ❌ |

---

## 五、下一步详细规划（联网检索后汇总）

### 5.1 业界同类项目设计参考

基于联网检索到的信息，以下为 JustTalk 可借鉴的设计理念：

| 参考项目 | 借鉴点 |
|---------|--------|
| **Jami (Ring)** | OpenDHT 实现无服务器节点发现。远程节点通过 DHT 存储消息，在线时拉取。但也引入了延迟问题。我们的轻量场景不需要 DHT 全部功能，但离线消息的 Store-and-Forward 思路值得借鉴。 |
| **Briar** | 扫码双向验证（双方互扫）建立好友关系。Tor 匿名传输。离线消息通过蓝牙/WiFi Direct 接力传递。扫码验证流程（双方互扫确认身份）可以大幅提高安全性。 |
| **Signal** | Signal Protocol 加密 + 中央服务器做密钥分发。Phone-number-as-identity 方案不适合无服务器场景，但端到端加密的标准做法不可绕过。 |
| **Session (Oxen)** | Loki 区块链 + onion routing。会话加密基于 Signal Protocol 改造版（Session Protocol）。抽换手机号为 Session ID（公钥哈希），适合我们 16 字节 token 做身份 ID 的设计。 |
| **Bridgefy** | 离线消息通过蓝牙 mesh 中继。每个节点存储并转发。我们不直接抄袭蓝牙方案，但"消息中继"概念可以扩展到我们的信令服务器作为 store-and-forward 节点。 |
| **Berty** | 基于 IPFS + libp2p + mDNS 的完全 P2P 架构。关注 NAT 穿透和本地发现。mDNS+BLE 自动发现局域网内的好友，无需扫码即可弹出连接邀请。 |


### 5.2 短期：修复当前的 JTC2 自动扫码配对（优先级最高）

**问题：** Flutter 侧已经发送了 `pair_intent` 和 `connect_via_pair` 信令，但 Rust 信令服务器的 `handle_ws` 不认识这两个命令（match 中只捕获了 connect/accept_connect/sdp_offer/ice_candidate/ping）。扫码后两个客户端都能解码 JTC2、创建联系人，但 WebRTC 协商无法自动触发。

**修复方案：**

1. **justtalk-signaling/src/main.rs** — 添加两个新路由：
   - `pair_intent` → 在 state 中注册配对意图（扩展 ConnectedPeer 或新增 PairingIntent 结构），记录 display_name
   - `connect_via_pair` → 通知目标 peer 建立 WebRTC 连接；收到后目标 peer 的 `_handlePairConnect` 自动创建 PeerConnection 并发送 sdp_offer

2. **测试验证：** cargo run 启动信令服务器 + flutter run 启动两个客户端，扫码验证自动连接

3. **如果没有信令服务器的降级路径验证：** 当前 `_tryStunDirectConnect` 在双方同时发起 offer 时竞争，ICE 连接成功率取决于 NAT 类型。需要额外测试。

### 5.3 中期：v0.1 收尾 + 体验打磨（基于业界最佳实践）

| 优先级 | 功能 | 说明 |
|--------|------|------|
| ★★★ | **局域网自动发现（mDNS）** | 宅家/校园网下自动发现同一局域网内的好友，无需扫码。Flutter 侧用 `multicast_dns` 包或 Bonjour/Avahi 实现。完全零配置。 |
| ★★★ | **双向扫码验证（Briar 风格）** | 安全性提升：A 扫 B 的码 → 自动添加联系人 → 提示 B 也扫 A 的码以确认身份互认。当前单向扫码存在冒充风险。 |
| ★★☆ | **深链接（justchat://）** | Android/iOS 上点击链接直接打开 app 并弹窗确认添加好友。当前已在 main.dart 植入 basic handler，但未处理 JTC2 格式。 |
| ★★☆ | **消息发送状态** | 已发送/已送达/已读三态指示。当前只有发送成功没反馈。 |
| ★★☆ | **消息时间线** | 按日期分组 + 时间戳显示。当前聊天 UI 没有时间线。 |
| ★☆☆ | **图片/文件传输** | 通过 DataChannel 分块传输。WebRTC 原生支持二进制数据。参考 webrtc.github.io/samples 的 filetransfer 示例。 |
| ★☆☆ | **消息编辑/撤回** | 通过系统消息协议实现。需要消息 ID 追踪。 |
| ★☆☆ | **置顶联系人** | 列表排序改进。 |

### 5.4 长期：v0.2 加密 + v0.3 群聊 + v0.5 语音

按原计划推进。加密优先于群聊和语音。

---

## 六、关键风险（补充）

| 风险 | 影响 | 对策 |
|------|------|------|
| JTC2 降级路径不稳定 | STUN-only 状态竞争，对称 NAT 完全失败 | 信令服务器必须优先部署；TURN 中继（v0.2+）兜底。也可考虑让一个客户端切换为信令服务器角色（嵌入式信令）。 |
| mDNS 不跨子网 | 多个 WiFi AP 下的设备发现失败 | 增加手动 IP 输入备选方案；或通过 DHT 远程发现（长期）。 |
| 消息丢失 | P2P DataChannel 关闭时正在传输的消息丢失 | 增加消息确认 + 重传机制。存储为 pending 队列，P2P 恢复后自动重发。 |
| phone-as-signaling | 想让其中一方手机充当信令服务器 | 手机端运行 Rust Warp 服务器不现实。可考虑 Dart 原生实现 WebSocket 服务器（非对称角色），或使用第三台中继做信令。 |

---

## 七、依赖清单（补充 JTC2 相关）

新增 Flutter 依赖：
```yaml
  qr_flutter: ^4.1.0          # 二维码生成（已有）
  mobile_scanner: ^6.0.0      # 扫码（跨平台，替换旧版）
  multicast_dns: ^0.3.2       # mDNS 局域网发现（v0.1 收尾）
  share_plus: ^10.0.0         # 系统分享（已有）
  app_links: ^6.3.0           # 深链接（已有）
```

---

## 八、当前待办摘要（按优先级排序）

1. **信令服务器 pair_intent + connect_via_pair 路由** — 完成 JTC2 自动连接闭环
2. **flutter analyze + 构建验证** — 确保无编译错误
3. **局域网 mDNS 自动发现** — 零配置连接体验
4. **双向扫码验证** — 提升安全性
5. **flutter analyze + 构建通过后打标签 v0.1.0**

---

*计划版本: v3.0*
*更新日期: 2026-05-25*
*维护者: 舰长*
