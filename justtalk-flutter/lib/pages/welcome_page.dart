import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/chat_state.dart';
import 'main_shell.dart';

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
  final TextEditingController _nameController = TextEditingController(text: '我');

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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      body: Stack(
        children: [
          // Blue orb
          AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return Positioned(
                top: size.height * 0.15 -
                    size.height * 0.15 * _orbController.value,
                left: size.width * 0.15 +
                    size.width * 0.2 * _orbController.value,
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
                top: size.height * 0.35 -
                    size.height * 0.05 * _orbController.value,
                right: size.width * 0.1 -
                    size.width * 0.05 * _orbController.value,
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
                bottom: size.height * 0.1 +
                    size.height * 0.1 * _orbController.value,
                left: size.width * 0.3 +
                    size.width * 0.05 * _orbController.value,
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
          // Brand text (below bubble)
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
                  final name = _nameController.text.trim().isEmpty
                      ? '我'
                      : _nameController.text.trim();
                  context.read<ChatState>().completeOnboarding(name);
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
