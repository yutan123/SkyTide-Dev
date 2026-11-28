import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps the destination mounted behind an opaque scene until the final reveal.
class DailyLaunchAnimation extends StatefulWidget {
  final Widget child;
  final bool force;
  final String? lastPlayedDate;
  final Future<void> Function(String) savePlayedDate;
  const DailyLaunchAnimation({
    super.key,
    required this.child,
    required this.lastPlayedDate,
    required this.savePlayedDate,
    this.force = false,
  });

  static const lightBackground = Color(0xFFE8FAF7);
  static const darkBackground = Color(0xFF071725);

  static Color backgroundOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkBackground
      : lightBackground;

  @override
  State<DailyLaunchAnimation> createState() => _DailyLaunchAnimationState();
}

class _DailyLaunchAnimationState extends State<DailyLaunchAnimation>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late bool _visible;
  late final String _today;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _today = '${now.year}-${now.month}-${now.day}';
    _visible = widget.force || widget.lastPlayedDate != _today;
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2300),
          animationBehavior: AnimationBehavior.preserve,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _dismiss();
        });
    if (_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_visible) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          _controller.duration = const Duration(milliseconds: 220);
        }
        _controller.forward();
      });
    }
  }

  void _dismiss() {
    if (!mounted || !_visible) return;
    _controller.stop();
    setState(() => _visible = false);
    unawaited(_saveDate());
  }

  Future<void> _saveDate() async {
    try {
      await widget.savePlayedDate(_today);
    } catch (_) {
      // A failed date write should only cause the animation to play again.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _dismiss();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the same wrapper after dismissal so the home state survives.
        widget.child,
        if (_visible)
          BlockSemantics(
            child: Semantics(
              button: true,
              label: '跳过开屏动画',
              onTap: _dismiss,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _dismiss,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: Image.asset(
                    'assets/images/launch_jellyfish.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                  builder: (context, mascot) {
                    final t = _controller.value;
                    final reveal = _phase(t, reduced ? .35 : .80, 1);
                    return Opacity(
                      key: const ValueKey('builtin-launch-curtain'),
                      opacity: 1 - reveal,
                      child: RepaintBoundary(
                        child: _LaunchScene(
                          progress: reduced ? .76 : t,
                          dark: dark,
                          reduced: reduced,
                          mascot: mascot!,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LaunchScene extends StatelessWidget {
  const _LaunchScene({
    required this.progress,
    required this.dark,
    required this.reduced,
    required this.mascot,
  });

  final double progress;
  final bool dark;
  final bool reduced;
  final Widget mascot;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: DailyLaunchAnimation.backgroundOf(context),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final center = _mascotCenter(size, progress);
        final side = math.min(size.shortestSide * .43, 206.0);
        final lift = _phase(progress, .04, .54);
        final pulse = reduced
            ? 0.0
            : math.sin(lift * math.pi) * math.sin(lift * 4 * math.pi);
        final title = _phase(progress, .49, .70);
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _TidePainter(progress, dark, reduced)),
            Positioned(
              left: center.dx - side / 2,
              top: center.dy - side / 2,
              width: side,
              height: side,
              child: Opacity(
                opacity: _phase(progress, .07, .32),
                child: Transform.rotate(
                  angle: -.22 * math.sin(lift * math.pi),
                  child: Transform.scale(
                    scaleX: (.70 + .30 * lift) * (1 - .08 * pulse),
                    scaleY: (.70 + .30 * lift) * (1 + .10 * pulse),
                    child: mascot,
                  ),
                ),
              ),
            ),
            Positioned(
              top: size.height * .56 + 14 * (1 - title),
              left: 12,
              right: 12,
              child: Opacity(
                opacity: title,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'SkyTide',
                    style: TextStyle(
                      decoration: TextDecoration.none,
                      color: dark
                          ? const Color(0xFFE1FFF7)
                          : const Color(0xFF123C4C),
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

double _phase(double t, double from, double to) =>
    Curves.easeInOutCubic.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

Offset _mascotCenter(Size size, double t) {
  final lift = _phase(t, .04, .54);
  return Offset(
    size.width * (.5 - .19 * math.sin(lift * math.pi)),
    size.height * (.72 - .32 * lift),
  );
}

class _TidePainter extends CustomPainter {
  const _TidePainter(this.t, this.dark, this.reduced);

  final double t;
  final bool dark;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final tide = _phase(t, 0, .49);
    final light = dark ? const Color(0xFF77F6DD) : const Color(0xFF008880);
    final deep = dark ? const Color(0xFF0D3A53) : const Color(0xFFA5DFE2);
    final base = dark
        ? DailyLaunchAnimation.darkBackground
        : DailyLaunchAnimation.lightBackground;
    final crestY = size.height * (.95 - .50 * tide);
    final w = size.width;
    final h = size.height;

    // Two moving crests turn the blank launch surface into a lit underwater scene.
    for (var i = 0; i < 2; i++) {
      final y = crestY + (i == 0 ? 0 : h * .075);
      final bend = w * (i == 0 ? .13 : .09);
      final wave = Path()
        ..moveTo(0, y)
        ..cubicTo(w * .25, y - bend, w * .44, y + bend, w * .63, y)
        ..quadraticBezierTo(w * .84, y - bend, w, y - bend * .2)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        wave,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              light.withValues(alpha: i == 0 ? .32 : .20),
              deep.withValues(alpha: .89),
              base,
            ],
          ).createShader(rect),
      );
    }

    final center = _mascotCenter(size, t);
    final halo = _phase(t, .28, .58);
    final radius = size.shortestSide * .48;
    final glowRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            light.withValues(alpha: halo * (dark ? .25 : .17)),
            light.withValues(alpha: 0),
          ],
        ).createShader(glowRect),
    );

    // The ascent leaves bubbles; the final pulse launches expanding rings.
    final paint = Paint()..color = light;
    if (!reduced) {
      for (var i = 0; i < 18; i++) {
        final birth = .10 + i * .021;
        final age = ((t - birth) / .37).clamp(0.0, 1.0);
        if (age == 0 || age == 1) continue;
        final origin = _mascotCenter(size, birth);
        final dx = math.sin(i * 2.4 + age * 2) * w * (.045 + .11 * age);
        final point = origin + Offset(dx, (1 - age) * 40 - age * 54);
        paint.color = light.withValues(
          alpha: math.sin(age * math.pi) * (dark ? .73 : .55),
        );
        canvas.drawCircle(point, 1.2 + (i % 4) * .65, paint);
      }
    }

    for (var i = 0; i < 3; i++) {
      final start = .44 + i * .065;
      final ring = reduced ? .60 - i * .15 : _phase(t, start, start + .34);
      if (ring == 0 || ring == 1) continue;
      final width = size.shortestSide * (.24 + ring * .57);
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = light.withValues(alpha: (1 - ring) * .60);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w / 2, h * .49),
          width: width,
          height: width * .23,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TidePainter old) =>
      old.t != t || old.dark != dark || old.reduced != reduced;
}
