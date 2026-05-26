import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/chat_state.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

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
                borderRadius: BorderRadius.circular(10),
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
      body: Column(
        children: [
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
                            borderRadius: BorderRadius.circular(24),
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
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
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
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded,
                color: JustChatApp.teal.withAlpha(150)),
            onPressed: () {},
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              gradient: LinearGradient(
                colors: [
                  JustChatApp.teal,
                  JustChatApp.tealLight.withAlpha(200),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _sendMessage,
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
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isMine ? const Radius.circular(18) : const Radius.circular(4),
            bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(18),
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
