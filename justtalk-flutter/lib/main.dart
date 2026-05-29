import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'models/chat_state.dart';
import 'models/notification_state.dart';
import 'pages/circle_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/welcome_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final chatState = ChatState();
  final notifState = NotificationState();

  // 初始化 Rust 引擎
  try {
    final appDir = await getApplicationDocumentsDirectory();
    await chatState.init(appDir.path);
  } catch (e) {
    debugPrint('引擎初始化失败（将使用 fallback 模式）: $e');
  }

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
    if (code != null && (code.startsWith('JTC1:') || code.startsWith('JTC2:'))) {
      chatState.handleConnectionCode(code);
    }
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 1; // Default to 聊天 tab

  final List<Widget> _pages = const [
    CirclePage(),
    HomePage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: JustChatApp.teal.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.circle_outlined, '圈子'),
              _buildChatItem(1),
              _buildNavItem(2, Icons.menu, '个人'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 48 : 32,
              height: isSelected ? 48 : 32,
              decoration: BoxDecoration(
                color: isSelected ? JustChatApp.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(isSelected ? 16 : 8),
                boxShadow: isSelected
                    ? [BoxShadow(
                        color: JustChatApp.teal.withAlpha(76),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )]
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                size: isSelected ? 24 : 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? JustChatApp.teal : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(int index) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isSelected ? 52 : 32,
              height: isSelected ? 52 : 32,
              margin: EdgeInsets.only(top: isSelected ? 0 : 8),
              decoration: BoxDecoration(
                color: isSelected ? JustChatApp.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(isSelected ? 18 : 8),
                boxShadow: isSelected
                    ? [BoxShadow(
                        color: JustChatApp.teal.withAlpha(76),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      )]
                    : null,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                size: isSelected ? 24 : 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '聊天',
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? JustChatApp.teal : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JustChatApp extends StatelessWidget {
  const JustChatApp({super.key});

  static const Color teal = Color(0xFF0D9488);
  static const Color tealLight = Color(0xFF5EEAD4);
  static const Color cream = Color(0xFFFFF8E1);
  static const Color creamDark = Color(0xFFFDE68A);
  static const Color surfaceLight = Color(0xFFF0FDFA);

  // Analogous colors (blue→teal→green)
  static const Color blue = Color(0xFF3B82F6);
  static const Color green = Color(0xFF10B981);

  // Complementary colors (amber/warm for emphasis)
  static const Color amber = Color(0xFFF59E0B);
  static const Color warmYellow = creamDark; // alias for semantic clarity

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
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: teal.withAlpha(15),
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
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: teal.withAlpha(128)),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: Consumer<ChatState>(
        builder: (context, state, _) =>
            state.isFirstLaunch ? const WelcomePage() : const MainShell(),
      ),
    );
  }
}
