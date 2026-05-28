import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:justchat/main.dart';
import 'package:justchat/models/chat_state.dart';
import 'package:justchat/models/notification_state.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    // 设置手机端宽度 (< 600)，避免触发桌面分栏模式
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatState()),
          ChangeNotifierProvider(create: (_) => NotificationState()),
        ],
        child: const JustChatApp(),
      ),
    );
    // 首次启动显示 WelcomePage
    expect(find.text('欢迎使用 JustChat'), findsOneWidget);
  });
}
