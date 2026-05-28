# JustChat

P2P 文字聊天应用。扫码即连，无需账号。

**技术栈**: Flutter (Dart) + WebRTC DataChannel + Rust 引擎 (FFI)

## 下载

前往 [Releases](https://github.com/Dreamy-MoLing/JustChat/releases/latest) 下载对应平台的安装包。

| 平台 | 文件 | 说明 |
|------|------|------|
| **Android** | `JustChat-*-android-arm64-v8a.apk` | 大多数现代手机（推荐） |
| | `JustChat-*-android-armeabi-v7a.apk` | 旧款 32 位手机 |
| | `JustChat-*-android-x86_64.apk` | Android 模拟器 |
| **Windows** | `JustChat-*-windows-x64.zip` | 解压后运行 `justchat.exe` |
| **iOS** | `JustChat-*-ios-unsigned.app.zip` | 需自行签名或使用 TestFlight |
| | `JustChat-*-ios.xcarchive.zip` | Xcode 归档，用于分发 |

> **Android 用户**：下载 APK 后在设置中允许"安装未知来源应用"即可安装。大多数手机选 `arm64-v8a` 版本，不确定可在「设置 → 关于手机 → 处理器」查看架构。

## 快速开始

```bash
# 启动信令服务器（用于扫码配对）
cargo run -p justtalk-signaling

# 另一个终端启动 Flutter 应用
cd justtalk-flutter
flutter pub get
flutter run -d linux     # Linux 桌面
flutter run -d android   # Android（需连接设备或模拟器）
```

### 使用方式

1. 双方各自启动应用，自动连接信令服务器
2. 一方点击「生成连接码」展示二维码
3. 另一方点击「扫码连接」扫描二维码
4. 配对成功，开始聊天

也支持手动粘贴 JTC1 连接码（无信令服务器场景的降级方案）。

## 项目结构

```
justtalk-flutter/          # Flutter 跨平台应用
├── lib/
│   ├── main.dart          # 入口、主题、深链接
│   ├── models/            # ChatState, NotificationState
│   ├── pages/             # HomePage, ChatPage, SettingsPage, etc.
│   └── services/          # EngineBridge, NativeFFI, WebrtcAdapter
└── test/

justtalk-core/             # Rust 核心引擎（P2P 逻辑、信令、存储）
├── src/
│   ├── api.rs             # FFI 接口（Dart↔Rust 桥梁）
│   ├── engine/            # P2pEngine 状态机、连接管理
│   ├── protocol/          # JTC1/JTC2 配对协议、信令消息
│   ├── network/           # WebSocket 信令客户端、重连、心跳
│   ├── crypto/            # 消息加密（预留）
│   ├── identity/          # Ed25519 密钥对
│   └── storage/           # JSON 文件持久化
└── tests/

justtalk-signaling/        # Rust 信令服务器（Warp + WebSocket）
├── src/main.rs
└── tests/

.github/workflows/         # CI/CD（push tag 自动构建）
```

## 架构

```
Flutter UI ──── EngineBridge (JSON) ──── Rust P2pEngine
    │                                        │
    ├─ WebrtcAdapter ◄── WebrtcCommand ──────┤
    │  (flutter_webrtc)                      │
    │                                        ├─ SignalingClient (WS)
    └─ P2pEvent ─────────────────────────────┘
         │                                  │
         └─ WebRTC DataChannel ────── P2P 直连
```

- **命令/事件模式**: Rust 引擎通过 `WebrtcCommand` 告诉 Dart 执行 WebRTC 操作，通过 `P2pEvent` 推送状态变化
- **FFI 桥接**: Dart 通过 `dart:ffi` 调用 Rust `api.rs`，JSON 序列化跨边界
- **状态管理**: Provider + ChangeNotifier，`ChatState` 为全局单例

## 版本

| 版本 | 内容 | 状态 |
|------|------|------|
| v0.0.4 | 代码清理、测试补充（63 tests）、结构优化 | 当前版本 |
| v0.0.3 | 架构迁移：Dart → Rust 引擎 | 已发布 |
| v0.0.2 | JTC2 死锁修复、CI/CD 三端构建 | 已发布 |
| v0.0.1 | P2P 文字聊天 + JTC2 扫码配对 | 已发布 |
| v0.2 | 端到端加密 (libsignal) | 计划中 |
| v0.3 | 多人文字群聊 | 计划中 |
| v0.5 | 多人语音聊天 | 计划中 |

## 开发

```bash
# 运行测试
cargo test                              # Rust 全量测试（63 个）
flutter test                            # Flutter 测试

# 代码检查
dart analyze                            # Flutter 零警告

# 构建
flutter build apk --release --split-per-abi   # Android
flutter build linux --debug                   # Linux
flutter build windows --release               # Windows（需 Windows 宿主）
flutter build ios --release --no-codesign     # iOS
```

## 通信协议

| 协议 | 用途 | 格式 |
|------|------|------|
| JTC2 | 扫码配对（主力） | `JTC2:base64(version + token + name + sigAddr)`，~80 字节 |
| JTC1 | 手动 SDP 交换（降级） | `JTC1:` + base64(gzip(json)) |

信令: JSON over WebSocket，支持 `register` / `pair_intent` / `connect_via_pair` / `sdp_offer` / `ice_candidate` / `ping`/`pong`。
