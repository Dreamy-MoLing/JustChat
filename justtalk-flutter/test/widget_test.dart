import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:justchat/main.dart';
import 'package:justchat/models/chat_state.dart';
import 'package:justchat/models/notification_state.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatState()),
          ChangeNotifierProvider(create: (_) => NotificationState()),
        ],
        child: const JustChatApp(),
      ),
    );
    expect(find.text('JustChat'), findsOneWidget);
  });
}
