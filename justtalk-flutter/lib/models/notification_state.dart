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

  NotificationState();

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

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
