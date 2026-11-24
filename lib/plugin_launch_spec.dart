import 'dart:convert';

import 'package:path/path.dart' as p;

const pluginLaunchEnabledOrderKey = '_launchEnabledOrder';

Object? pluginLaunchDeclaration(Map<String, dynamic> manifest) {
  final appearance = manifest['appearance'];
  return appearance is Map ? appearance['launchAnimation'] : null;
}

enum PluginLaunchFrequency { everyLaunch, daily, oncePerVersion, interval }

enum PluginLaunchTheme { any, light, dark }

enum PluginLaunchFit { cover, contain }

final class PluginLaunchSpec {
  final String? asset;
  final String? script;
  final Map<String, String> images;
  final int? durationMs;
  bool get isScript => script != null;
  final PluginLaunchFrequency frequency;
  final int? intervalMinutes;
  final Set<int>? weekdays;
  final (int, int)? timeWindow;
  final PluginLaunchTheme theme;
  final PluginLaunchFit fit;

  const PluginLaunchSpec._({
    required this.asset,
    required this.script,
    required this.images,
    required this.durationMs,
    required this.frequency,
    required this.intervalMinutes,
    required this.weekdays,
    required this.timeWindow,
    required this.theme,
    required this.fit,
  });

  static const formats = {'.mp4', '.webm', '.gif', '.webp'};
  static const videoLimit = 64 * 1024 * 1024;
  static const imageLimit = 16 * 1024 * 1024;
  static const scriptCapability = 'appearance.launchAnimation.script';
  static const scriptLimit = 128 * 1024;
  static const spriteLimit = 4 * 1024 * 1024;
  static const spriteTotalLimit = 16 * 1024 * 1024;
  static const spriteFormats = {'.png', '.jpg', '.jpeg', '.webp'};
  String get extension => p.posix.extension(asset ?? '').toLowerCase();
  static bool _path(Object? value, Set<String> extensions) =>
      value is String &&
      !value.contains(RegExp(r'[\\:\x00-\x1f]')) &&
      !value
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..') &&
      extensions.contains(p.posix.extension(value).toLowerCase());

  bool get isVideo => extension == '.mp4' || extension == '.webm';
  int get byteLimit => isVideo ? videoLimit : imageLimit;

  static PluginLaunchSpec? fromManifest(Map<String, dynamic> manifest) {
    if (!manifest.containsKey('appearance')) return null;
    final appearance = manifest['appearance'];
    if (appearance is! Map ||
        appearance.isEmpty ||
        appearance.keys.any(
          (key) => key != 'launchAnimation' && key != 'interfaceTheme',
        )) {
      throw const FormatException('appearance 声明无效');
    }
    if (!appearance.containsKey('launchAnimation')) return null;
    final raw = appearance['launchAnimation'];
    if (raw is! Map ||
        raw.keys.any(
          (key) => !const {
            'asset',
            'script',
            'images',
            'durationMs',
            'frequency',
            'intervalMinutes',
            'weekdays',
            'timeWindow',
            'theme',
            'fit',
          }.contains(key),
        )) {
      throw const FormatException('launchAnimation 字段无效');
    }
    final asset = raw['asset'];
    final script = raw['script'];
    final duration = raw['durationMs'];
    final images = <String, String>{};
    if (raw.containsKey('script')) {
      final capabilities = manifest['requiredCapabilities'];
      if (raw.containsKey('asset') ||
          raw.containsKey('fit') ||
          !_path(script, const {'.js'}) ||
          duration is! int ||
          duration < 250 ||
          duration > 10000 ||
          capabilities is! List ||
          !capabilities.contains(scriptCapability)) {
        throw const FormatException(
          '脚本动画需要独立 JS、250–10000 ms 时长及脚本动画能力，不接受 asset 或 fit',
        );
      }
      if (raw.containsKey('images')) {
        final entries = raw['images'];
        if (entries is! Map || entries.length > 16) {
          throw const FormatException('脚本动画最多声明 16 个图片素材');
        }
        for (final entry in entries.entries) {
          final id = entry.key;
          if (id is! String ||
              !RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(id) ||
              !_path(entry.value, spriteFormats)) {
            throw const FormatException('脚本动画图片标识或包内路径无效');
          }
          images[id] = entry.value as String;
        }
      }
    } else if (!_path(asset, formats) ||
        raw.containsKey('images') ||
        raw.containsKey('durationMs')) {
      throw const FormatException('媒体动画需要包内 MP4/WebM/GIF/WebP asset');
    }
    T option<T extends Enum>(String key, List<T> options, T fallback) {
      if (!raw.containsKey(key)) return fallback;
      return options.where((item) => item.name == raw[key]).firstOrNull ??
          (throw FormatException('launchAnimation.$key 无效'));
    }

    final frequency = option(
      'frequency',
      PluginLaunchFrequency.values,
      PluginLaunchFrequency.daily,
    );
    final interval = raw['intervalMinutes'];
    if (frequency == PluginLaunchFrequency.interval
        ? interval is! int || interval < 1 || interval > 525600
        : raw.containsKey('intervalMinutes')) {
      throw const FormatException('仅 interval 允许且要求 intervalMinutes（1–525600）');
    }
    final days = raw['weekdays'];
    if (raw.containsKey('weekdays') &&
        (days is! List ||
            days.isEmpty ||
            days.length > 7 ||
            days.any((day) => day is! int || day < 1 || day > 7) ||
            days.toSet().length != days.length)) {
      throw const FormatException('launchAnimation.weekdays 必须为不重复的星期编号（1–7）');
    }
    final window = raw['timeWindow'];
    (int, int)? timeWindow;
    if (raw.containsKey('timeWindow')) {
      if (window is! Map ||
          window.length != 2 ||
          !window.containsKey('start') ||
          !window.containsKey('end')) {
        throw const FormatException('timeWindow 必须包含 start 和 end');
      }
      final start = _minute(window['start']);
      final end = _minute(window['end']);
      if (start == end) throw const FormatException('timeWindow 的起止时间不能相同');
      timeWindow = (start, end);
    }
    return PluginLaunchSpec._(
      asset: asset as String?,
      script: script as String?,
      images: Map.unmodifiable(images),
      durationMs: duration as int?,
      frequency: frequency,
      intervalMinutes: interval as int?,
      weekdays: days == null
          ? null
          : Set.unmodifiable((days as List).cast<int>()),
      timeWindow: timeWindow,
      theme: option('theme', PluginLaunchTheme.values, PluginLaunchTheme.any),
      fit: option('fit', PluginLaunchFit.values, PluginLaunchFit.cover),
    );
  }

