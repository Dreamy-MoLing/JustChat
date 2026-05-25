import 'package:flutter/foundation.dart';

enum NotificationType { friendRequest, systemUpdate, newMessage }

class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime time;
  bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
  });
}

class NotificationState extends ChangeNotifier {
  final List<AppNotification> _notifications = [];

  NotificationState() {
    _addSamples();
  }

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  void _addSamples() {
    _notifications.addAll([
      AppNotification(
        id: '1',
        type: NotificationType.systemUpdate,
        title: 'JustChat v0.1.0 已就绪',
        body: 'P2P 文字聊天功能可用。长按消息可复制。',
        time: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      AppNotification(
        id: '2',
        type: NotificationType.friendRequest,
        title: '好友申请',
        body: 'peer_alice 请求添加你为好友。',
        time: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
      AppNotification(
        id: '3',
        type: NotificationType.newMessage,
        title: '布洛妮娅 发来消息',
        body: '舰长，JustChat 已就绪。',
        time: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ]);
    notifyListeners();
  }

  void markAllRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void addNotification(AppNotification n) {
    _notifications.insert(0, n);
    notifyListeners();
  }
}
