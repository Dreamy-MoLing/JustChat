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
            )
          else
            const SizedBox(width: 80),
          const Spacer(),
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
