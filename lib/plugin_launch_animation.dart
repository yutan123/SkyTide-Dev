import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'plugin_launch_spec.dart';
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
      final resolved = await File(
        p.join(root, spec.asset),
      ).resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) return _finish();
      final file = File(resolved);
      final stat = await file.stat();
      if (!_active) return;
      if (stat.type != FileSystemEntityType.file ||
          stat.size < 1 ||
          stat.size > spec.byteLimit) {
        return _finish();
      }
      if (spec.isVideo) {
        await _startVideo(file);
      } else {
        await _startImage(file);
      }
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
    _closed = true;
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
                child: _image != null
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
