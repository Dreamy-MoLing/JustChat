# UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize JustTalk UI from brutalist-square to rounded-corner style with analogous color scheme, welcome animation, and bottom navigation.

**Architecture:** Update theme in `main.dart` first (global border radius + new colors), then restructure navigation (bottom nav replacing drawer), then update each page. New pages: `CirclePage`, `ProfilePage`. Existing pages get border radius + color updates.

**Tech Stack:** Flutter 3.41+, Dart 3.9+, Material 3, Provider

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `lib/main.dart` | Theme: add colors, update border radius, remove drawer |
| Rewrite | `lib/pages/welcome_page.dart` | Animation + onboarding steps |
| Modify | `lib/pages/home_page.dart` | Remove drawer, adapt for bottom nav |
| Create | `lib/pages/circle_page.dart` | Empty shell for 圈子 tab |
| Create | `lib/pages/profile_page.dart` | Profile + settings entry points |
| Modify | `lib/pages/chat_page.dart` | Border radius + bubble style |
| Modify | `lib/pages/settings_page.dart` | Border radius |
| Modify | `lib/pages/notifications_page.dart` | Border radius + complementary color |
| Modify | `lib/pages/info_page.dart` | Border radius |
| Modify | `lib/pages/qr_scanner_page.dart` | Border radius |
| Modify | `lib/pages/answer_qr_page.dart` | Border radius |
| Modify | `lib/pages/widgets/contact_card.dart` | Border radius |
| Modify | `lib/pages/widgets/qr_countdown.dart` | No changes needed |

---

### Task 1: Update Theme Constants in main.dart

**Files:**
- Modify: `lib/main.dart:68-174`

- [ ] **Step 1: Add new color constants to JustChatApp**

Add after line 75 (`surfaceLight`):

```dart
// Analogous colors (blue→teal→green)
static const Color blue = Color(0xFF3B82F6);
static const Color green = Color(0xFF10B981);

// Complementary colors (amber/warm for emphasis)
static const Color amber = Color(0xFFF59E0B);
static const Color warmYellow = Color(0xFFFDE68A);
```

- [ ] **Step 2: Update all theme border radii**

Replace every `BorderRadius.zero` in the theme with appropriate rounded values:

Line 111 (appBarTheme shape):
```dart
shape: const RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
),
```

Line 119 (cardTheme shape):
```dart
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
```

Line 128 (FAB shape):
```dart
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
```

Lines 137, 141, 145 (inputDecoration borders):
```dart
border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x800D9488))),
```

Line 157 (elevatedButton shape):
```dart
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
```

Line 164 (drawerTheme shape — will be unused after bottom nav, but update for consistency):
```dart
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
```

- [ ] **Step 3: Update cardTheme shadowColor**

```dart
shadowColor: JustChatApp.teal.withAlpha(15),
```

- [ ] **Step 4: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add justtalk-flutter/lib/main.dart
git commit -m "feat: update theme with rounded corners and analogous color constants"
```

---

### Task 2: Create Bottom Navigation Bar Shell

**Files:**
- Create: `lib/pages/circle_page.dart`
- Create: `lib/pages/profile_page.dart`
- Modify: `lib/main.dart:168-174`

- [ ] **Step 1: Create CirclePage (empty shell)**

```dart
// lib/pages/circle_page.dart
import 'package:flutter/material.dart';
import '../main.dart';

