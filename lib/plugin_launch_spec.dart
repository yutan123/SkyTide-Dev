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
  final String asset;
  final PluginLaunchFrequency frequency;
  final int? intervalMinutes;
  final Set<int>? weekdays;
  final (int, int)? timeWindow;
  final PluginLaunchTheme theme;
  final PluginLaunchFit fit;

  const PluginLaunchSpec._({
    required this.asset,
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
  String get extension => p.posix.extension(asset).toLowerCase();
  bool get isVideo => extension == '.mp4' || extension == '.webm';
  int get byteLimit => isVideo ? videoLimit : imageLimit;

  static PluginLaunchSpec? fromManifest(Map<String, dynamic> manifest) {
    if (!manifest.containsKey('appearance')) return null;
    final appearance = manifest['appearance'];
    if (appearance is! Map ||
        appearance.length != 1 ||
        !appearance.containsKey('launchAnimation')) {
      throw const FormatException('appearance 仅支持 launchAnimation');
    }
    final raw = appearance['launchAnimation'];
    if (raw is! Map ||
        raw.keys.any(
          (key) => !const {
            'asset',
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
    if (asset is! String ||
        asset.contains(RegExp(r'[\\:\x00-\x1f]')) ||
        asset
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..') ||
        !formats.contains(p.posix.extension(asset).toLowerCase())) {
      throw const FormatException(
        'launchAnimation.asset 必须是包内 MP4/WebM/GIF/WebP 路径',
      );
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
      asset: asset,
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
