import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'models/chat_state.dart';
import 'models/notification_state.dart';
import 'pages/home_page.dart';

void main() {
  final chatState = ChatState();
  final notifState = NotificationState();

  // Auto-connect to signaling server if enabled.
  if (chatState.autoConnect) {
    chatState.connectToSignaling();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: chatState),
        ChangeNotifierProvider.value(value: notifState),
      ],
      child: const JustChatApp(),
    ),
  );

  // Listen for incoming deep links (justchat://connect).
  _initDeepLinks(chatState);
}

void _initDeepLinks(ChatState chatState) {
  final appLinks = AppLinks();

  // Handle link when app is opened from a terminated state.
  appLinks.getInitialLink().then((uri) {
    if (uri != null) _handleLink(uri, chatState);
  });

  // Handle links while app is running.
  appLinks.uriLinkStream.listen((uri) {
    _handleLink(uri, chatState);
  });
}

void _handleLink(Uri uri, ChatState chatState) {
  // Expected: justchat://connect?code=JTC1:...
  if (uri.scheme == 'justchat' && uri.host == 'connect') {
    final code = uri.queryParameters['code'];
    if (code != null && code.startsWith('JTC1:')) {
      chatState.handleConnectionCode(code);
    }
  }
}

class JustChatApp extends StatelessWidget {
  const JustChatApp({super.key});

  static const Color teal = Color(0xFF0D9488);
  static const Color tealLight = Color(0xFF5EEAD4);
  static const Color cream = Color(0xFFFFF8E1);
  static const Color creamDark = Color(0xFFFDE68A);
  static const Color surfaceLight = Color(0xFFF0FDFA);

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.notoSansTextTheme(
      Theme.of(context).textTheme,
    ).apply(
      bodyColor: const Color(0xFF1E293B),
      displayColor: const Color(0xFF0F172A),
    );

    return MaterialApp(
      title: 'JustChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          primary: teal,
          secondary: creamDark,
          surface: surfaceLight,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: surfaceLight,
        textTheme: textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.notoSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: teal.withAlpha(40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: teal.withAlpha(50)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: teal, width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: teal,
            foregroundColor: Colors.white,
            elevation: 2,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        drawerTheme: DrawerThemeData(
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}
