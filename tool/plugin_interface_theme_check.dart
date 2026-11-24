import 'dart:io';

import 'package:skytide/plugin_archive.dart';
import 'package:skytide/plugin_interface_theme.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void rejects(void Function() test) {
  try {
    test();
  } on FormatException {
    return;
  }
  throw StateError('Expected invalid appearance declaration or asset');
}

PluginInterfaceTheme parse(Object? value) => PluginInterfaceTheme.fromManifest({
  'appearance': {'interfaceTheme': value},
})!;

void main(List<String> arguments) {
  final archive = PluginArchive.decode(
    File(arguments.single).readAsBytesSync(),
  );
  check(
    !archive.manifest.containsKey('entry'),
    'Appearance-only ZIP has an entry',
  );
  final sample = PluginInterfaceTheme.fromManifest(archive.manifest)!;
  sample.validateFiles(archive.files);
  check(
    sample.surface('card.bot', 'normal', false).decorations!.length == 2,
    'Sample should draw both decorations',
  );
  check(
    sample.color('primary', false) != sample.color('primary', true),
    'Sample should vary day/night palette',
  );

  const image = {'asset': 'decor/star.png', 'width': 12, 'height': 13};
  final rules = parse({
    'common': {
      'colors': {'primary': '#123456'},
      'surfaces': {
        'card': {
          'fill': '#111111',
          'strokeWidth': 1.5,
          'decorations': [image],
        },
        'card.bot': {
          'fill': '#222222',
          'liquid': {'fill': '#40223344'},
        },
      },
    },
    'dark': {
      'colors': {'primary': '#BCDEF1'},
      'surfaces': {
        'card': {'fill': '#333333', 'stroke': '#ABCDEF'},
        'card.bot': {
          'liquid': {'decorations': [], 'strokeWidth': 0},
        },
      },
    },
  });
  final normal = rules.surface('card.bot', 'normal', true);
  final liquid = rules.surface('card.bot', 'liquid', true);
  final light = rules.surface('card.bot', 'liquid', false);
  check(
    normal.fill == 0xff222222 &&
        normal.stroke == 0xffabcdef &&
        normal.strokeWidth == 1.5 &&
        normal.decorations!.single.anchor == 4,
    'Target, common/night and fallback merge',
  );
  check(
    liquid.fill == 0x40223344 &&
        liquid.strokeWidth == 0 &&
        liquid.decorations!.isEmpty &&
        light.decorations!.length == 1,
    'Only the active material branch overrides the decoration list',
  );
  check(
    rules.surface('dialog', 'normal', true).isEmpty,
    'No cross-category styles',
  );
  check(
    rules.color('primary', false) == 0xff123456 &&
        rules.color('primary', true) == 0xffbcdef1,
    'Palette merge',
  );
  for (final value in [
    {'common': null},
    {
      'light': {'colors': null},
    },
    {
      'dark': {'surfaces': null},
    },
    {
      'common': {
        'colors': {'primary': '#12345'},
      },
    },
    {
      'common': {
        'surfaces': {
          'card': {'strokeWidth': 9},
        },
      },
    },
    {
      'common': {
        'surfaces': {
          'card': {'material': 'liquid'},
        },
      },
    },
  ]) {
    rejects(() => parse(value));
  }
  for (final changes in <Map<String, Object?>>[
    {'asset': '../star.png'},
    {'anchor': null},
    {'width': 0},
    {'offsetX': 2049},
    {'opacity': 2},
  ]) {
    rejects(
      () => parse({
        'common': {
          'surfaces': {
            'card': {
              'decorations': [
                {...image, ...changes},
              ],
            },
          },
        },
      }),
    );
  }
  rejects(() => rules.validateFiles({}));
  final original = archive.files['decor/star.png']!;
  rejects(() => rules.validateFiles({'decor/star.png': List.filled(32, 0)}));
  rejects(
    () => rules.validateFiles({
      'decor/star.png': [...original]..[16] = 1,
    }),
  );
  print('Interface theme ZIP, style resolution and validation checks passed.');
}
