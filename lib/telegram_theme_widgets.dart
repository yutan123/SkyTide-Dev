import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'tide_appearance_surface.dart';
import 'tide_popover.dart';

const telegramGreen = Color(0xFF12B86A);

/// Frosted surfaces sample the actual content beneath them.
class TelegramGlass extends StatelessWidget {
  const TelegramGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.fillOpacity,
    this.appearanceTarget,
  });
  final Widget child;
  final double radius;
  final double? fillOpacity;
  final String? appearanceTarget;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final target = appearanceTarget;
    final borderRadius = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                (target == null
                    ? null
                    : tideAppearanceFill(context, target, 'frosted')) ??
                theme.surface.withValues(
                  alpha: fillOpacity ?? (theme.isDark ? .78 : .83),
                ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: theme.isDark ? .08 : .65),
              width: .6,
            ),
          ),
          child: target == null
              ? child
              : tideAppearanceSurface(
                  context,
                  target,
                  child,
                  material: 'frosted',
                  radius: borderRadius,
                  paintFill: false,
                ),
        ),
      ),
    );
  }
}

/// Uses the same anchor geometry as SkyTide popovers, including reverse travel.
Future<T?> showTelegramMenu<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool preferAbove = false,
  double width = 196,
  Duration duration = const Duration(milliseconds: 440),
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final trigger = context.findRenderObject()! as RenderBox;
  final anchor =
      trigger.localToGlobal(Offset.zero, ancestor: overlay) & trigger.size;
  final route = RawDialogRoute<T>(
    requestFocus: false,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: .12),
    transitionDuration: duration,
    transitionBuilder: (_, animation, secondary, child) => child,
    pageBuilder: (ctx, animation, secondary) => AnimatedBuilder(
      animation: animation,
      child: TelegramGlass(
        radius: 26,
        appearanceTarget: 'dialog.popover',
        fillOpacity: TideTheme.of(context).isDark ? .72 : .64,
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Builder(builder: builder),
          ),
        ),
      ),
      builder: (ctx, child) {
        final media = MediaQuery.of(ctx);
        final t = Curves.easeOutCubic.transform(animation.value);
        return CustomSingleChildLayout(
          delegate: TidePopoverLayout(
            anchor: anchor,
            insets: EdgeInsets.fromLTRB(
              12,
              media.padding.top + 8,
              12,
              math.max(media.padding.bottom, media.viewInsets.bottom) + 12,
            ),
            width: width,
            preferAbove: preferAbove,
            progress: t,
          ),
          child: Opacity(
            opacity: (animation.value * 5).clamp(0, 1),
            child: Transform.scale(
              scale: .08 + .92 * t,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    ),
  );
  final result = await navigator.push<T>(route);
  await route.completed;
  return result;
}

/// Local spring motion keeps the title and back button stationary.
class TelegramChatMenuIsland extends StatefulWidget {
  const TelegramChatMenuIsland({super.key, required this.onPressed});
  final Future<void> Function(BuildContext, VoidCallback) onPressed;
  @override
  State<TelegramChatMenuIsland> createState() => _TelegramChatMenuIslandState();
}

class _TelegramChatMenuIslandState extends State<TelegramChatMenuIsland>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _open = false;
  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    if (_open) return;
    _open = true;
    _spring.forward(from: 0);
    try {
      await widget.onPressed(context, () {
        if (mounted) _spring.forward(from: 0);
      });
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return AnimatedBuilder(
      animation: _spring,
      child: TelegramGlass(
        fillOpacity: theme.isDark ? .48 : .52,
        child: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            tooltip: '聊天菜单',
            onPressed: _press,
            icon: Icon(Icons.more_vert, color: theme.textStrong),
          ),
        ),
      ),
      builder: (context, child) {
        final t = _spring.value;
        final wave = math.sin(t * math.pi * 4) * math.exp(-t * 4) * (1 - t);
        return Transform.translate(
          offset: Offset(0, -6 * wave),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(
              1 - .09 * wave,
              1 + .12 * wave,
              1,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class TelegramMenuItem extends StatelessWidget {
  const TelegramMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFD64C4C)
        : TideTheme.of(context).textStrong;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Flexible(
              child: Text(label, style: TextStyle(fontSize: 14, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class TelegramNavigationBar extends StatelessWidget {
  const TelegramNavigationBar({
    super.key,
    required this.index,
    required this.unread,
    required this.onTap,
  });
  final int index;
  final int unread;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return TelegramGlass(
      radius: 32,
      fillOpacity: theme.isDark ? .72 : .76,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: List.generate(4, (i) {
            final selected = i == index;
            final color = selected ? telegramGreen : theme.textStrong;
            final icon = [
              selected ? Icons.forum_rounded : Icons.forum_outlined,
              selected ? Icons.people_rounded : Icons.people_outline_rounded,
              selected ? Icons.explore_rounded : Icons.explore_outlined,
              selected
                  ? Icons.account_circle_rounded
                  : Icons.account_circle_outlined,
            ][i];
            return Expanded(
              child: Semantics(
                selected: selected,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => onTap(i),
                  child: SizedBox(
                    height: 50,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: selected ? 1.0 : 0.0),
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            builder: (_, value, child) => Center(
                              child: FractionallySizedBox(
                                widthFactor: value,
                                heightFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: telegramGreen.withValues(
                                      alpha: .10 * value,
                                    ),
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Badge(
                              isLabelVisible: i == 0 && unread > 0,
                              backgroundColor: telegramGreen,
                              label: Text(unread > 99 ? '99+' : '$unread'),
                              child: Icon(icon, color: color, size: 23),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ['聊天', '空间', '动态', '我'][i],
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class TelegramBubble extends StatelessWidget {
  final bool showTail;
  const TelegramBubble({
    super.key,
    required this.isUser,
    required this.child,
    this.showTail = true,
    this.joinsPrevious = false,
  });
  final bool isUser;
  final bool joinsPrevious;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final color =
        theme.appearanceColor(isUser ? 'bubbleUser' : 'bubbleAi') ??
        (isUser
            ? (theme.isDark ? const Color(0xFF315B45) : const Color(0xFFE2F6CD))
            : theme.surface);
    return CustomPaint(
      painter: _TelegramBubblePainter(color, isUser, showTail, joinsPrevious),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
        child: child,
      ),
    );
  }
}

class _TelegramBubblePainter extends CustomPainter {
  const _TelegramBubblePainter(
    this.color,
    this.isUser,
    this.showTail,
    this.joinsPrevious,
  );
  final bool joinsPrevious;
  final bool showTail;
  final Color color;
  final bool isUser;
  @override
  void paint(Canvas canvas, Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Offset.zero & size,
          topLeft: Radius.circular(!isUser && joinsPrevious ? 5 : 19),
          topRight: Radius.circular(isUser && joinsPrevious ? 5 : 19),
          bottomLeft: Radius.circular(isUser ? 19 : 5),
          bottomRight: Radius.circular(isUser ? 5 : 19),
        ),
      );
    final x = isUser ? size.width : 0.0;
    final d = isUser ? 1.0 : -1.0;
    final tail = Path()
      ..moveTo(x - d * 8, size.height - 14)
      ..quadraticBezierTo(x, size.height - 1, x + d * 5, size.height)
      ..lineTo(x - d * 9, size.height)
      ..close();
    final path = showTail
        ? Path.combine(PathOperation.union, body, tail)
        : body;
    canvas.drawShadow(path, Colors.black.withValues(alpha: .12), 1, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TelegramBubblePainter old) =>
      old.color != color ||
      old.isUser != isUser ||
      old.showTail != showTail ||
      old.joinsPrevious != joinsPrevious;
}

/// Decorative fallback wallpaper; user backgrounds continue to take precedence.
class TelegramWallpaper extends StatelessWidget {
  const TelegramWallpaper({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: TideTheme.of(context).isDark
            ? const [Color(0xFF263E32), Color(0xFF1C3438)]
            : const [Color(0xFFDAE5A1), Color(0xFFA7D6AF)],
      ),
    ),
    child: CustomPaint(
      painter: _WallpaperPainter(TideTheme.of(context).isDark),
      child: const SizedBox.expand(),
    ),
  );
}

class _WallpaperPainter extends CustomPainter {
  const _WallpaperPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = (dark ? Colors.white : const Color(0xFF54895E)).withValues(
        alpha: .12,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (var row = 0; row < size.height / 70; row++) {
      for (var col = 0; col < size.width / 70; col++) {
        canvas.save();
        canvas.translate(col * 70.0 + (row.isOdd ? 26 : 8), row * 70.0 + 15);
        canvas.rotate((row + col) * .4);
        switch ((row + col) % 3) {
          case 0:
            for (var k = 0; k < 5; k++) {
              final angle = k * math.pi * 2 / 5;
              canvas.drawOval(
                Rect.fromCenter(
                  center: Offset(math.cos(angle) * 10, math.sin(angle) * 10),
                  width: 11,
                  height: 13,
                ),
                p,
              );
            }
            canvas.drawCircle(Offset.zero, 4, p);
          case 1:
            canvas.drawPath(
              Path()
                ..moveTo(0, 18)
                ..cubicTo(-30, 0, -10, -20, 0, -9)
                ..cubicTo(10, -20, 30, 0, 0, 18),
              p,
            );
          default:
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                const Rect.fromLTWH(-17, -12, 34, 24),
                const Radius.circular(9),
              ),
              p,
            );
            canvas.drawPath(
              Path()
                ..moveTo(-10, 12)
                ..lineTo(-13, 19)
                ..lineTo(-2, 12),
              p,
            );
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter old) => old.dark != dark;
}
