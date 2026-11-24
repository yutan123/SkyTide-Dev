import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:skytide/plugin_archive.dart';
import 'package:skytide/plugin_launch_spec.dart';

const mp4Header = [0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70];

Map<String, dynamic> manifest([Map<String, dynamic> overrides = const {}]) => {
  'id': 'skytide.example.launch',
  'name': 'Launch check',
  'version': '1.0.0',
  'requiredCapabilities': ['appearance.launchAnimation'],
  'appearance': {
    'launchAnimation': {'asset': 'media/intro.mp4', ...overrides},
  },
};

PluginLaunchSpec spec([Map<String, dynamic> options = const {}]) =>
    PluginLaunchSpec.fromManifest(manifest(options))!;

List<int> zip(Map<String, dynamic> input, Map<String, List<int>> files) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('manifest.json', jsonEncode(input)));
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encode(archive);
}

void check(bool result, String message) {
  if (!result) throw StateError(message);
}

void reject(void Function() work, String message) {
  try {
    work();
  } on FormatException {
    return;
  }
  throw StateError('Expected rejection: $message');
}

void checkScriptArchives() {
  const pngHeader = [137, 80, 78, 71, 13, 10, 26, 10];
  final files = <String, List<int>>{
    'launch.js': utf8.encode('function draw(frame) { return []; }'),
    'media/mark.png': pngHeader,
  };
  Map<String, dynamic> scriptManifest([
    Map<String, dynamic> fields = const {},
  ]) => {
    ...manifest(),
    'requiredCapabilities': [PluginLaunchSpec.scriptCapability],
    'appearance': {
      'launchAnimation': {
        'script': 'launch.js',
        'durationMs': 2500,
        'images': {'mark': 'media/mark.png'},
        ...fields,
      },
    },
  };
  final package = PluginArchive.decode(zip(scriptManifest(), files));
  final parsed = PluginLaunchSpec.fromManifest(package.manifest)!;
  check(
    parsed.isScript &&
        parsed.asset == null &&
        parsed.durationMs == 2500 &&
        parsed.images['mark'] == 'media/mark.png',
    'script package without entry',
  );
  PluginArchive.decode(
    zip(scriptManifest({'images': {}}), {'launch.js': files['launch.js']!}),
  );
  for (final invalid in [
    {'asset': 'a.mp4'},
    {'fit': 'contain'},
    {'script': '../launch.js'},
    {'script': 'https://example.com/launch.js'},
    {'script': 'missing.js'},
    {'durationMs': 10001},
    {
      'images': {'invalid/key': 'media/mark.png'},
    },
    {
      'images': {'mark': 'media/missing.png'},
    },
    {
      'images': {'mark': 'media/mark.gif'},
    },
  ]) {
    reject(
      () => PluginArchive.decode(zip(scriptManifest(invalid), files)),
      '$invalid',
    );
  }
  for (final replacement in <Map<String, List<int>>>[
    {
      'launch.js': [255],
    },
    {'launch.js': List.filled(PluginLaunchSpec.scriptLimit + 1, 32)},
    {
      'media/mark.png': [1, 2, 3],
    },
  ]) {
    reject(
      () => PluginArchive.decode(
        zip(scriptManifest(), {...files, ...replacement}),
      ),
      'invalid script package bytes',
    );
  }
  reject(
    () => PluginArchive.decode(
      zip(scriptManifest()..remove('requiredCapabilities'), files),
    ),
    'missing script capability',
  );
}

