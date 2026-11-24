import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

const pluginLaunchScriptSdk = r'''
(() => {
  'use strict';
  const send = globalThis.sendMessage;
  const stringify = JSON.stringify;
  const parse = JSON.parse;
  const isArray = Array.isArray;
  let drawing = false;
  Object.defineProperty(globalThis, 'sendMessage', {value: undefined, writable: false, configurable: false});
  Object.defineProperty(globalThis, '__tideDispatch', {value(id, kind, name, input) {
    if (drawing) return;
    drawing = true;
    try {
      if (kind !== 'launchFrame' || typeof draw !== 'function') throw new Error();
      const frame = draw(parse(input));
      if (!isArray(frame) || frame.length > 256) throw new Error();
      const value = stringify(frame);
      if (typeof value !== 'string' || value.length > 65536) throw new Error();
      send('tide.result', stringify({__proto__: null, id, value}));
    } catch (_) {
      send('tide.result', stringify({__proto__: null, id, error: 'Invalid launch animation frame'}));
    } finally {
      drawing = false;
    }
  }});
})();
''';

final class PluginLaunchFramePainter extends CustomPainter {
  PluginLaunchFramePainter(this.frames) : super(repaint: frames);

  final ValueListenable<ui.Picture?> frames;

  @override
  void paint(Canvas canvas, Size size) {
    final picture = frames.value;
    if (picture != null) canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(PluginLaunchFramePainter oldDelegate) =>
      oldDelegate.frames != frames;
}

Never _invalid() => throw const FormatException('启动动画绘图指令无效');

double _number(Object? value, {double min = -32768, double max = 32768}) {
  if (value is! num || !value.isFinite || value < min || value > max) {
    _invalid();
  }
  return value.toDouble();
}

Color _color(Object? value) {
  if (value is! int || value < 0 || value > 0xffffffff) _invalid();
  return Color(value);
}

Offset _point(List command, int i) =>
    Offset(_number(command[i]), _number(command[i + 1]));

Rect _rect(List command, int i) => Rect.fromLTWH(
  _number(command[i]),
  _number(command[i + 1]),
  _number(command[i + 2], min: 0),
  _number(command[i + 3], min: 0),
);

Paint _paint(Object? color, [Object? stroke]) {
  final paint = Paint()..color = _color(color);
  if (stroke != null) {
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = _number(stroke, min: 0, max: 512)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }
  return paint;
}

Path _path(Object? value) {
  if (value is! List || value.isEmpty || value.length > 128) _invalid();
  final path = Path();
  for (final segment in value) {
    switch (segment) {
      case ['M', final x, final y]:
        path.moveTo(_number(x), _number(y));
      case ['L', final x, final y]:
        path.lineTo(_number(x), _number(y));
      case ['Q', final cx, final cy, final x, final y]:
        path.quadraticBezierTo(
          _number(cx),
          _number(cy),
          _number(x),
          _number(y),
        );
      case ['C', final ax, final ay, final bx, final by, final x, final y]:
        path.cubicTo(
          _number(ax),
          _number(ay),
          _number(bx),
          _number(by),
          _number(x),
          _number(y),
        );
      case ['Z']:
        path.close();
      default:
        _invalid();
    }
  }
  return path;
}

ui.Picture recordPluginLaunchFrame(
  Object? encoded,
  Size size,
  Map<String, ui.Image> images,
) {
  if (encoded is! String || encoded.length > 65536) _invalid();
  // Check nesting before decoding arbitrary script output on the UI isolate.
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (final unit in encoded.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        quoted = false;
      }
    } else if (unit == 34) {
      quoted = true;
    } else if (unit == 91 || unit == 123) {
      if (++depth > 4) _invalid();
    } else if (unit == 93 || unit == 125) {
      if (--depth < 0) _invalid();
    }
  }
  final decoded = jsonDecode(encoded);
  if (decoded is! List || decoded.length > 256) _invalid();
  final bounds = Offset.zero & size;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds)..clipRect(bounds);
  try {
    for (final command in decoded) {
      if (command is! List) _invalid();
      switch (command) {
        case ['clear', final color]:
          canvas.drawColor(_color(color), BlendMode.src);
        case ['rect', _, _, _, _, final color]:
          canvas.drawRect(_rect(command, 1), _paint(color));
        case ['circle', _, _, final radius, final color]:
          canvas.drawCircle(
            _point(command, 1),
            _number(radius, min: 0),
            _paint(color),
          );
        case ['ring', _, _, final radius, final color, final stroke]:
          if (stroke == null) _invalid();
          canvas.drawCircle(
            _point(command, 1),
            _number(radius, min: 0),
            _paint(color, stroke),
          );
        case ['line', _, _, _, _, final color, final stroke]:
          if (stroke == null) _invalid();
          canvas.drawLine(
            _point(command, 1),
            _point(command, 3),
            _paint(color, stroke),
          );
        case ['path', final segments, final color, final stroke]:
          canvas.drawPath(_path(segments), _paint(color, stroke));
        case ['linear', _, _, _, _, final from, final to]:
          canvas.drawRect(
            bounds,
            Paint()
              ..shader = ui.Gradient.linear(
                _point(command, 1),
                _point(command, 3),
                [_color(from), _color(to)],
              ),
          );
        case ['glow', _, _, final radius, final color, final edge]:
          final center = _point(command, 1);
          final r = _number(radius, min: .01);
          canvas.drawCircle(
            center,
            r,
            Paint()
              ..shader = ui.Gradient.radial(center, r, [
                _color(color),
                _color(edge),
              ]),
          );
        case ['image', String id, _, _, _, _, final opacity, final radians]:
          final image = images[id];
          if (image == null) _invalid();
          final dest = _rect(command, 2);
          final rotation = _number(radians, min: -1000, max: 1000);
          final alpha = _number(opacity, min: 0, max: 1);
          final center = dest.center;
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.rotate(rotation);
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            dest.shift(-center),
            Paint()
              ..filterQuality = FilterQuality.low
              ..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255),
          );
          canvas.restore();
        default:
          _invalid();
      }
    }
    return recorder.endRecording();
  } catch (_) {
    recorder.endRecording().dispose();
    rethrow;
  }
}
