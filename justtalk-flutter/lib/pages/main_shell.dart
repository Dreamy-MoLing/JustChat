import 'package:flutter/material.dart';
import '../main.dart';
import 'circle_page.dart';
import 'home_page.dart';
import 'profile_page.dart';

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
              _buildNavItem(1, Icons.chat_bubble_outline, '聊天', isCenter: true),
              _buildNavItem(2, Icons.person_outline, '个人'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, {bool isCenter = false}) {
    final isSelected = _currentIndex == index;
    final size = isCenter ? 52.0 : 48.0;
    final unselectedSize = 32.0;
    final radius = isCenter ? 18.0 : 16.0;

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
              width: isSelected ? size : unselectedSize,
              height: isSelected ? size : unselectedSize,
              margin: EdgeInsets.only(top: (isCenter && !isSelected) ? 8 : 0),
              decoration: BoxDecoration(
                color: isSelected ? JustChatApp.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(isSelected ? radius : 8),
                boxShadow: isSelected
                    ? [BoxShadow(
                        color: JustChatApp.teal.withAlpha(76),
                        blurRadius: isCenter ? 16 : 12,
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
}
