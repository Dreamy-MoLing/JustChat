import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/chat_state.dart';

/// 联系人列表卡片
class ContactCard extends StatelessWidget {
  final Contact contact;
  final String? lastMessage;
  final bool connected;
  final VoidCallback onTap;

  const ContactCard({
    super.key,
    required this.contact,
    this.lastMessage,
    this.connected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [JustChatApp.teal, JustChatApp.tealLight]),
                  borderRadius: BorderRadius.zero,
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(contact.initials,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                    if (contact.online || connected)
                      Positioned(
                        right: 2, bottom: 2,
                        child: Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact.displayName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                    if (lastMessage != null) ...[
                      const SizedBox(height: 2),
                      Text(lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: JustChatApp.teal.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }
}
