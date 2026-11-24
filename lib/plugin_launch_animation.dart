import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'plugin_launch_drawing.dart';
import 'plugin_launch_spec.dart';
import 'plugin_runtime.dart';
import 'plugin_system.dart';
import 'theme.dart';

class PluginLaunchAnimation extends StatefulWidget {
  const PluginLaunchAnimation({
    super.key,
    required this.package,
    required this.child,
  });

  final TidePluginPackage package;
  final Widget child;

  @override
  State<PluginLaunchAnimation> createState() => _PluginLaunchAnimationState();
}

class _PluginLaunchAnimationState extends State<PluginLaunchAnimation>
    with WidgetsBindingObserver {
  static const _startupBudget = Duration(milliseconds: 1500);
  static const _stallBudget = Duration(seconds: 8);
  static const _maxPixels = 3840 * 2160;

  Timer? _watchdog;
  Timer? _frameTimer;
  VideoPlayerController? _video;
  ui.Codec? _codec;
  ui.Image? _image;
  final _scriptFrames = ValueNotifier<ui.Picture?>(null);
  PluginRuntime? _scriptRuntime;
  final _sprites = <String, ui.Image>{};
  final _scriptClock = Stopwatch();
  late BoxFit _fit;
  String? _historyKey;
  SharedPreferencesAsync? _preferences;
  var _position = Duration.zero;
  var _frames = 0;
  var _visible = false;
  var _closed = false;
  bool get _active => mounted && !_closed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active) unawaited(_begin());
    });
  }

  Future<void> _begin() async {
    _arm(_startupBudget);
    try {
      if (MediaQuery.disableAnimationsOf(context)) return _finish();
      final pack = widget.package;
      final spec = PluginLaunchSpec.fromManifest(pack.manifest)!;
      final dark = TideTheme.of(context).isDark;
      _fit = spec.fit == PluginLaunchFit.cover ? BoxFit.cover : BoxFit.contain;
      if (spec.frequency != PluginLaunchFrequency.everyLaunch) {
        final version = spec.frequency == PluginLaunchFrequency.oncePerVersion
            ? pack.version
            : '';
        _historyKey =
            'plugin_launch_v1:${jsonEncode([pack.id, spec.frequency.name, version])}';
        _preferences = SharedPreferencesAsync();
      }
      final millis = _historyKey == null
          ? null
          : await _preferences!.getInt(_historyKey!);
      if (!_active) return;
      if (!spec.shouldPlay(
        now: DateTime.now(),
        dark: dark,
        lastPlayed: millis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(millis),
      ))
        return _finish();
      final root = await pack.directory.resolveSymbolicLinks();
      if (!_active) return;
      if (spec.isScript) {
        await _startScript(spec, root, pack.id);
        return;
      }
      final file = await _packageFile(root, spec.asset!, spec.byteLimit);
      if (!_active) return;
      if (spec.isVideo) {
        await _startVideo(file);
      } else {
        await _startImage(file);
      }
    } catch (_) {
      _finish();
    }
  }

  static Future<File> _packageFile(String root, String path, int limit) async {
    final resolved = await File(p.join(root, path)).resolveSymbolicLinks();
    if (!p.isWithin(root, resolved)) throw const FormatException('素材不在插件包内');
    final file = File(resolved);
    final info = await file.stat();
    if (info.type != FileSystemEntityType.file ||
        info.size < 1 ||
        info.size > limit) {
      throw const FormatException('启动动画文件为空或大小无效');
    }
    return file;
  }

  Future<void> _startScript(
    PluginLaunchSpec spec,
    String root,
    String id,
  ) async {
    final file = await _packageFile(
      root,
      spec.script!,
      PluginLaunchSpec.scriptLimit,
    );
    if (!_active) return;
    final code = await file.readAsString();
    if (!_active) return;
    final runtime = PluginRuntime(
      (method, args) async => throw UnsupportedError('启动动画不允许宿主请求'),
      pluginId: id,
      onClosed: _finish,
    );
    _scriptRuntime = runtime;
    await Future.wait<void>([
      runtime.start(pluginLaunchScriptSdk, code, const {}),
      _loadSprites(spec, root),
    ], eagerError: true);
    if (!_active) return;
    await _drawScriptFrame(runtime, spec.durationMs!);
  }

  Future<void> _loadSprites(PluginLaunchSpec spec, String root) async {
    var pixels = 0;
    var encodedBytes = 0;
    for (final entry in spec.images.entries) {
      if (!_active) return;
      final file = await _packageFile(
        root,
        entry.value,
        PluginLaunchSpec.spriteLimit,
      );
      if (!_active) return;
      final data = await file.readAsBytes();
      if (!_active) return;
      encodedBytes += data.length;
      if (data.length > PluginLaunchSpec.spriteLimit ||
          encodedBytes > PluginLaunchSpec.spriteTotalLimit) {
        throw const FormatException('脚本动画图片超出大小限制');
      }
      PluginLaunchSpec.validateSprite(entry.value, data);
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      try {
        if (!_active) return;
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (!_active) return;
          pixels += descriptor.width * descriptor.height;
          if (descriptor.width > 2048 ||
              descriptor.height > 2048 ||
              pixels > _maxPixels) {
            throw const FormatException('脚本动画图片解码尺寸超出限制');
          }
          final codec = await descriptor.instantiateCodec();
          try {
            if (!_active) return;
            if (codec.frameCount != 1)
              throw const FormatException('脚本动画素材必须是静态图片');
            final frame = await codec.getNextFrame();
            if (!_active) {
              frame.image.dispose();
              return;
            }
            _sprites[entry.key] = frame.image;
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    }
  }

  Future<void> _drawScriptFrame(PluginRuntime runtime, int durationMs) async {
    if (!_active) return;
    final timeMs = _scriptClock.elapsedMilliseconds;
    if (timeMs >= durationMs || MediaQuery.disableAnimationsOf(context))
      return _finish();
    final size = context.size;
    if (size == null || size.isEmpty || !size.isFinite) return _finish();
    try {
      final frame = await runtime
          .call('launchFrame', 'draw', {
            'width': size.width,
            'height': size.height,
            'timeMs': timeMs,
            'durationMs': durationMs,
            'progress': timeMs / durationMs,
            'dark': TideTheme.of(context).isDark,
            'images': {
              for (final entry in _sprites.entries)
                entry.key: {
                  'width': entry.value.width,
                  'height': entry.value.height,
                },
            },
          })
          .timeout(const Duration(milliseconds: 120));
      if (!_active) return;
      final picture = recordPluginLaunchFrame(frame, size, _sprites);
      if (!_visible) {
        _scriptClock.start();
        _arm(Duration(milliseconds: durationMs));
      }
      final previous = _scriptFrames.value;
      _scriptFrames.value = picture;
      previous?.dispose();
      _reveal();
      final next = (33 + timeMs - _scriptClock.elapsedMilliseconds).clamp(
        0,
        33,
      );
      _frameTimer = Timer(Duration(milliseconds: next), () {
        unawaited(_drawScriptFrame(runtime, durationMs));
      });
    } catch (_) {
      _finish();
    }
  }

  Future<void> _startVideo(File file) async {
    final controller = VideoPlayerController.file(file);
    _video = controller;
    await controller.initialize();
    if (!_active) return;
    final info = controller.value;
    if (info.duration <= Duration.zero ||
        !_validSize(info.size.width, info.size.height)) {
      return _finish();
    }
    await controller.setVolume(0);
    if (!_active) return;
    controller.addListener(_onVideoChanged);
    await controller.play();
  }

  void _onVideoChanged() {
    if (!_active) return;
    final value = _video!.value;
    if (value.hasError || value.isCompleted) return _finish();
    if (value.position > _position) {
      _position = value.position;
      _arm(_stallBudget);
      _reveal();
    }
  }

  static bool _validSize(num width, num height) =>
      width > 0 &&
      height > 0 &&
      width <= 4096 &&
      height <= 4096 &&
      width * height <= _maxPixels;

  Future<void> _startImage(File file) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
    try {
      if (!_active) return;
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (!_active) return;
        if (!_validSize(descriptor.width, descriptor.height)) return _finish();
        final codec = await descriptor.instantiateCodec();
        if (!_active || codec.frameCount < 2) {
          codec.dispose();
          return _finish();
        }
        _codec = codec;
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
    await _nextFrame();
  }

  Future<void> _nextFrame() async {
    if (!_active) return;
    final codec = _codec!;
    if (_frames >= codec.frameCount) return _finish();
    try {
      if (_visible) _arm(_stallBudget);
      final frame = await codec.getNextFrame();
      if (!_active) {
        frame.image.dispose();
        return;
      }
      _watchdog?.cancel();
      final previous = _image;
      setState(() => _image = frame.image);
      if (previous != null) previous.dispose();
      _frames++;
      _reveal();
      final duration = frame.duration < const Duration(milliseconds: 16)
          ? const Duration(milliseconds: 16)
          : frame.duration;
      _frameTimer = Timer(duration, () => unawaited(_nextFrame()));
    } catch (_) {
      _finish();
    }
  }

  void _reveal() {
    if (_visible) return;
    setState(() => _visible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_visible && _active && _historyKey != null)
        unawaited(_savePlayback());
    });
  }

  Future<void> _savePlayback() async {
    try {
      await _preferences!.setInt(
        _historyKey!,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // A storage failure does not affect this launch.
    }
  }

  void _arm(Duration timeout) {
    _watchdog?.cancel();
    _watchdog = Timer(timeout, _finish);
  }

  void _finish() {
    if (!_active) return;
    setState(() => _visible = false);
    _release();
  }

  void _release() {
    if (_closed) return;
    _closed = true;
    _scriptClock.stop();
    final runtime = _scriptRuntime;
    _scriptRuntime = null;
    runtime?.close();
    final picture = _scriptFrames.value;
    _scriptFrames.value = null;
    picture?.dispose();
    for (final image in _sprites.values) {
      image.dispose();
    }
    _sprites.clear();
    _watchdog?.cancel();
    _frameTimer?.cancel();
    final controller = _video;
    _video = null;
    if (controller != null) {
      controller.removeListener(_onVideoChanged);
      unawaited(controller.dispose().catchError((Object _) {}));
    }
    _codec?.dispose();
    _codec = null;
    _image?.dispose();
    _image = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    _scriptFrames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Listener(onPointerDown: (_) => _finish(), child: widget.child),
      if (_visible)
        Semantics(
          button: true,
          label: '跳过启动动画',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _finish,
            child: ColoredBox(
              color: Colors.black,
              child: ClipRect(
                child: _scriptRuntime != null
                    ? RepaintBoundary(
                        child: CustomPaint(
                          painter: PluginLaunchFramePainter(_scriptFrames),
                          child: const SizedBox.expand(),
                        ),
                      )
                    : _image != null
                    ? RawImage(image: _image, fit: _fit)
                    : FittedBox(
                        fit: _fit,
                        child: SizedBox.fromSize(
                          size: _video!.value.size,
                          child: VideoPlayer(_video!),
                        ),
                      ),
              ),
            ),
          ),
        ),
    ],
  );
}
