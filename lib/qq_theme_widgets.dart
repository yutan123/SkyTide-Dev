import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'theme.dart';

const qqBlue = Color(0xFF0099FF);

/// Blur the actual content behind a bar, including moving messages and images.
class QqFrostedBar extends StatelessWidget {
  const QqFrostedBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: ColoredBox(
          color:
              (theme.isDark ? const Color(0xFF202126) : const Color(0xFFF7F7FA))
                  .withValues(alpha: .76),
          child: child,
        ),
      ),
    );
  }
}

class QqNavigationBar extends StatelessWidget {
  const QqNavigationBar({
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
    return QqFrostedBar(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: List.generate(4, (i) {
              final selected = index == i;
              final color = selected ? qqBlue : theme.textStrong;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Semantics(
                    selected: selected,
                    button: true,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            QqIcon(
                              kind: [
                                'chat',
                                'person',
                                'activity',
                                'channel',
                              ][i],
                              color: color,
                              filled: selected,
                              size: 23,
                            ),
                            if (i == 0 && unread > 0)
                              Positioned(
                                right: -12,
                                top: -5,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF5845),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    unread > 99 ? '99+' : '$unread',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ['聊天', '空间', '动态', '我'][i],
                          style: TextStyle(color: color, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Reference silhouettes use the same geometry in outline and selected states.
class QqIcon extends StatelessWidget {
  const QqIcon({
    super.key,
    required this.kind,
    required this.color,
    this.filled = false,
    this.size = 28,
  });
  final String kind;
  final Color color;
  final bool filled;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _QqIconPainter(kind, color, filled)),
  );
}

class _QqIconPainter extends CustomPainter {
  const _QqIconPainter(this.kind, this.color, this.filled);
  final String kind;
  final Color color;
  final bool filled;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final ink = Paint()..color = color;
    if (kind == 'chat') {
      final path = Path()
        ..moveTo(16, 3)
        ..cubicTo(-1, 3, 0, 23, 11, 26)
        ..lineTo(20, 30)
        ..lineTo(20, 25)
        ..cubicTo(34, 21, 32, 3, 16, 3)
        ..close();
      canvas.drawPath(path, filled ? ink : pen);
      if (filled) {
        canvas.drawCircle(
          const Offset(11, 14),
          1.3,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          const Offset(21, 14),
          1.3,
          Paint()..color = Colors.white,
        );
      }
    } else if (kind == 'person') {
      final head = Path()
        ..moveTo(11, 3)
        ..cubicTo(6, 3, 7, 5, 9, 7)
        ..cubicTo(4, 21, 25, 23, 24, 11)
        ..cubicTo(24, 5, 20, 3, 11, 3)
        ..close();
      final body = Path()
        ..moveTo(4, 30)
        ..cubicTo(4, 20, 10, 19, 16, 23)
        ..cubicTo(22, 19, 28, 21, 28, 30)
        ..close();
      canvas.drawPath(head, filled ? ink : pen);
      canvas.drawPath(body, filled ? ink : pen);
    } else if (kind == 'channel') {
      if (filled) canvas.drawCircle(const Offset(16, 16), 15, ink);
      final line = filled
          ? (Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round)
          : pen;
      canvas.drawLine(const Offset(13, 3), const Offset(8, 29), line);
      canvas.drawLine(const Offset(24, 3), const Offset(19, 29), line);
      canvas.drawLine(const Offset(5, 11), const Offset(29, 11), line);
      canvas.drawLine(const Offset(3, 22), const Offset(27, 22), line);
    } else if (kind == 'activity') {
      if (filled) {
        canvas.drawCircle(const Offset(16, 16), 15, ink);
      } else {
        canvas.drawArc(
          const Rect.fromLTWH(3, 3, 26, 26),
          -.05,
          math.pi * 1.62,
          false,
          pen,
        );
      }
      final star = Path();
      for (var i = 0; i < 8; i++) {
        final angle = -math.pi / 2 + i * math.pi / 4;
        final radius = i.isEven ? 6.0 : 2.1;
        final x = 25 + math.cos(angle) * radius;
        final y = 7 + math.sin(angle) * radius;
        if (i == 0) {
          star.moveTo(x, y);
        } else {
          star.lineTo(x, y);
        }
      }
      canvas.drawPath(
        star..close(),
        Paint()..color = filled ? Colors.white : color,
      );
    } else if (kind == 'mic') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 2, 8, 19),
          const Radius.circular(4),
        ),
        pen,
      );
      canvas.drawPath(
        Path()
          ..moveTo(7, 14)
          ..lineTo(7, 18)
          ..cubicTo(7, 31, 25, 31, 25, 18)
          ..lineTo(25, 14),
        pen,
      );
      canvas.drawLine(const Offset(16, 27), const Offset(16, 31), pen);
    } else if (kind == 'smile') {
      canvas.drawCircle(const Offset(16, 16), 13, pen);
      canvas.drawLine(const Offset(11, 10), const Offset(11, 14), pen);
      canvas.drawLine(const Offset(21, 10), const Offset(21, 14), pen);
      canvas.drawPath(
        Path()
          ..moveTo(9, 20)
          ..quadraticBezierTo(16, 28, 23, 20),
        pen,
      );
    } else if (kind == 'photo') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 4, 26, 24),
          const Radius.circular(4),
        ),
        pen,
      );
      canvas.drawCircle(const Offset(22, 11), 3, pen);
      canvas.drawPath(
        Path()
          ..moveTo(4, 23)
          ..lineTo(12, 15)
          ..lineTo(21, 25)
          ..lineTo(25, 21)
          ..lineTo(29, 25),
        pen,
      );
    } else if (kind == 'camera') {
      canvas.drawPath(
        Path()
          ..moveTo(4, 8)
          ..lineTo(10, 8)
          ..lineTo(12, 4)
          ..lineTo(20, 4)
          ..lineTo(22, 8)
          ..lineTo(28, 8)
          ..quadraticBezierTo(30, 8, 30, 11)
          ..lineTo(30, 26)
          ..quadraticBezierTo(30, 28, 27, 28)
          ..lineTo(5, 28)
          ..quadraticBezierTo(2, 28, 2, 25)
          ..lineTo(2, 11)
          ..quadraticBezierTo(2, 8, 4, 8)
          ..close(),
        pen,
      );
      canvas.drawCircle(const Offset(16, 18), 7, pen);
    } else if (kind == 'video') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 7, 20, 20),
          const Radius.circular(5),
        ),
        pen,
      );
      canvas.drawPath(
        Path()
          ..moveTo(22, 13)
          ..lineTo(30, 8)
          ..lineTo(30, 26)
          ..lineTo(22, 21),
        pen,
      );
    } else if (kind == 'file') {
      canvas.drawPath(
        Path()
          ..moveTo(12, 20)
          ..lineTo(21, 10)
          ..cubicTo(26, 5, 31, 11, 26, 16)
          ..lineTo(14, 28)
          ..cubicTo(5, 36, -2, 23, 5, 17)
          ..lineTo(19, 3),
        pen,
      );
    } else if (kind == 'add') {
      canvas.drawLine(const Offset(3, 16), const Offset(29, 16), pen);
      canvas.drawLine(const Offset(16, 3), const Offset(16, 29), pen);
    }
  }

  @override
  bool shouldRepaint(covariant _QqIconPainter oldDelegate) =>
      kind != oldDelegate.kind ||
      color != oldDelegate.color ||
      filled != oldDelegate.filled;
}

class QqBubble extends StatelessWidget {
  const QqBubble({super.key, required this.isUser, required this.child});
  final bool isUser;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 40),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color:
          TideTheme.of(
            context,
          ).appearanceColor(isUser ? 'bubbleUser' : 'bubbleAi') ??
          (isUser ? qqBlue : TideTheme.of(context).surface),
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );
}

class QqChatSettingsPage extends StatelessWidget {
  const QqChatSettingsPage({super.key, required this.actions});
  final List<({String title, VoidCallback onTap})> actions;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.pageBackground,
      appBar: AppBar(
        title: const Text('聊天设置'),
        centerTitle: true,
        backgroundColor: theme.surface,
        foregroundColor: theme.textStrong,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 5,
                  ),
                  title: Text(
                    action.title,
                    style: TextStyle(color: theme.textStrong),
                  ),
                  trailing: Icon(Icons.chevron_right, color: theme.textFaint),
                  onTap: () {
                    Navigator.pop(context);
                    action.onTap();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
