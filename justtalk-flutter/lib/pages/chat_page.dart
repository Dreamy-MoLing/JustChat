import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/chat_state.dart';
import '../services/p2p_service.dart';

class ChatPage extends StatefulWidget {
  final bool embedded;
  const ChatPage({super.key, this.embedded = false});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final state = context.read<ChatState>();
    final contactId = state.activeContactId;
    state.sendChatMessage(contactId, text);
    _messageController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChatState>();
    final contactId = state.activeContactId;
    final contact = state.getContact(contactId);
    final messages = state.getMessages(contactId);
    final isConnected = state.isPeerConnected(contactId);

    if (contactId.isEmpty) {
      return const Center(
        child: Text('选择一个联系人开始聊天', style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }

    final chatBody = Column(
      children: [
        _buildConnectionBar(context, contactId, isConnected),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: JustChatApp.cream.withAlpha(150),
                          borderRadius: BorderRadius.circular(0),
                        ),
                        child: Icon(Icons.chat_rounded,
                            size: 48, color: JustChatApp.teal.withAlpha(100)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '开始聊天吧',
                        style: TextStyle(
                          color: JustChatApp.teal.withAlpha(120),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _MessageBubble(message: msg);
                  },
                ),
        ),
        _buildInputBar(isConnected),
      ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          _buildEmbeddedHeader(contact!, isConnected),
          const Divider(height: 1),
          Expanded(child: chatBody),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                borderRadius: BorderRadius.circular(0),
              ),
              child: Center(
                child: Text(
                  contact?.initials ?? '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact?.displayName ?? '未知用户',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  isConnected ? '在线' : '离线',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withAlpha(180),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, size: 20),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: chatBody,
    );
  }

  Widget _buildConnectionBar(BuildContext context, String peerId, bool isConnected) {
    final state = context.watch<ChatState>();
    final phase = state.getPeerPhase(peerId);
    final sigConnected = state.signalingConnected;
    final sigConnecting = state.signalingConnecting;

    // 根据 ConnectionPhase 决定 UI
    Color barColor;
    IconData icon;
    String statusText;
    Widget? leading;
    Widget? action;

    switch (phase) {
      case ConnectionPhase.connected:
        barColor = const Color(0xFFDCFCE7);
        icon = Icons.link_rounded;
        statusText = 'P2P 已连接 — WebRTC DataChannel';
      case ConnectionPhase.connecting:
        barColor = const Color(0xFFFEF9C3);
        icon = Icons.sync_rounded;
        statusText = '正在创建对等连接...';
        leading = SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber.shade700),
        );
      case ConnectionPhase.iceGathering:
        barColor = const Color(0xFFFEF9C3);
        icon = Icons.sync_rounded;
        statusText = '正在收集 ICE 候选 (NAT 穿透)...';
        leading = SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber.shade700),
        );
      case ConnectionPhase.exchanging:
        barColor = const Color(0xFFFEF9C3);
        icon = Icons.swap_horiz_rounded;
        statusText = '正在交换 SDP (信令协商)...';
        leading = SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber.shade700),
        );
      case ConnectionPhase.failed:
        barColor = const Color(0xFFFEF2F2);
        icon = Icons.error_outline_rounded;
        statusText = '连接失败 — 请检查网络后重试';
        action = SizedBox(
          height: 28,
          child: TextButton(
            onPressed: () => context.read<ChatState>().connectToPeer(peerId),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              foregroundColor: JustChatApp.teal,
            ),
            child: const Text('重试', style: TextStyle(fontSize: 12)),
          ),
        );
      case ConnectionPhase.idle:
        if (sigConnecting) {
          barColor = const Color(0xFFFEF9C3);
          icon = Icons.cloud_sync_rounded;
          statusText = '正在连接信令服务器...';
          leading = SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber.shade700),
          );
        } else if (sigConnected) {
          barColor = const Color(0xFFE0F2FE);
          icon = Icons.cloud_done_rounded;
          statusText = '信令已连接 — 点击连接建立 P2P';
          action = SizedBox(
            height: 28,
            child: TextButton(
              onPressed: () => context.read<ChatState>().connectToPeer(peerId),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: JustChatApp.teal,
              ),
              child: const Text('连接', style: TextStyle(fontSize: 12)),
            ),
          );
        } else {
          barColor = const Color(0xFFFEF2F2);
          icon = Icons.cloud_off_rounded;
          statusText = '信令未连接 — 请先连接信令服务器';
          action = SizedBox(
            height: 28,
            child: TextButton(
              onPressed: () {
                final st = context.read<ChatState>();
                st.connectToSignaling().then((_) => st.connectToPeer(peerId));
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: JustChatApp.teal,
              ),
              child: const Text('全部连接', style: TextStyle(fontSize: 12)),
            ),
          );
        }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: barColor,
      child: Row(
        children: [
          leading ?? Icon(icon, size: 16,
              color: phase == ConnectionPhase.connected ? const Color(0xFF16A34A)
                  : phase == ConnectionPhase.failed ? const Color(0xFFDC2626)
                  : sigConnected ? const Color(0xFF0284C7)
                  : const Color(0xFFDC2626)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                color: phase == ConnectionPhase.connected ? const Color(0xFF16A34A)
                    : phase == ConnectionPhase.failed ? const Color(0xFFDC2626)
                    : phase == ConnectionPhase.idle && !sigConnected ? const Color(0xFFDC2626)
                    : Colors.amber.shade800,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _buildEmbeddedHeader(Contact contact, bool isConnected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [JustChatApp.teal, JustChatApp.tealLight]),
              borderRadius: BorderRadius.circular(0),
            ),
            child: Center(
              child: Text(contact.initials,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.displayName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: isConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(isConnected ? '在线' : '离线',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ),
          if (!isConnected)
            TextButton(
              onPressed: () {
                final state = context.read<ChatState>();
                state.connectToPeer(contact.peerId);
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: JustChatApp.teal,
              ),
              child: const Text('连接', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isConnected) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 12, top: 8,
        bottom: bottomPad + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: JustChatApp.teal.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: isConnected,
              decoration: InputDecoration(
                hintText: isConnected ? '输入消息...' : '未连接，无法发送',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              maxLines: 5,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            decoration: BoxDecoration(
              gradient: isConnected
                  ? LinearGradient(
                      colors: [
                        JustChatApp.teal,
                        JustChatApp.tealLight.withAlpha(200),
                      ],
                    )
                  : LinearGradient(
                      colors: [
                        Colors.grey.shade400,
                        Colors.grey.shade300,
                      ],
                    ),
              borderRadius: BorderRadius.circular(0),
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: isConnected ? _sendMessage : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final time = '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMine
              ? const LinearGradient(
                  colors: [JustChatApp.teal, Color(0xFF0FAAA0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isMine ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(0),
            topRight: const Radius.circular(0),
            bottomLeft: isMine ? const Radius.circular(0) : const Radius.circular(0),
            bottomRight: isMine ? const Radius.circular(0) : const Radius.circular(0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isMine ? Colors.white : const Color(0xFF1E293B),
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 11,
                color: isMine
                    ? Colors.white.withAlpha(180)
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
