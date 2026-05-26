import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_state.dart';

/// Persistent storage for chat messages and contacts.
class StorageService {
  static const _keyMessages = 'chat_messages_v1';
  static const _keyContacts = 'chat_contacts_v1';
  static const _keySettings = 'chat_settings_v1';

  // ── Messages ──

  /// Load all messages grouped by peer ID.
  static Future<Map<String, List<ChatMessage>>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyMessages);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, List<ChatMessage>>{};
      for (final entry in decoded.entries) {
        final list = (entry.value as List)
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        result[entry.key] = list;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Save all messages.
  static Future<void> saveMessages(Map<String, List<ChatMessage>> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = messages.map(
      (key, list) => MapEntry(key, list.map((m) => m.toJson()).toList()),
    );
    await prefs.setString(_keyMessages, jsonEncode(encoded));
  }

  /// Append a single message and persist.
  static Future<void> appendMessage(String peerId, ChatMessage msg) async {
    final all = await loadMessages();
    all.putIfAbsent(peerId, () => []);
    // Avoid duplicates by id.
    if (all[peerId]!.any((m) => m.id == msg.id)) return;
    all[peerId]!.add(msg);
    await saveMessages(all);
  }

  // ── Contacts ──

  /// Load saved contacts.
  static Future<List<Contact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyContacts);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((c) => Contact.fromJson(c as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Save contacts.
  static Future<void> saveContacts(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyContacts,
      jsonEncode(contacts.map((c) => c.toJson()).toList()),
    );
  }

  // ── Settings ──

  /// Load settings map.
  static Future<Map<String, String>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySettings);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  /// Save settings.
  static Future<void> saveSettings(Map<String, String> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, jsonEncode(settings));
  }
}
