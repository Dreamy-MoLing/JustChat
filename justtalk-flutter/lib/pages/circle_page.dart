import 'package:flutter/material.dart';
import '../main.dart';

class CirclePage extends StatelessWidget {
  const CirclePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('圈子')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: JustChatApp.teal.withAlpha(80)),
            const SizedBox(height: 16),
            Text(
              '圈子功能即将上线',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: JustChatApp.teal.withAlpha(150),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
