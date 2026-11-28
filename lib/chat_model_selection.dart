/// SQLite owns the primary selection; preferences hold the optional backup.
List<String> configuredChatProviderIds(
  Map<String, Object?> bot,
  String? backupId,
) {
  final primary = bot['chat_model']?.toString().trim() ?? '';
  final backup = backupId?.trim() ?? '';
  return [
    if (primary.isNotEmpty) primary,
    if (backup.isNotEmpty && backup != primary) backup,
  ];
}
