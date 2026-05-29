# JustChat

P2P 文字聊天应用。扫码即连，无需账号。

**技术栈**: Flutter + Rust 引擎 (FFI) + WebRTC DataChannel

---

## 安装与部署

### 下载安装包

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

### 从源码构建

**环境要求：**
- Flutter SDK >= 3.41.0
- Dart SDK >= 3.9.0
- Rust (edition 2024)
- Android Studio / Xcode（移动端）

```bash
# 克隆仓库
git clone https://github.com/Dreamy-MoLing/JustChat.git
cd JustChat

# 安装 Flutter 依赖
cd justtalk-flutter
flutter pub get

# 构建 Rust 引擎（首次需要）
cd ..
cargo build

# 启动信令服务器
cargo run -p justtalk-signaling

# 新终端中启动 Flutter 应用
cd justtalk-flutter
flutter run -d linux      # Linux 桌面
flutter run -d android    # Android
flutter run -d windows    # Windows
flutter run -d macos      # macOS
```

### 信令服务器部署

信令服务器用于扫码配对阶段的 P2P 握手。默认连接 `wss://justchat-signaling.fly.dev`，也可自建：

```bash
# 构建信令服务器
cargo build -p justtalk-signaling --release

# 启动（默认监听 0.0.0.0:3000）
./target/release/justtalk-signaling

# 或指定端口
PORT=8080 ./target/release/justtalk-signaling
```

在应用「设置 → 信令服务器」中填写自建地址即可切换。

### 构建发布包

```bash
# Android（按 ABI 分包，推荐）
flutter build apk --release --split-per-abi

# Linux
flutter build linux --release

# Windows（需 Windows 宿主）
flutter build windows --release

# iOS（需 macOS）
flutter build ios --release --no-codesign
```

CI/CD：推送 `v*.*.*` tag 后 GitHub Actions 自动构建 Android、Windows、iOS 三端。

---

## 功能介绍

### 欢迎引导

首次启动展示三色光晕聚拢动画，随后进入三步引导：

1. **设置昵称** — 让朋友认出你
2. **扫描二维码** — 点击 + 按钮，对准朋友屏幕
3. **开始聊天** — P2P 直连，安全无忧

### 底边栏导航

三个标签页，选中项凸起并附有主色强调：

| 标签 | 功能 |
|------|------|
| **圈子** | 社交动态（即将上线） |
| **聊天** | 联系人列表、消息收发（默认页） |
| **个人** | 头像、昵称、设置入口 |

### 连接方式

应用提供三种连接方式：

| 方式 | 场景 | 说明 |
|------|------|------|
| **扫码连接** | 面对面 | 一方展示二维码，另一方扫码，自动完成配对 |
| **粘贴连接码** | 远程 | 通过微信等分享连接码，粘贴到应用中 |
| **手动添加** | 调试 | 输入对方 Peer ID 直接连接 |

### 聊天功能

- **P2P 直连** — 消息通过 WebRTC DataChannel 直接传输，不经过服务器
- **消息气泡** — 自己的消息右对齐（青色渐变），对方的消息左对齐（白色）
- **在线状态** — 联系人卡片显示实时连接状态
- **联系人管理** — 左滑删除联系人及聊天记录
- **桌面分栏** — 宽屏（>=600px）自动切换为左侧联系人列表 + 右侧聊天面板

### 个人页

- 渐变头像（取昵称首字母）
- 显示 Peer ID
- 设置入口：通知设置、信令服务器配置、使用帮助

### 二维码扫描

- 全屏摄像头扫描
- 支持 JTC2（扫码配对，主力）和 JTC1（手动 SDP 交换，降级方案）
- JTC1 扫描后自动生成应答码展示

### 深链接

支持 `justchat://connect?code=JTC1:...` 或 `JTC2:...` 格式的深链接，可从浏览器或其他应用直接跳转连接。

---

## 通信协议

| 协议 | 用途 | 格式 |
|------|------|------|
| JTC2 | 扫码配对（主力） | `JTC2:base64(version + token + name + sigAddr)`，~80 字节 |
| JTC1 | 手动 SDP 交换（降级） | `JTC1:` + base64(gzip(json)) |

信令消息：JSON over WebSocket，支持 `register` / `pair_intent` / `connect_via_pair` / `sdp_offer` / `ice_candidate` / `ping` / `pong`。

---

## 项目结构

```
JustChat/
├── justtalk-flutter/        # Flutter 跨平台应用
│   ├── lib/
│   │   ├── main.dart        # 入口、主题、深链接
│   │   ├── models/          # ChatState, NotificationState
│   │   ├── pages/           # 页面（HomePage, ChatPage, WelcomePage...）
│   │   └── services/        # EngineBridge, NativeFFI, WebrtcAdapter
│   └── test/
│
├── justtalk-core/           # Rust 核心引擎
│   ├── src/
│   │   ├── api.rs           # FFI 接口（Dart↔Rust 桥梁）
│   │   ├── engine/          # P2pEngine 状态机
│   │   ├── protocol/        # JTC1/JTC2 配对协议
│   │   ├── network/         # WebSocket 信令客户端
│   │   ├── crypto/          # 消息加密（预留）
│   │   ├── identity/        # Ed25519 密钥对
│   │   └── storage/         # JSON 文件持久化
│   └── tests/
│
├── justtalk-signaling/      # Rust 信令服务器（Warp + WebSocket）
│
└── .github/workflows/       # CI/CD（push tag 自动构建）
```

### 架构总览

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

- **命令/事件模式**：Rust 引擎通过 `WebrtcCommand` 告诉 Dart 执行 WebRTC 操作，通过 `P2pEvent` 推送状态变化
- **FFI 桥接**：Dart 通过 `dart:ffi` 调用 Rust `api.rs`，JSON 序列化跨边界
- **状态管理**：Provider + ChangeNotifier，`ChatState` 为全局单例

---

## 开发

```bash
# 测试
cargo test --workspace             # Rust 全量测试（63 个）
flutter test                       # Flutter 测试

# 代码检查
dart analyze                       # Flutter 零警告

# 本地联调
cargo run -p justtalk-signaling    # 终端 1：信令服务器
cd justtalk-flutter && flutter run # 终端 2：Flutter 应用
```

---

## 版本历史

| 版本 | 内容 |
|------|------|
| **v0.0.5** | UI 重设计：圆角风格、三色光晕欢迎动画、底边栏导航、配色方案升级 |
| v0.0.4 | 代码清理、测试补充、结构优化 |
| v0.0.3 | 架构迁移：Dart → Rust 引擎 (FFI) |
| v0.0.2 | JTC2 死锁修复、CI/CD 三端构建 |
| v0.0.1 | P2P 文字聊天 + JTC2 扫码配对 |

---

## 未来计划

| 版本 | 功能 | 状态 |
|------|------|------|
| v0.1.0 | 圈子功能（社交动态信息流） | 计划中 |
| v0.2.0 | 端到端加密 (libsignal) | 计划中 |
| v0.3.0 | 多人文字群聊 | 计划中 |
| v0.4.0 | 文件/图片传输 | 计划中 |
| v0.5.0 | 多人语音聊天 | 计划中 |
| 未来 | 暗色模式 | 计划中 |
| 未来 | 消息可靠送达（离线队列） | 计划中 |

---

## 许可证

[MIT License](LICENSE)
