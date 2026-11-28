import 'dart:convert';

/// Validation shared by plugin media downloads and message delivery.
class PluginMediaContract {
  static const permissions = {
    'storage',
    'workers',
    'database',
    'ai',
    'files',
    'media.process',
    'network',
    'network.sockets',
    'network.cleartext',
    'network.local',
    'auth.browser',
    'credentials',
    'background.send',
    'background.generate',
    'context.inject',
    'platform.editor',

    'chat.send',
    'chat.read',
    'tasks',
    'notifications',
    'media.download',
  };
  static const limits = {
    'image': 32 * 1024 * 1024,
    'video': 256 * 1024 * 1024,
    'audio': 64 * 1024 * 1024,
    'document': 64 * 1024 * 1024,
    'file': 256 * 1024 * 1024,
  };

  static bool validOrigin(Object? value) {
    if (value == '*') return true;
    if (value is! String) return false;
    final normalized = value.startsWith('https://*.')
        ? value.replaceFirst('https://*.', 'https://')
        : value;
    final parsed = Uri.tryParse(normalized);
    return parsed != null &&
        parsed.scheme == 'https' &&
        parsed.host.isNotEmpty &&
        !parsed.host.contains('*') &&
        parsed.userInfo.isEmpty &&
        parsed.origin == normalized;
  }

  static bool allows(Uri uri, List origins) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty)
      return false;
    return origins.any((origin) {
      if (!validOrigin(origin)) return false;
      if (origin == '*' || origin == uri.origin) return true;
      if (origin is String && origin.startsWith('https://*.')) {
        final base = Uri.parse(origin.replaceFirst('https://*.', 'https://'));
        return uri.port == base.port &&
            uri.host.endsWith('.${base.host}') &&
            uri.host != base.host;
      }
      return false;
    });
  }

  static Map<String, String> headers(Object? value) {
    if (value == null) return {};
    if (value is! Map) throw const FormatException('headers 必须为字符串映射');
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          !RegExp(
            r"^[!#$%&'*+.^_`|~0-9a-zA-Z-]+$",
          ).hasMatch(entry.key as String) ||
          (entry.value as String).contains(RegExp(r'[\r\n\x00]'))) {
        throw const FormatException('请求头名称或值无效');
      }
      result[(entry.key as String).toLowerCase()] = entry.value as String;
    }
    return result;
  }

  static Uri uri(Object? value, List origins) {
    if (value is! String) throw const FormatException('url 必须为 HTTPS 地址');
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !allows(uri, origins)) {
      throw const FormatException('媒体地址未获得 networkOrigins 授权');
    }
    return uri;
  }

  static String text(
    Object? value,
    String field,
    int max, {
    bool required = false,
  }) {
    if (value == null && !required) return '';
    if (value is! String ||
        value.length > max ||
        (required && value.trim().isEmpty)) {
      throw FormatException('$field 必须为${required ? "非空" : ""}字符串，最多 $max 字符');
    }
    return value;
  }

  /// A display name is never allowed to escape the message's own directory.
  static String fileName(Object? value, {String fallback = 'attachment.bin'}) {
    final name = text(value ?? fallback, 'fileName', 180, required: true);
    if (name == '.' ||
        name == '..' ||
        name.trim() != name ||
        utf8.encode(name).length > 240 ||
        name.contains(RegExp(r'[\\/\\\\\x00-\x1f\x7f]'))) {
      throw const FormatException('fileName 必须为不含路径和控制字符的文件名');
    }
    return name;
  }

  /// Inspect signatures, rather than trusting extensions or Content-Type.
  static String extension(List<int> bytes, String kind) {
    bool at(int offset, List<int> magic) =>
        bytes.length >= offset + magic.length &&
        List.generate(
          magic.length,
          (i) => bytes[offset + i] == magic[i],
        ).every((v) => v);
    bool word(int offset, String s) => at(offset, ascii.encode(s));
    if (kind == 'file') return 'bin';
    if (kind == 'document' && word(0, '%PDF-')) return 'pdf';
    if (kind == 'image') {
      if (at(0, [137, 80, 78, 71, 13, 10, 26, 10])) return 'png';
      if (at(0, [255, 216, 255])) return 'jpg';
      if (word(0, 'GIF87a') || word(0, 'GIF89a')) return 'gif';
      if (word(0, 'RIFF') && word(8, 'WEBP')) return 'webp';
    } else if (kind == 'video') {
      if (word(4, 'ftyp')) return 'mp4';
      if (at(0, [26, 69, 223, 163])) return 'webm';
    } else if (kind == 'audio') {
      if (word(0, 'RIFF') && word(8, 'WAVE')) return 'wav';
      if (word(0, 'OggS')) return 'ogg';
      if (word(0, 'fLaC')) return 'flac';
      if (word(0, '#!AMR')) return 'amr';
      if (word(4, 'ftyp')) return 'm4a';
      if (word(0, 'ID3')) return 'mp3';
      if (bytes.length > 1 && bytes[0] == 255 && (bytes[1] & 246) == 240)
        return 'aac';
      if (bytes.length > 1 && bytes[0] == 255 && (bytes[1] & 224) == 224)
        return 'mp3';
    }
    throw const FormatException('媒体内容与类型不匹配或格式不支持');
  }
}
