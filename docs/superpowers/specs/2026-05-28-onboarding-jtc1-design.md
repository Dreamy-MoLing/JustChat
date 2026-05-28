# 首次启动向导 + JTC1 扫码优化 设计文档

## 目标

用户拿到 app 后无需理解"信令服务器"等技术概念，通过设置向导了解连接方式，通过 JTC1 双向扫码两步完成配对。

## 背景

- 信令服务器需要公网部署，开发者无法提供，用户自建过于繁琐
- JTC1 协议已实现（SDP+ICE 打包在二维码中），但 UI 把它藏在降级位置
- 当前无首次启动引导，用户不知道如何开始
- Settings 页面修改信令服务器地址不会持久化（Dart→Rust 桥接断裂）

## 范围

1. 首次启动设置向导（3 步）
2. JTC1 双向扫码流程优化（自动引导）
3. Settings 信令服务器持久化 bug 修复

---

## 一、设置向导

### 触发条件

首次启动时，检查 `settings.json` 中 `firstLaunchDone` 字段。不存在或为 `false` 时显示向导。完成后写入 `firstLaunchDone: true`。

### 页面结构

**第 1 步：欢迎 + 昵称**

```
┌─────────────────────────────┐
│                             │
│     JustChat                │
│     扫码即聊，无需账号       │
│                             │
│     [输入昵称]  默认: "我"   │
│                             │
│         [下一步 →]          │
└─────────────────────────────┘
```

- 标题: "欢迎使用 JustChat"
- 副标题: "扫码即聊，无需账号"
- 输入框: 昵称（placeholder "我"）
- 按钮: "下一步"

**第 2 步：连接方式介绍**

```
┌─────────────────────────────┐
│                             │
│     如何连接好友？           │
│                             │
│  ┌───────────────────────┐  │
│  │ ① 你展示二维码         │  │
│  │ ② 对方扫码             │  │
│  │ ③ 对方展示应答码       │  │
│  │ ④ 你扫码               │  │
│  │ → 连接成功！            │  │
│  └───────────────────────┘  │
│                             │
│  面对面时互相扫码            │
│  远程时通过微信粘贴连接码    │
│                             │
│     [← 上一步] [开始使用 →] │
└─────────────────────────────┘
```

- 标题: "如何连接好友？"
- 4 步图示说明 JTC1 双向扫码流程
- 补充说明: "面对面扫码 / 远程粘贴码"
- 按钮: "上一步" + "开始使用"

**第 3 步：完成**

直接跳转主界面。向导完成，写入 `firstLaunchDone: true`。

### 文件变更

| 文件 | 操作 |
|------|------|
| `lib/pages/welcome_page.dart` | 新建 — 设置向导页面 |
| `lib/main.dart` | 修改 — 启动时检查 `firstLaunchDone`，决定显示向导还是主页 |
| `lib/models/chat_state.dart` | 修改 — 添加 `isFirstLaunch` / `completeOnboarding()` |
| `lib/services/engine_bridge.dart` | 修改 — 添加 `isFirstLaunch()` / `setFirstLaunchDone()` |

---

## 二、JTC1 双向扫码流程优化

### 当前问题

用户需要：选"扫码连接" → 扫码 → 回到主页 → 选"粘贴连接码" → 粘贴应答码。步骤多，用户不理解"应答码"概念。

### 优化后流程

```
用户 A                          用户 B
  │                               │
  ├─ 点击 "连接"                  │
  ├─ 展示 QR（含 offer SDP+ICE）  │
  │    底部提示: "对方扫码后       │
  │    会显示应答码"               │
  │                               ├─ 扫码
  │                               ├─ 自动识别 JTC1 offer
  │                               ├─ 生成应答码，展示 QR
  │                               │    标题: "请让对方扫描此应答码"
  ├─ 收到 connect_req 通知        │
  ├─ 自动弹出扫码框               │
  ├─ 扫描 B 的应答码              │
  │                               │
  ├─ 连接建立 ✓                   ├─ 连接建立 ✓
  ├─ 跳转聊天页                   ├─ 跳转聊天页
```

### 关键改动

**1. 扫码后自动展示应答码（用户 B 侧）**

当前 `handleConnectionCode()` 检测到 JTC1 offer 后调用 `accept_connection_code()`，但 UI 没有后续引导。改为：

- 扫码识别 JTC1 offer → 调用 `accept_connection_code()` → 自动弹出"应答码"页面展示 answer QR
- 页面标题: "请让对方扫描此应答码"
- 底部提示: "对方扫码后将自动连接"

**2. 展示 offer QR 后引导扫码 answer（用户 A 侧）**

当前 `_showMyQrCode()` 展示 QR 后设置 `onPairedFromQr` 回调，但只处理 JTC2。改为：

- 展示 offer QR 的对话框底部增加文字提示："对方扫码后会显示应答码，请再扫描对方的应答码"
- 当 B 扫码触发 `connect` 命令后，信令服务器通知 A（已有 `connect_req` 消息）
- A 收到 `connect_req` 后，自动弹出扫码框，标题显示"扫描对方的应答码"
- A 扫描 B 的 answer QR → 连接建立 → 双方跳转聊天页

**3. 连接菜单简化**

当前连接菜单有 5 个选项。简化为：

```
┌─────────────────────┐
│     连接方式         │
│                     │
│  📱 扫码连接         │  ← 主入口，展示 offer QR
│  📋 粘贴连接码       │  ← 远程场景
│  ➕ 手动添加联系人    │  ← 仅输入 peer ID
└─────────────────────┘
```

- 移除"我的二维码"（合并到"扫码连接"中）
- 移除"分享连接码"（合并到"粘贴连接码"中）

### 文件变更

| 文件 | 操作 |
|------|------|
| `lib/pages/home_page.dart` | 修改 — 连接菜单简化、扫码后自动弹出应答码 |
| `lib/pages/answer_qr_page.dart` | 新建 — 应答码展示页面 |
| `lib/models/chat_state.dart` | 修改 — JTC1 answer 自动处理逻辑 |
| `lib/services/engine_bridge.dart` | 修改 — 监听 JTC1 answer 事件 |

---

## 三、Settings 信令服务器持久化修复

### 当前 bug

`SettingsPage` 调用 `state.setSignalingServer(v)` 只更新 Dart 内存变量，不调用 `_engine.setSignalingServerUrl(url)` 持久化到 Rust 引擎。

### 修复

`ChatState.setSignalingServer()` 中增加 `_engine.setSignalingServerUrl(url)` 调用。

### 文件变更

| 文件 | 操作 |
|------|------|
| `lib/models/chat_state.dart` | 修改 — `setSignalingServer()` 调用 EngineBridge 持久化 |

---

## 测试计划

| 测试 | 验证内容 |
|------|---------|
| 首次启动显示向导 | 无 `firstLaunchDone` 时显示 WelcomePage |
| 向导完成后不再显示 | 写入 `firstLaunchDone: true` 后直接进主页 |
| 昵称设置生效 | 向导中设置的昵称在主页显示 |
| JTC1 offer 展示 | 点击"扫码连接"展示含 SDP+ICE 的 QR |
| JTC1 answer 自动弹出 | 扫码 JTC1 offer 后自动展示应答码页面 |
| 信令服务器持久化 | 设置页修改地址后重启 app，地址保持 |
| flutter analyze | 零警告 |
| cargo test | 全部通过 |
