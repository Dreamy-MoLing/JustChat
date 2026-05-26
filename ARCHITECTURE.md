# JustChat 架构文档

## 系统架构总览

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App                        │
│  ┌───────────┐  ┌──────────┐  ┌───────────────────┐ │
│  │  UI Layer  │  │  State   │  │    Services       │ │
│  │ (pages/)   │◄─┤ (models/ │◄─┤                   │ │
│  │            │  │  notify)  │  │ p2p_service.dart  │ │
│  │ HomePage   │  │          │  │ storage_service   │ │
│  │ ChatPage   │  │ ChatState│  │                   │ │
│  │ Settings   │  │ NotifSt  │  │ WebRTC DataChannel│ │
│  │ Notifs     │  │ PairCode │  │ WebSocket Client  │ │
│  │ QR Scanner │  └──────────┘  │ SharedPreferences │ │
│  │ Info/Tutor │                └───────────────────┘ │
│  └───────────┘                                       │
└──────────────────────┬──────────────────────────────┘
                       │
          ┌────────────┴────────────┐
          │  WebSocket (信令协议)    │
          │  JSON over WS           │
          └────────────┬────────────┘
                       │
          ┌────────────┴────────────┐
          │  信令服务器 (Rust)       │
          │  justtalk-signaling     │
          │  Warp HTTP/WS           │
          │  端口 3000              │
          │  状态: HashMap<peer_id, │
          │        ConnectedPeer>   │
          └─────────────────────────┘

                  ╔══════════════╗
                  ║ P2P Channel ║  ← STUN/TURN/直连
                  ║ WebRTC DC   ║
                  ╚══════════════╝
```

## 数据流

### 连接建立 (JTC2 信令模式)

```
Peer A                         信令服务器                    Peer B
  │                               │                           │
  │── register ──────────────────►│                           │
  │                               │── peer_online ──────────► │
  │◄── registered ───────────────│                           │
  │── pair_intent ──────────────►│                           │
  │   (display_name="Alice")     │                           │
  │                               │                           │
  │ [生成 QR: JTC2:base64(...)]   │                           │
  │                               │                           │
  │                   扫码 ───────┴──→ 解码 display_name       │
  │                               │   自动创建联系人           │
  │── connect_via_pair ─────────►│                           │
  │   (target_peer=Bob)           │── pair_connect ──────────►│
  │                               │                           │
  │◄══════ sdp_offer ────────────│══════════════════════════► │
  │═══════ ice_candidate ────────│══════════════════════════► │
  │◄══════ ice_candidate ────────│══════════════════════════► │
  │═══════ sdp_answer ───────────│══════════════════════════► │
  │                               │                           │
  │◄══════════════ P2P DataChannel ═════════════════════════►│
```

### 消息发送

```
user types text
  │
  ▼
ChatPage → chatState.sendChatMessage()
  │
  ▼
P2pService.sendData(msgJSON)
  │
  ▼
RTCPeerConnection.sendDataChannel(msgJSON)
  │
  ▼
[DataChannel] ───────────────► Remote peer
                                  │
                                  ▼
                              P2pService._onDataChannelMessage()
                                  │
                                  ▼
                              ChatState: 存消息 → notifyListeners()
                                  │
                                  ▼
                              StorageService: SharedPreferences 写入
```

## 状态模型

### ChatState (核心)

```
ChatState
├── contacts: List<Contact>          # 联系人列表
│   └── Contact
│       ├── peerId: String
│       ├── displayName: String
│       └── isOnline: bool
├── messages: Map<String, List<Msg>> # peerId → 消息历史
├── currentChatPeerId: String?
├── settings
│   ├── displayName: String
│   ├── notificationsEnabled: bool
│   ├── autoConnect: bool
│   └── signalingServer: String
├── p2pService: P2pService
├── storageService: StorageService
│
├── addContact(Contact)
├── sendChatMessage(String)
├── generatePairingCode() → String
├── acceptPairingCode(String)
├── handleConnectionCode(String)     # JTC1
├── connectToSignaling()
└── (notifyListeners: ChangeNotifier)
```

### NotificationState

```
NotificationState
├── notifications: List<AppNotification>
│   └── AppNotification
│       ├── id: String
│       ├── type: NotificationType (friendRequest/systemUpdate/newMessage)
│       ├── title: String
│       ├── body: String
│       ├── time: DateTime
│       └── isRead: bool
├── unreadCount: int (getter)
├── markAllRead()
├── addNotification(AppNotification)
└── (notifyListeners: ChangeNotifier)
```

### PairingCode (JTC2)

```
PairingCode (static utilities)
├── encode(displayName, token?, sigAddr?) → String  # base64 编码
├── decode(String) → {version, token, displayName, sigAddr}
└── generateToken() → String  # 16 字节随机 token
```

## 持久化 (StorageService)

```
StorageService (SharedPreferences)
├── _saveMessages(peerId, messages)
├── _loadMessages(peerId) → List<Msg>
├── _saveContacts(contacts)
├── _loadContacts() → List<Contact>
│
├── Key 前缀:
│   ├── messages_{peerId}: JSON
│   ├── contacts: JSON
│   └── settings: JSON
```

## 页面导航

```
HomePage (联系人列表 + 通知角标)
├── Drawer
│   ├── 账户信息 (peer ID)
│   ├── 设置 → SettingsPage
│   ├── 教程 → InfoPage
│   └── 通知 → NotificationsPage
├── FAB → 添加联系人 (底部弹窗)
├── 右上角 → 通知角标 (带未读数)
├── 联系人卡片 → 点击 → ChatPage
└── 底部操作
    ├── 生成连接码 (二维码分享)
    └── 输入连接码 (扫码/粘贴)
```

## 主题体系

均在 `main.dart` 的 `JustChatApp` 类中定义:

```dart
static const Color teal      = Color(0xFF0D9488);
static const Color tealLight = Color(0xFF5EEAD4);
static const Color cream     = Color(0xFFFFF8E1);
static const Color creamDark = Color(0xFFFDE68A);
static const Color surface   = Color(0xFFF0FDFA);
```

引用方式: `JustChatApp.teal`

## 构建产物

| 命令 | 产物路径 |
|------|---------|
| `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| `flutter build windows --release` | `build/windows/runner/Release/justchat.exe` |
| `flutter build ios --release` | `build/ios/iphoneos/Runner.app` |
| `flutter build linux --release` | `build/linux/x64/release/bundle/justchat` |