class CirclePage extends StatelessWidget {
  const CirclePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('圈子')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: JustChatApp.teal.withAlpha(80)),
            const SizedBox(height: 16),
            Text(
              '圈子功能即将上线',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: JustChatApp.teal.withAlpha(150),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create ProfilePage**

```dart
// lib/pages/profile_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/chat_state.dart';
import 'info_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();

    return Scaffold(
      appBar: AppBar(title: const Text('个人')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [JustChatApp.teal, JustChatApp.tealLight],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        chatState.displayName.isNotEmpty
                            ? chatState.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chatState.displayName.isEmpty ? '未设置昵称' : chatState.displayName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID: ${chatState.peerId.length > 12 ? chatState.peerId.substring(0, 12) : chatState.peerId}...',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Settings list
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined, color: JustChatApp.teal),
                  title: const Text('通知设置'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationsPage()),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.dns_outlined, color: JustChatApp.teal),
                  title: const Text('信令服务器'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.help_outline, color: JustChatApp.teal),
                  title: const Text('使用帮助'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InfoPage()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Create MainShell with bottom navigation**

Replace the `main.dart` entry point widget. Change the `home:` property in `JustChatApp`'s `build` method (lines 168-174) to use a new `MainShell` widget:

Add new stateful widget class before `JustChatApp`:

```dart
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 1; // Default to 聊天 tab

  final List<Widget> _pages = const [
    CirclePage(),
    HomePage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: JustChatApp.teal.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.circle_outlined, '圈子'),
              _buildChatItem(1),
              _buildNavItem(2, Icons.menu, '个人'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 48 : 32,
              height: isSelected ? 48 : 32,
              decoration: BoxDecoration(
                color: isSelected ? JustChatApp.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(isSelected ? 16 : 8),
                boxShadow: isSelected
                    ? [BoxShadow(
                        color: JustChatApp.teal.withAlpha(76),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )]
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                size: isSelected ? 24 : 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? JustChatApp.teal : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(int index) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 52 : 32,
              height: isSelected ? 52 : 32,
              margin: EdgeInsets.only(top: isSelected ? 0 : 8),
              decoration: BoxDecoration(
                color: isSelected ? JustChatApp.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(isSelected ? 18 : 8),
                boxShadow: isSelected
                    ? [BoxShadow(
                        color: JustChatApp.teal.withAlpha(76),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      )]
                    : null,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                size: isSelected ? 24 : 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '聊天',
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? JustChatApp.teal : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Update main.dart entry point**

Change lines 168-174 from:
```dart
home: Consumer<ChatState>(
  builder: (context, state, _) {
    if (state.isFirstLaunch) return const WelcomePage();
    return const HomePage();
  },
),
```
To:
```dart
home: Consumer<ChatState>(
  builder: (context, state, _) {
    if (state.isFirstLaunch) return const WelcomePage();
    return const MainShell();
  },
),
```

Add imports at top of main.dart:
```dart
import 'pages/circle_page.dart';
import 'pages/profile_page.dart';
```

- [ ] **Step 5: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add justtalk-flutter/lib/main.dart justtalk-flutter/lib/pages/circle_page.dart justtalk-flutter/lib/pages/profile_page.dart
git commit -m "feat: add bottom navigation bar with circle, chat, and profile tabs"
```

---

### Task 3: Remove Drawer from HomePage

**Files:**
- Modify: `lib/pages/home_page.dart`

- [ ] **Step 1: Remove drawer from Scaffold**

In the `build()` method (lines 654-717), remove the `drawer:` property from the Scaffold. Also remove the `_buildDrawer()` method (lines 550-638) and `_sectionHeader()` method (lines 640-648).

- [ ] **Step 2: Remove AppBar actions that moved to ProfilePage**

Remove the settings/info popup menu items from the AppBar actions (if they exist as actions). The AppBar should only keep the notification bell icon.

- [ ] **Step 3: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add justtalk-flutter/lib/pages/home_page.dart
git commit -m "refactor: remove drawer from HomePage, navigation moved to bottom nav"
```

---

### Task 4: Update HomePage Border Radius

**Files:**
- Modify: `lib/pages/home_page.dart`

- [ ] **Step 1: Replace all BorderRadius.zero with rounded values**

13 occurrences to update:

- Line 54 (bottom sheet shape): `BorderRadius.vertical(top: Radius.circular(24))`
- Line 174 (AlertDialog shape): `BorderRadius.circular(20)`
- Line 193 (Card shape): `BorderRadius.circular(16)`
- Line 214 (Card shape): `BorderRadius.circular(16)`
- Line 400 (AlertDialog shape): `BorderRadius.circular(20)`
- Line 419 (Card shape): `BorderRadius.circular(16)`
- Line 573 (drawer icon container): `BorderRadius.circular(12)` (will be removed with drawer)
- Line 875 (dismiss background): `BorderRadius.circular(16)`
- Line 904 (bottom sheet shape): `BorderRadius.vertical(top: Radius.circular(24))`
- Line 919 (drag handle): `BorderRadius.circular(4)`
- Line 933 (icon container): `BorderRadius.circular(14)`
- Line 949 (icon container): `BorderRadius.circular(14)`
- Line 965 (icon container): `BorderRadius.circular(14)`

- [ ] **Step 2: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add justtalk-flutter/lib/pages/home_page.dart
git commit -m "feat: update HomePage border radius to rounded corners"
```

---

### Task 5: Rewrite WelcomePage with Animation

**Files:**
- Rewrite: `lib/pages/welcome_page.dart`

- [ ] **Step 1: Write the new WelcomePage**

Replace the entire file content. The new WelcomePage has two phases:
1. **Animation phase**: Three color orbs converge → single-color teal bubble → "JustChat" text below
2. **Onboarding phase**: Step cards with complementary color accents

```dart
import 'package:flutter/material.dart';
import '../main.dart';
import 'home_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> with TickerProviderStateMixin {
  bool _showAnimation = true;
  bool _showBubble = false;
  bool _showBrand = false;
  bool _showSteps = false;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final TextEditingController _nameController = TextEditingController();

  late AnimationController _orbController;
  late AnimationController _bubbleController;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _startAnimation();
  }

  void _startAnimation() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _orbController.forward();
    await Future.delayed(const Duration(milliseconds: 1600));
    setState(() => _showBubble = true);
    _bubbleController.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _showBrand = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    setState(() {
      _showAnimation = false;
      _showSteps = true;
    });
  }

  @override
  void dispose() {
    _orbController.dispose();
    _bubbleController.dispose();
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showAnimation) return _buildAnimation();
    if (_showSteps) return _buildSteps();
    return const SizedBox.shrink();
  }

  Widget _buildAnimation() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      body: Stack(
        children: [
          // Blue orb
          AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return Positioned(
                top: MediaQuery.of(context).size.height * 0.15 -
                    MediaQuery.of(context).size.height * 0.15 * _orbController.value,
                left: MediaQuery.of(context).size.width * 0.15 +
                    MediaQuery.of(context).size.width * 0.2 * _orbController.value,
                child: Opacity(
                  opacity: _showBubble ? 0.0 : 0.9,
                  child: Container(
                    width: 200 + 20 * _orbController.value,
                    height: 200 + 20 * _orbController.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          JustChatApp.blue.withAlpha(180),
                          JustChatApp.blue.withAlpha(0),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Teal orb
          AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return Positioned(
                top: MediaQuery.of(context).size.height * 0.35 -
                    MediaQuery.of(context).size.height * 0.05 * _orbController.value,
                right: MediaQuery.of(context).size.width * 0.1 -
                    MediaQuery.of(context).size.width * 0.05 * _orbController.value,
                child: Opacity(
                  opacity: _showBubble ? 0.0 : 0.9,
                  child: Container(
                    width: 220 + 20 * _orbController.value,
                    height: 220 + 20 * _orbController.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          JustChatApp.teal.withAlpha(180),
                          JustChatApp.teal.withAlpha(0),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Green orb
          AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return Positioned(
                bottom: MediaQuery.of(context).size.height * 0.1 +
                    MediaQuery.of(context).size.height * 0.1 * _orbController.value,
                left: MediaQuery.of(context).size.width * 0.3 +
                    MediaQuery.of(context).size.width * 0.05 * _orbController.value,
                child: Opacity(
                  opacity: _showBubble ? 0.0 : 0.9,
                  child: Container(
                    width: 180 + 20 * _orbController.value,
                    height: 180 + 20 * _orbController.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          JustChatApp.green.withAlpha(180),
                          JustChatApp.green.withAlpha(0),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Bubble icon (center, above brand text)
          if (_showBubble)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _bubbleController,
                    curve: Curves.elasticOut,
                  ),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: JustChatApp.teal,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: JustChatApp.teal.withAlpha(128),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
          // Brand text (below bubble, z-index on top)
          if (_showBrand)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'JustChat',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '扫码即连，无需账号',
                        style: TextStyle(
                          fontSize: 14,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSteps() {
    return Scaffold(
      backgroundColor: JustChatApp.surfaceLight,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Bubble icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: JustChatApp.teal,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: JustChatApp.teal.withAlpha(76),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              '欢迎使用 JustChat',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '三步开始，轻松聊天',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            // Steps
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _buildStep1(),
                  _buildStep2(),
                  _buildStep3(),
                ],
              ),
            ),
            // Page indicator + button
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_outline, size: 64, color: JustChatApp.teal),
          const SizedBox(height: 24),
          Text(
            '设置昵称',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            '让朋友认出你',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '你的昵称',
              hintText: '输入一个好记的名字',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 64, color: JustChatApp.teal),
          const SizedBox(height: 24),
          Text(
            '扫描二维码',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            '对准朋友的屏幕',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          _buildStepItem('1', '点击右下角 + 按钮', JustChatApp.teal),
          _buildStepItem('2', '选择"扫描二维码"', JustChatApp.blue),
          _buildStepItem('3', '对准朋友的二维码', JustChatApp.green),
        ],
      ),
    );
  }

  Widget _buildStepItem(String number, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_outlined, size: 64, color: JustChatApp.green),
          const SizedBox(height: 24),
          Text(
            '开始聊天',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            'P2P 直连，安全无忧',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Page indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == i ? JustChatApp.teal : Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          // Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_currentPage < 2) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  // Save name and complete
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const MainShell()),
                  );
                }
              },
              child: Text(_currentPage < 2 ? '下一步' : '开始使用'),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add justtalk-flutter/lib/pages/welcome_page.dart
git commit -m "feat: rewrite WelcomePage with three-color orb animation and onboarding steps"
```

---

### Task 6: Update ContactCard Border Radius

**Files:**
- Modify: `lib/pages/widgets/contact_card.dart`

- [ ] **Step 1: Replace BorderRadius.zero**

Line 24 (InkWell): `BorderRadius.circular(16)`
Line 35 (avatar container): `BorderRadius.circular(14)`

- [ ] **Step 2: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add justtalk-flutter/lib/pages/widgets/contact_card.dart
git commit -m "feat: update ContactCard with rounded corners"
```

---

### Task 7: Update ChatPage Border Radius

**Files:**
- Modify: `lib/pages/chat_page.dart`

- [ ] **Step 1: Replace BorderRadius.circular(0) and Radius.circular(0)**

- Line 79 (empty container): `BorderRadius.circular(16)`
- Line 132 (AppBar avatar): `BorderRadius.circular(14)`
- Line 319 (embedded header avatar): `BorderRadius.circular(14)`
- Line 417 (send button): `BorderRadius.circular(14)`
- Lines 458-461 (message bubble): Update to asymmetric:
  ```dart
  borderRadius: BorderRadius.only(
    topLeft: const Radius.circular(16),
    topRight: const Radius.circular(16),
    bottomLeft: isMine ? const Radius.circular(16) : const Radius.circular(4),
    bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(16),
  ),
  ```

- [ ] **Step 2: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```

- [ ] **Step 3: Commit**

```bash
git add justtalk-flutter/lib/pages/chat_page.dart
git commit -m "feat: update ChatPage with rounded corners and asymmetric bubble radius"
```

---

### Task 8: Update Remaining Pages Border Radius

**Files:**
- Modify: `lib/pages/notifications_page.dart`
- Modify: `lib/pages/info_page.dart`
- Modify: `lib/pages/qr_scanner_page.dart`
- Modify: `lib/pages/answer_qr_page.dart`

- [ ] **Step 1: Update notifications_page.dart**

Line 61: `BorderRadius.circular(12)` for notification icon container

- [ ] **Step 2: Update info_page.dart**

Line 47: `BorderRadius.circular(16)` for tips container
Line 98: `BorderRadius.circular(10)` for step number badge

- [ ] **Step 3: Update qr_scanner_page.dart**

Line 59: `BorderRadius.circular(16)` for scan overlay guide

- [ ] **Step 4: Update answer_qr_page.dart**

Add `BorderRadius.circular(16)` to the QR code container (currently has no border radius)

- [ ] **Step 5: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```

- [ ] **Step 6: Commit**

```bash
git add justtalk-flutter/lib/pages/notifications_page.dart justtalk-flutter/lib/pages/info_page.dart justtalk-flutter/lib/pages/qr_scanner_page.dart justtalk-flutter/lib/pages/answer_qr_page.dart
git commit -m "feat: update remaining pages with rounded corners"
```

---

### Task 9: Run All Tests and Final Verification

**Files:**
- Test: all modified files

- [ ] **Step 1: Run flutter analyze**

```bash
cd justtalk-flutter && flutter analyze
```
Expected: No errors, no warnings

- [ ] **Step 2: Run all tests**

```bash
cd justtalk-flutter && flutter test
```
Expected: All tests pass

- [ ] **Step 3: Run the app and verify visually**

```bash
cd justtalk-flutter && flutter run -d linux
```
Verify:
- Welcome animation plays on first launch
- Bottom navigation works (3 tabs)
- Default tab is 聊天
- Selected tab protrudes with teal background
- All pages have rounded corners
- Chat bubbles have asymmetric radius

- [ ] **Step 4: Commit any fixes**

```bash
git add -A && git commit -m "fix: UI redesign verification fixes"
```
