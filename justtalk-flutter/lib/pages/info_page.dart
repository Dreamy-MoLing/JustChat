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
            '设置昵称',
            '打开左上角菜单 → 设置，修改你的显示名称。\n扫码时对方会看到这个名字。',
            Icons.edit_rounded,
          ),
          _buildStep(
            context,
            '2',
            '展示二维码',
            '点击右下角 + → 「我的二维码」，打开你的专属二维码。\n让对方扫码，即可自动添加好友。',
            Icons.qr_code_rounded,
          ),
          _buildStep(
            context,
            '3',
            '扫码添加好友',
            '点击右下角 + → 「扫码连接」，扫描对方的二维码。\n好友会自动添加到联系人列表，昵称来自对方设置。',
            Icons.camera_alt_rounded,
          ),
          _buildStep(
            context,
            '4',
            '开始聊天',
            '在联系人列表中点击好友，进入聊天界面。\n双方通过 WebRTC P2P 直连，消息不经过任何服务器。',
            Icons.chat_rounded,
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
                Text('• 先在自己手机设置好昵称，再展示二维码让好友扫\n'
                    '• 扫码后好友自动添加到列表，昵称为对方设置的名字\n'
                    '• 双方连接同一信号服务器时，P2P 连接自动完成\n'
                    '• 如无信号服务器，连接建立可能需要等待几秒',
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
              borderRadius: BorderRadius.circular(10),
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