  static int _minute(Object? value) {
    if (value is! String ||
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
      throw const FormatException('timeWindow 时间必须为 HH:mm');
    }
    return int.parse(value.substring(0, 2)) * 60 +
        int.parse(value.substring(3));
  }

  void validateFiles(Map<String, List<int>> files) {
    if (!isScript) return validateAsset(files[asset]);
    final code = files[script];
    if (code == null ||
        code.isEmpty ||
        code.length > scriptLimit ||
        utf8.decode(code).trim().isEmpty) {
      throw const FormatException('脚本动画需要非空 UTF-8 JS，最多 128 KiB');
    }
    var total = 0;
    for (final path in images.values) {
      final bytes = files[path];
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > spriteLimit ||
          (total += bytes.length) > spriteTotalLimit) {
        throw const FormatException('脚本动画图片不存在、为空或超出大小限制');
      }
      validateSprite(path, bytes);
    }
  }

  static void validateSprite(String path, List<int> bytes) {
    bool starts(List<int> prefix, [int offset = 0]) =>
        bytes.length >= offset + prefix.length &&
        prefix.indexed.every((e) => bytes[offset + e.$1] == e.$2);
    final valid = switch (p.posix.extension(path).toLowerCase()) {
      '.png' => starts(const [137, 80, 78, 71, 13, 10, 26, 10]),
      '.jpg' || '.jpeg' => starts(const [255, 216, 255]),
      '.webp' =>
        starts(const [82, 73, 70, 70]) && starts(const [87, 69, 66, 80], 8),
      _ => false,
    };
    if (!valid) throw const FormatException('脚本动画图片文件头与格式不符');
  }

  void validateAsset(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty || bytes.length > byteLimit) {
      throw const FormatException('启动动画素材不存在、为空或超过文件大小限制');
    }
    bool signature(int offset, List<int> prefix) =>
        bytes.length >= offset + prefix.length &&
        prefix.indexed.every((entry) => bytes[offset + entry.$1] == entry.$2);
    final valid = switch (extension) {
      '.mp4' => signature(4, const [0x66, 0x74, 0x79, 0x70]),
      '.webm' => signature(0, const [0x1a, 0x45, 0xdf, 0xa3]),
      '.gif' =>
        signature(0, const [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
            signature(0, const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
      '.webp' =>
        signature(0, const [0x52, 0x49, 0x46, 0x46]) &&
            signature(8, const [0x57, 0x45, 0x42, 0x50]),
      _ => false,
    };
    if (!valid) throw const FormatException('启动动画素材文件头与格式不符');
  }

  bool shouldPlay({
    required DateTime now,
    required bool dark,
    required DateTime? lastPlayed,
  }) {
    final local = now.toLocal();
    if ((theme == PluginLaunchTheme.light && dark) ||
        (theme == PluginLaunchTheme.dark && !dark))
      return false;
    var weekday = local.weekday;
    if (timeWindow case (final start, final end)) {
      final minute = local.hour * 60 + local.minute;
      if (start < end) {
        if (minute < start || minute >= end) return false;
      } else if (minute < start) {
        if (minute >= end) return false;
        weekday = weekday == DateTime.monday ? DateTime.sunday : weekday - 1;
      }
    }
    if (weekdays != null && !weekdays!.contains(weekday)) return false;
    if (lastPlayed == null) return true;
    final last = lastPlayed.toLocal();
    return switch (frequency) {
      PluginLaunchFrequency.everyLaunch => true,
      PluginLaunchFrequency.daily =>
        (last.year, last.month, last.day) !=
            (local.year, local.month, local.day),
      PluginLaunchFrequency.oncePerVersion => false,
      PluginLaunchFrequency.interval =>
        now.difference(lastPlayed).inMinutes >= intervalMinutes!,
    };
  }
}