void main() {
  checkScriptArchives();
  final archive = PluginArchive.decode(
    zip(manifest(), {'media/intro.mp4': mp4Header}),
  );
  check(
    !archive.manifest.containsKey('entry'),
    'accept declarative ZIP without JS',
  );
  final scriptPlugin = manifest()..['entry'] = 'main.js';
  PluginArchive.decode(
    zip(scriptPlugin, {'media/intro.mp4': mp4Header, 'main.js': []}),
  );
  final oldPlugin = {...scriptPlugin}
    ..remove('appearance')
    ..remove('requiredCapabilities');
  PluginArchive.decode(zip(oldPlugin, {'main.js': []}));
  reject(() => PluginArchive.decode(zip(manifest(), {})), 'missing asset');
  reject(
    () => PluginArchive.decode(
      zip(manifest(), {
        'media/intro.mp4': [1, 2, 3],
      }),
    ),
    'wrong signature',
  );
  reject(
    () => PluginArchive.decode(
      zip(manifest()..['hooks'] = ['chat.message'], {
        'media/intro.mp4': mp4Header,
      }),
    ),
    'hooks without a script',
  );

  const formats = {
    'intro.mp4': mp4Header,
    'intro.webm': [0x1a, 0x45, 0xdf, 0xa3],
    'intro.gif': [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
    'intro.webp': [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50],
  };
  for (final entry in formats.entries) {
    spec({'asset': entry.key}).validateAsset(entry.value);
  }
  for (final invalid in [
    {'asset': '../intro.mp4'},
    {'asset': 'https://example.com/intro.mp4'},
    {'asset': 'media/../intro.mp4'},
    {'asset': 'intro.svg'},
    {'frequency': 'interval'},
    {'intervalMinutes': 10},
    {'frequency': 'interval', 'intervalMinutes': 0},
    {
      'weekdays': [1, 1],
    },
    {
      'weekdays': [0],
    },
    {
      'timeWindow': {'start': '23:00', 'end': '23:00'},
    },
    {
      'timeWindow': {'start': '24:00', 'end': '02:00'},
    },
    {'theme': 'amoled'},
    {'fit': 'stretch'},
  ]) {
    reject(() => spec(invalid), '$invalid');
  }

  final monday = DateTime(2026, 11, 23, 23);
  final tuesday = DateTime(2026, 11, 24, 1);
  final overnight = spec({
    'weekdays': [1],
    'timeWindow': {'start': '23:00', 'end': '02:00'},
    'theme': 'dark',
  });
  check(
    overnight.shouldPlay(now: monday, dark: true, lastPlayed: null),
    'inclusive start',
  );
  check(
    overnight.shouldPlay(now: tuesday, dark: true, lastPlayed: monday),
    'cross-midnight weekday and new daily date',
  );
  check(
    !overnight.shouldPlay(now: tuesday, dark: false, lastPlayed: null),
    'theme mismatch',
  );
  check(
    !overnight.shouldPlay(now: tuesday, dark: true, lastPlayed: tuesday),
    'daily already played',
  );
  check(
    !overnight.shouldPlay(
      now: DateTime(2026, 11, 24, 2),
      dark: true,
      lastPlayed: null,
    ),
    'exclusive end',
  );
  check(
    !overnight.shouldPlay(
      now: DateTime(2026, 11, 25, 1),
      dark: true,
      lastPlayed: null,
    ),
    'wrong overnight weekday',
  );
  check(
    spec({
      'frequency': 'everyLaunch',
    }).shouldPlay(now: tuesday, dark: false, lastPlayed: tuesday),
    'every launch ignores history',
  );
  check(
    !spec({
      'frequency': 'oncePerVersion',
    }).shouldPlay(now: tuesday, dark: false, lastPlayed: monday),
    'version already played',
  );
  final interval = spec({'frequency': 'interval', 'intervalMinutes': 15});
  check(
    !interval.shouldPlay(
      now: tuesday,
      dark: false,
      lastPlayed: tuesday.subtract(const Duration(minutes: 14, seconds: 59)),
    ),
    'interval pending',
  );
  check(
    interval.shouldPlay(
      now: tuesday,
      dark: false,
      lastPlayed: tuesday.subtract(const Duration(minutes: 15)),
    ),
    'interval elapsed',
  );
  print('Plugin launch archive, format and schedule checks passed');
}
