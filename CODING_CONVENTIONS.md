# JustChat 编码规范

本文件定义 JustChat 项目的编码约定，所有提交必须遵守。Claude Code 应遵循以下规则。

---

## 通用原则

1. **正确性 > 效率 > 延迟 > token 消耗**
2. 提交前必须运行 `flutter analyze`，**零警告**才能提交
3. 不要引入未使用的 import / variable / parameter
4. 功能性修改必须附带对应测试（widget / unit test）

## 命名规范

| 类别 | 规则 | 示例 |
|------|------|------|
| Dart 文件 | snake_case | `chat_state.dart`, `p2p_service.dart` |
| 类名 | PascalCase | `ChatState`, `P2pService`, `JustChatApp` |
| 方法/变量 | camelCase | `sendChatMessage()`, `_addContact()` |
| 私有成员 | `_` 前缀 | `_peerIdController`, `_addContact()` |
| 常量 | 不强制全大写 | `teal`, `cream`（`JustChatApp` 类的 static const） |
| Rust 文件 | snake_case | `main.rs`, `keypair.rs` |
| Rust 类型 | PascalCase | `ConnectedPeer`, `PeerInfo` |
| Rust 函数 | snake_case | `handle_ws()`, `send_to_peer()` |
| 枚举 | PascalCase | `NotificationType.friendRequest` |
| 路由路径 | 小写 | `/peers`, `/health` |

## Widget 规范

1. **适度深度**: Widget 树超过 5 层嵌套必须抽取独立 Widget
2. **抽取原则**: 任何可复用的 UI 块 → 独立 Widget；超过 200 行的 build 方法 → 抽取
3. **Consumer 位置**: `Consumer<ChatState>` 放在需要响应变化的最小 Widget 上，不要包裹整棵树
4. **const 构造器**: 所有 Widget 尽可能声明 `const` 构造器
5. **BuildContext 安全**: 异步回调中检查 `context.mounted`（Flutter 3.7+）

## Flutter 特有

```dart
// ✅ 正确: Provider 模式
final chatState = context.read<ChatState>();
final messages = context.watch<ChatState>().getMessages(peerId);

// ❌ 错误: 不要在 build 方法内重复 read 不变的数据
// ❌ 错误: 用 GlobalKey 代替参数传递
```

### 状态管理规则

- `ChatState` 和 `NotificationState` 是全局单例（通过 `MultiProvider` 注入）
- 只在这两个模型中使用 `ChangeNotifier`
- 新建状态类必须先问：能否复用 `ChatState`？
- 数据修改后必须调 `notifyListeners()`

### Google Fonts

字体引用必须走 `GoogleFonts.notoSansTextTheme()`，不硬编码字体文件路径。

```dart
// ✅
final textTheme = GoogleFonts.notoSansTextTheme(
  Theme.of(context).textTheme,
).apply(...);

// ❌ 不要使用自定义的 .ttf 文件
```

## Rust 特有

1. 优先使用 `anyhow::Result` 而非自定义错误类型
2. `match` 必须覆盖所有分支
3. 用 `tracing` crate 做日志（`tracing::info!`, `tracing::warn!`）
4. 信令消息体使用 `serde_json::Value` 做动态字段（非强类型 struct）

## Git 提交

1. **提交信息格式**: `type: short description`，类型: `feat` / `fix` / `refactor` / `docs` / `ci` / `chore`
2. **不要提交** 到 main 分支（使用 feature 分支 + PR）
3. **每次提交前** 运行 `flutter analyze` 和 `flutter test`
4. 推送 tag `v*.*.*` 触发 CI/CD 自动构建

## 安全规则

1. 任何 API key / token / 密码 不得硬编码在代码中
2. 使用 GitHub Secrets 存储敏感信息
3. WebSocket 消息体大小上限 64KB（信令服务器端已校验）
4. peer_id 长度限制 128 字符

## 注释规范

- **中文注释**，英文变量/函数名
- 复杂逻辑必须加注释说明意图
- 注释不是翻译代码："// 增加 i" → ❌；"// 循环重试直到连接成功" → ✅
- 公共 API 写文档注释（`///`）
