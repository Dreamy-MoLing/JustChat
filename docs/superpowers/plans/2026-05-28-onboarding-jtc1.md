# 首次启动向导 + JTC1 扫码优化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户首次打开 app 有完整引导，JTC1 双向扫码两步完成配对，无需理解信令服务器。

**Architecture:** 新增 WelcomePage（首次启动向导），简化连接菜单，JTC1 扫码后自动引导应答码流程。Settings 信令服务器持久化 bug 修复。

**Tech Stack:** Flutter/Dart, Provider, existing Rust FFI engine

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/pages/welcome_page.dart` | 新建 | 首次启动 3 步向导 |
| `lib/pages/answer_qr_page.dart` | 新建 | JTC1 应答码展示页面 |
| `lib/main.dart` | 修改 | 启动时检查首次启动，决定显示向导或主页 |
| `lib/models/chat_state.dart` | 修改 | 添加 `isFirstLaunch`/`completeOnboarding()`，修复 `setSignalingServer` |
| `lib/services/engine_bridge.dart` | 修改 | 添加 `isFirstLaunch()`/`setFirstLaunchDone()` |
| `lib/pages/home_page.dart` | 修改 | 连接菜单简化，JTC1 扫码后自动弹出应答码 |

---

### Task 1: 修复 Settings 信令服务器持久化 bug

**问题:** `ChatState.setSignalingServer()` 只更新 Dart 内存，不调用 `_engine.setSignalingServerUrl()` 持久化到 Rust 引擎。

**Files:**
- Modify: `lib/models/chat_state.dart:262-264`

- [ ] **Step 1: 修复 setSignalingServer 方法**

将 `chat_state.dart` 中的:
```dart
void setSignalingServer(String url) {
  _signalingServer = url;
  notifyListeners();
}
```
改为:
```dart
void setSignalingServer(String url) {
  _signalingServer = url;
  _engine.setSignalingServerUrl(url);
  notifyListeners();
}
```

- [ ] **Step 2: 运行 analyze 验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && dart analyze
```
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add justtalk-flutter/lib/models/chat_state.dart
git commit -m "fix: persist signaling server URL to Rust engine on settings change"
```

---

### Task 2: 添加首次启动检测到 EngineBridge

**Files:**
- Modify: `lib/services/engine_bridge.dart`

- [ ] **Step 1: 添加 isFirstLaunch 和 setFirstLaunchDone 方法**

在 `EngineBridge` 类中添加（在 `setNotificationsEnabled` 方法之后）:
```dart
/// 检查是否首次启动
bool isFirstLaunch() {
  if (!_initialized) return true;
  try {
    final result = _native.call('get_settings', {'key': 'firstLaunchDone'});
    return result['data']?['value'] != 'true';
  } catch (_) {
    return true;
  }
}

/// 标记首次启动完成
void setFirstLaunchDone() {
  if (_initialized) {
    _native.call('set_settings', {'key': 'firstLaunchDone', 'value': 'true'});
  }
}
```

- [ ] **Step 2: 运行 analyze 验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && dart analyze
```
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add justtalk-flutter/lib/services/engine_bridge.dart
git commit -m "feat: add firstLaunch detection to EngineBridge"
```

---

### Task 3: 添加首次启动状态到 ChatState

**Files:**
- Modify: `lib/models/chat_state.dart`

- [ ] **Step 1: 添加 _isFirstLaunch 字段和 getter**

在 `ChatState` 类的 `_pendingAnswerCode` 字段之后添加:
```dart
bool _isFirstLaunch = true;

bool get isFirstLaunch => _isFirstLaunch;
```

- [ ] **Step 2: 在 init() 中加载首次启动状态**

在 `init()` 方法的 `_pollTimer` 之后添加:
```dart
_isFirstLaunch = _engine.isFirstLaunch();
```

- [ ] **Step 3: 添加 completeOnboarding 方法**

在 `setSignalingServer` 方法之后添加:
```dart
void completeOnboarding(String displayName) {
  _isFirstLaunch = false;
  _engine.setDisplayName(displayName);
  _engine.setFirstLaunchDone();
  notifyListeners();
}
```

- [ ] **Step 4: 运行 analyze 验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && dart analyze
```
Expected: No issues found

- [ ] **Step 5: 提交**

```bash
git add justtalk-flutter/lib/models/chat_state.dart
git commit -m "feat: add isFirstLaunch state and completeOnboarding to ChatState"
```

---

### Task 4: 创建 WelcomePage 设置向导

**Files:**
- Create: `lib/pages/welcome_page.dart`

- [ ] **Step 1: 创建 WelcomePage 文件**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/chat_state.dart';
import 'home_page.dart';

