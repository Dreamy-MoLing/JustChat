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

# 信令服务器（可选，用于自动配对）
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

## CI/CD — GitHub Actions 自动构建

推送标签 `v*.*.*` 自动构建三平台安装包：

| 产物 | 平台 | Runner |
|------|------|--------|
| APK | Android | ubuntu-latest |
| ZIP (exe + DLLs) | Windows | windows-latest |
| .app / .xcarchive | iOS (unsigned) | macos-latest |
| IPA | iOS (signed) | macos-latest |

### iOS 签名配置（可选）

要生成可安装的 IPA，需要以下步骤：

**前提**: Apple Developer Program 会员资格 ($99/年)

**1. 注册 Bundle ID**

在 https://developer.apple.com/account/resources/identifiers 注册 App ID，例如 `com.justchat.app`

**2. 创建 Distribution Certificate**

在 Xcode → Settings → Accounts → Manage Certificates，点击 + 选择 "Apple Distribution"。导出为 .p12（需要密码）。

**3. 创建 Provisioning Profile**

在 https://developer.apple.com/account/resources/profiles 创建 App Store Distribution Profile，绑定上述 Bundle ID 和 Certificate。

**4. 设置 GitHub 仓库变量和密钥**

| 类型 | 名称 | 值 |
|------|------|----|
| Variables | `IOS_SIGNING_ENABLED` | `true` |
| Variables | `IOS_TEAM_ID` | 你的 Team ID（10 位字母数字，Apple Developer 页面可查） |
| Variables | `IOS_BUNDLE_ID` | 注册的 Bundle ID，如 `com.justchat.app` |
| Secrets | `IOS_CERT_P12_B64` | `.p12` 文件的 base64 编码 |
| Secrets | `IOS_CERT_PASSWORD` | 导出 .p12 时设置的密码 |
| Secrets | `IOS_PROFILE_B64` | `.mobileprovision` 文件的 base64 编码 |

**生成 base64**:

```bash
base64 -w0 /path/to/Certificates.p12   # 输出填入 IOS_CERT_P12_B64
base64 -w0 /path/to/Profile.mobileprovision  # 输出填入 IOS_PROFILE_B64
```

**5. 推送标签触发构建**

```bash
git tag v0.2.0
git push origin v0.2.0
# Actions 自动构建，release 页面出现 IPA
```
