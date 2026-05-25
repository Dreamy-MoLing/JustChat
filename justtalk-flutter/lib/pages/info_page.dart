import 'package:flutter/material.dart';
import '../main.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使用教程')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildStep(
            context,
            '1',
            '获取 Peer ID',
            '打开左上角抽屉菜单，查看你的本机 Peer ID。\n将此 ID 分享给想聊天的朋友。',
            Icons.fingerprint,
          ),
          _buildStep(
            context,
            '2',
            '添加联系人',
            '点击右下角 + 按钮，输入对方的 Peer ID 和显示名称。\n双方互相添加后即可开始聊天。',
            Icons.person_add_rounded,
          ),
          _buildStep(
            context,
            '3',
            '开始聊天',
            '在联系人列表中点击好友，进入聊天界面。\n输入消息后点击发送按钮或按回车键。',
            Icons.chat_rounded,
          ),
          _buildStep(
            context,
            '4',
            'P2P 连接',
            'JustChat 采用 P2P 直连技术，消息不经过服务器。\n需要双方网络支持 NAT 穿透。\n如果连接失败，系统会自动尝试 TURN 中继。',
            Icons.link_rounded,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JustChatApp.cream,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lightbulb_outline, color: JustChatApp.teal, size: 20),
                  SizedBox(width: 8),
                  Text('小提示',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: JustChatApp.teal)),
                ]),
                SizedBox(height: 8),
                Text('• 长按消息可以复制内容\n'
                    '• 联系人卡片上绿色圆点表示在线\n'
                    '• 在设置中可以修改昵称和服务器地址\n'
                    '• 信令服务器只负责协调连接，不中转聊天数据',
                    style: TextStyle(fontSize: 13, height: 1.6)),
              ],
            ),
          ),
        ],
      ),
      // ── Back to home ──
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('返回'),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, String num, String title,
      String desc, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [JustChatApp.teal, JustChatApp.tealLight]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 18, color: JustChatApp.teal),
                  const SizedBox(width: 6),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 6),
                Text(desc,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(height: 1.5, color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
