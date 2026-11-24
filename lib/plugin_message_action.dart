import 'dart:convert';

import 'chat_content.dart';

final class PluginMessageAction {
  const PluginMessageAction(this.id, this.label);

  final String id;
  final String label;

  static const maxInputBytes = 64 * 1024;
  static const maxResultLength = 8192;
  static final _id = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

  static List<PluginMessageAction> parse(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.length > 16) {
      throw const FormatException('messageActions 最多声明 16 项');
    }
    final ids = <String>{};
    return [for (final item in value) _parseItem(item, ids)];
  }

  static PluginMessageAction _parseItem(Object? item, Set<String> ids) {
    if (item is Map && item.length == 2) {
      final id = item['id'];
      final label = item['label'];
      if (id is String &&
          _id.hasMatch(id) &&
          ids.add(id) &&
          label is String &&
          label.trim() == label &&
          label.isNotEmpty &&
          label.runes.length <= 40 &&
          !label.runes.any(
            (r) =>
                r < 32 || (r >= 127 && r <= 159) || r == 0x2028 || r == 0x2029,
          )) {
        return PluginMessageAction(id, label);
      }
    }
    throw const FormatException('messageActions 的 id 或 label 无效，或 id 重复');
  }

  static Map<String, String>? payload(Map<String, dynamic> message) {
    final id = message['id'];
    final role = message['role'];
    final content = message['content'];
    final type = message['type'];
    if (id == null ||
        (role != 'user' && role != 'assistant') ||
        (type != null && type != 'text') ||
        content is! String ||
        content.length > maxInputBytes ||
        utf8.encode(content).length > maxInputBytes)
      return null;
    final text = role == 'assistant' ? cleanChatContent(content) : content;
    if (text.trim().isEmpty) return null;
    return {'id': id.toString(), 'role': role as String, 'text': text};
  }
}
