import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/chat_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _nameCtrl;
  late TextEditingController _serverCtrl;

  @override
  void initState() {
    super.initState();
    final state = context.read<ChatState>();
    _nameCtrl = TextEditingController(text: state.displayName);
    _serverCtrl = TextEditingController(text: state.signalingServer);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Consumer<ChatState>(
        builder: (context, state, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── 个人信息 ──
              _sectionTitle('个人信息'),
              const SizedBox(height: 12),
              _buildTextField('显示名称', _nameCtrl, (v) {
                state.setDisplayName(v);
              }),
              const SizedBox(height: 12),
              // Peer ID (read-only)
              TextField(
                enabled: false,
                controller: TextEditingController(text: state.myPeerId),
                decoration: const InputDecoration(
                  labelText: '本机 Peer ID',
                  prefixIcon: Icon(Icons.fingerprint, color: JustChatApp.teal),
                ),
              ),
              const SizedBox(height: 24),

              // ── 连接 ──
              _sectionTitle('连接'),
              const SizedBox(height: 12),
              _buildTextField('信令服务器地址', _serverCtrl, (v) {
                state.setSignalingServer(v);
              }),
              const SizedBox(height: 24),

              // ── 偏好 ──
              _sectionTitle('偏好'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('新消息通知', style: TextStyle(fontSize: 14)),
                subtitle: const Text('收到新消息时显示通知',
                    style: TextStyle(fontSize: 12)),
                value: state.notificationsEnabled,
                activeThumbColor: JustChatApp.teal,
                onChanged: (v) => state.setNotificationsEnabled(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动连接', style: TextStyle(fontSize: 14)),
                subtitle: const Text('启动时自动连接信令服务器',
                    style: TextStyle(fontSize: 12)),
                value: state.autoConnect,
                activeThumbColor: JustChatApp.teal,
                onChanged: (v) => state.setAutoConnect(v),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: JustChatApp.teal,
            letterSpacing: 1.5));
  }

  Widget _buildTextField(
      String label, TextEditingController ctrl, Function(String) onChanged) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.edit_rounded, color: JustChatApp.teal),
      ),
      onChanged: onChanged,
    );
  }
}
