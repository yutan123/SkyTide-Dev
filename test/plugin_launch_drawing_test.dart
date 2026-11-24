import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skytide/plugin_launch_drawing.dart';

void main() {
  const size = Size(180, 320);
  test('records valid geometry, paths and gradients', () {
    final encoded = jsonEncode([
      ['clear', 0xff101820],
      ['linear', 0, 0, 0, 320, 0xff101820, 0xff406090],
      ['rect', 1, 2, 3, 4, 0x88ffffff],
      ['glow', 90, 160, 80, 0xaa00ffff, 0x0000ffff],
      ['circle', 90, 160, 10, 0xccffffff],
      ['ring', 90, 160, 35, 0xccffffff, 1.5],
      ['line', 10, 20, 40, 50, 0xff000000, 1],
      [
        'path',
        [
          ['M', 0, 0],
          ['L', 100, 100],
          ['Q', 40, 40, 30, 30],
          ['C', 20, 40, 60, 80, 100, 120],
          ['Z'],
        ],
        0xffff00ff,
        null,
      ],
    ]);
    recordPluginLaunchFrame(encoded, size, {}).dispose();
  });

  test('rejects malformed, unbounded and undeclared drawing input', () {
    for (final frame in [
      '[[[[[0]]]]]',
      '[["circle",1,2,3,-1]]',
      '[["circle",1,2,-3,0]]',
      '[["circle",1,2,1e309,0]]',
      '[["line",1,2,3,4,0,null]]',
      '[["image","unknown",0,0,1,1,1,0]]',
      '[["unknown"]]',
      jsonEncode(List.filled(257, ['clear', 0])),
      jsonEncode(List.filled(65536, 0)),
    ]) {
      expect(
        () => recordPluginLaunchFrame(frame, size, {}),
        throwsFormatException,
      );
    }
  });
}