/// 首次启动设置向导（3 步）
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _pageCtrl = PageController();
  final _nameCtrl = TextEditingController(text: '我');
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  void _prevPage() {
    _pageCtrl.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _complete() {
    final name = _nameCtrl.text.trim().isEmpty ? '我' : _nameCtrl.text.trim();
    context.read<ChatState>().completeOnboarding(name);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildStep1(),
                  _buildStep2(),
                  _buildStep3(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_rounded, size: 80, color: JustChatApp.teal),
          const SizedBox(height: 24),
          Text('欢迎使用 JustChat',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('扫码即聊，无需账号',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600])),
          const SizedBox(height: 48),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '你的昵称',
              hintText: '我',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('如何连接好友？',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          _buildStepItem('1', '你展示二维码'),
          _buildStepItem('2', '对方扫码'),
          _buildStepItem('3', '对方展示应答码'),
          _buildStepItem('4', '你扫码 → 连接成功！'),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JustChatApp.teal.withAlpha(15),
              borderRadius: BorderRadius.zero,
            ),
            child: Column(
              children: [
                Row(children: [
                  Icon(Icons.people_rounded, size: 18, color: JustChatApp.teal),
                  const SizedBox(width: 8),
                  const Text('面对面时互相扫码'),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.link_rounded, size: 18, color: JustChatApp.teal),
                  const SizedBox(width: 8),
                  const Text('远程时通过微信粘贴连接码'),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: JustChatApp.teal,
              borderRadius: BorderRadius.zero,
            ),
            alignment: Alignment.center,
            child: Text(num, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 16),
          Text(text, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, size: 80, color: JustChatApp.teal),
          const SizedBox(height: 24),
          Text('你已准备就绪！',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('点击右下角 + 开始连接第一个朋友',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          if (_currentPage > 0)
            TextButton(
              onPressed: _prevPage,
              child: const Text('上一步'),
            ),
          const Spacer(),
          // 页面指示器
          Row(
            children: List.generate(3, (i) => Container(
              width: 8, height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: i == _currentPage ? JustChatApp.teal : Colors.grey[300],
                borderRadius: BorderRadius.zero,
              ),
            )),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _nextPage,
            child: Text(_currentPage < 2 ? '下一步' : '开始使用'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 运行 analyze 验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && dart analyze
```
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add justtalk-flutter/lib/pages/welcome_page.dart
git commit -m "feat: add WelcomePage setup wizard (3 steps)"
```

---

### Task 5: 修改 main.dart 支持首次启动跳转

**Files:**
- Modify: `lib/main.dart:167`

- [ ] **Step 1: 修改 MaterialApp home 属性**

将 `main.dart` 中的:
```dart
home: const HomePage(),
```
改为:
```dart
home: Consumer<ChatState>(
  builder: (context, state, _) =>
      state.isFirstLaunch ? const WelcomePage() : const HomePage(),
),
```

- [ ] **Step 2: 添加 WelcomePage import**

在 `main.dart` 顶部 imports 中添加:
```dart
import 'pages/welcome_page.dart';
```

- [ ] **Step 3: 运行 analyze 验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && dart analyze
```
Expected: No issues found

- [ ] **Step 4: 提交**

```bash
git add justtalk-flutter/lib/main.dart
git commit -m "feat: route to WelcomePage on first launch"
```

---

### Task 6: 创建 AnswerQrPage 应答码页面

**Files:**
- Create: `lib/pages/answer_qr_page.dart`

- [ ] **Step 1: 创建 AnswerQrPage 文件**

```dart
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../main.dart';

/// JTC1 应答码展示页面
///
/// 当用户扫描 JTC1 offer 后，自动生成 answer 并展示二维码。
/// 标题提示对方扫描此应答码。
class AnswerQrPage extends StatelessWidget {
  final String answerCode;
  final String peerDisplayName;

  const AnswerQrPage({
    super.key,
    required this.answerCode,
    required this.peerDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应答码'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('请让 $peerDisplayName 扫描此应答码',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('对方扫码后将自动连接',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: answerCode,
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 运行 analyze 验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && dart analyze
```
Expected: No issues found

- [ ] **Step 3: 提交**

```bash
git add justtalk-flutter/lib/pages/answer_qr_page.dart
git commit -m "feat: add AnswerQrPage for JTC1 answer code display"
```

---

### Task 7: 简化连接菜单 + JTC1 扫码自动引导

**Files:**
- Modify: `lib/pages/home_page.dart`

- [ ] **Step 1: 添加 import**

在 `home_page.dart` 顶部 imports 中添加:
```dart
import 'answer_qr_page.dart';
```

- [ ] **Step 2: 简化连接菜单**

将 `_showConnectionMenu()` 方法中的 `ListView.children` 替换为 3 个选项:

```dart
children: [
  Center(
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(100),
        borderRadius: BorderRadius.zero,
      ),
    ),
  ),
  const SizedBox(height: 16),
  const Text('连接方式',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
  const SizedBox(height: 16),
  ListTile(
    leading: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: JustChatApp.teal.withAlpha(20),
        borderRadius: BorderRadius.zero,
      ),
      child: const Icon(Icons.camera_alt_rounded, color: JustChatApp.teal),
    ),
    title: const Text('扫码连接'),
    subtitle: const Text('面对面互相扫码', style: TextStyle(fontSize: 12)),
    onTap: () {
      Navigator.pop(ctx);
      _openScanner();
    },
  ),
  ListTile(
    leading: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: JustChatApp.teal.withAlpha(20),
        borderRadius: BorderRadius.zero,
      ),
      child: const Icon(Icons.paste_rounded, color: JustChatApp.teal),
    ),
    title: const Text('粘贴连接码'),
    subtitle: const Text('远程时通过微信等粘贴', style: TextStyle(fontSize: 12)),
    onTap: () {
      Navigator.pop(ctx);
      _showPasteCodeDialog();
    },
  ),
  ListTile(
    leading: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: JustChatApp.teal.withAlpha(20),
        borderRadius: BorderRadius.zero,
      ),
      child: const Icon(Icons.person_add_rounded, color: JustChatApp.teal),
    ),
    title: const Text('手动添加联系人'),
    subtitle: const Text('输入对方 Peer ID', style: TextStyle(fontSize: 12)),
    onTap: () {
      Navigator.pop(ctx);
      _showAddContactDialog();
    },
  ),
],
```

- [ ] **Step 3: 修改 _openScanner 支持 JTC1 自动应答**

将 `_openScanner()` 方法中识别 JTC1 的分支修改为自动展示应答码。找到:
```dart
if (result.startsWith('JTC1:')) {
  state.handleConnectionCode(result);
}
```
改为:
```dart
if (result.startsWith('JTC1:')) {
  // 解码 JTC1 offer，生成应答码
  final answerCode = await state.generateJtc1Answer(result);
  if (answerCode != null && mounted) {
    // 展示应答码页面，提示用户让对方扫描
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnswerQrPage(
        answerCode: answerCode,
        peerDisplayName: '对方',
      ),
    ));
  }
}
```

- [ ] **Step 4: 在 ChatState 中添加 generateJtc1Answer 方法**

在 `chat_state.dart` 的 `handleConnectionCode` 方法之后添加:
```dart
/// 处理 JTC1 offer 并返回应答码
Future<String?> generateJtc1Answer(String code) async {
  try {
    final result = _engine.acceptConnectionCode(code);
    // 等待 ICE 收集完成，然后编码 answer
    await Future.delayed(const Duration(seconds: 2));
    final answerCode = _engine.encodeJtc1Answer();
    return answerCode;
  } catch (e) {
    _lastError = 'JTC1 应答失败: $e';
    notifyListeners();
    return null;
  }
}
```

- [ ] **Step 5: 在 EngineBridge 中添加 acceptConnectionCode 和 encodeJtc1Answer**

在 `engine_bridge.dart` 中添加:
```dart
/// 接受 JTC1 连接码（answer 侧）
String? acceptConnectionCode(String code) {
  final result = _native.call('accept_connection_code', {'code': code});
  return result['data']?['peer_id'] as String?;
}

/// 编码 JTC1 answer
String? encodeJtc1Answer() {
  final result = _native.call('encode_jtc1_answer');
  return result['data']?['code'] as String?;
}
```

- [ ] **Step 6: 运行 analyze 验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && dart analyze
```
Expected: No issues found

- [ ] **Step 7: 运行全量测试验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && flutter test
cargo test
```
Expected: All tests pass

- [ ] **Step 8: 提交**

```bash
git add justtalk-flutter/lib/
git commit -m "feat: simplify connection menu and add JTC1 auto-answer flow"
```

---

### Task 8: 全量验证

- [ ] **Step 1: Rust 测试**

```bash
cargo test
```
Expected: All pass

- [ ] **Step 2: Dart analyze**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && dart analyze
```
Expected: No issues found

- [ ] **Step 3: Flutter test**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && flutter test
```
Expected: All tests pass

- [ ] **Step 4: 构建验证**

```bash
cd /mnt/新加卷/Programing/JustTalk/justtalk-flutter && flutter build linux --debug
```
Expected: Build succeeds
