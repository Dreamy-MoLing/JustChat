import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/notification_state.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  IconData _iconFor(NotificationType t) => switch (t) {
    NotificationType.friendRequest => Icons.person_add_rounded,
    NotificationType.systemUpdate => Icons.system_update_rounded,
    NotificationType.newMessage => Icons.chat_bubble_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          Consumer<NotificationState>(
            builder: (_, ns, __) => ns.unreadCount > 0
                ? TextButton(
                    onPressed: () => ns.markAllRead(),
                    child: const Text('全部已读',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Consumer<NotificationState>(
        builder: (context, ns, _) {
          if (ns.notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 64, color: JustChatApp.teal.withAlpha(80)),
                  const SizedBox(height: 12),
                  const Text('暂无通知', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: ns.notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final n = ns.notifications[index];
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: n.isRead
                        ? JustChatApp.cream
                        : JustChatApp.teal.withAlpha(40),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Icon(_iconFor(n.type),
                      size: 22,
                      color: n.isRead
                          ? Colors.grey
                          : JustChatApp.teal),
                ),
                title: Text(n.title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            n.isRead ? FontWeight.normal : FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(n.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(_formatTime(n.time),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey)),
                  ],
                ),
                isThreeLine: true,
                onTap: () {},
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${t.month}/${t.day}';
  }
}
