import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'theme.dart';

/// 微信风格的平面导航，不使用玻璃、浮岛或胶囊选中背景。
class WechatNavigationBar extends StatelessWidget {
  const WechatNavigationBar({
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.wechatBar,
        border: Border(top: BorderSide(color: theme.divider, width: .5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: Row(
            children: List.generate(4, (i) {
              final color = i == index ? theme.primary : theme.textStrong;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          WechatIcon(
                            kind: ['chat', 'contacts', 'discover', 'person'][i],
                            color: color,
                            filled: i == index,
                            size: 23,
                          ),
                          if (i == 0 && unread > 0)
                            Positioned(
                              top: -5,
                              right: -12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFA5151),
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
                      const SizedBox(height: 3),
                      Text(
                        ['聊天', '空间', '动态', '我'][i],
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ],
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

/// 统一线宽的主题图标，避免用平台默认图标替代参考图的轮廓。
class WechatIcon extends StatelessWidget {
  const WechatIcon({
    super.key,
    required this.kind,
    required this.color,
    this.size = 28,
    this.filled = false,
  });
  final String kind;
  final Color color;
  final double size;
  final bool filled;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _WechatIconPainter(kind, color, filled)),
  );
}

class _WechatIconPainter extends CustomPainter {
  _WechatIconPainter(this.kind, this.color, this.filled);
  final String kind;
  final Color color;
  final bool filled;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (kind == 'add' || kind == 'voice' || kind == 'smile') {
      canvas.drawCircle(const Offset(16, 16), 13, p);
      if (kind == 'add') {
        canvas.drawLine(const Offset(8, 16), const Offset(24, 16), p);
        canvas.drawLine(const Offset(16, 8), const Offset(16, 24), p);
      } else if (kind == 'smile') {
        canvas.drawCircle(const Offset(11, 12), 1.5, Paint()..color = color);
        canvas.drawCircle(const Offset(21, 12), 1.5, Paint()..color = color);
        canvas.drawPath(
          Path()
            ..moveTo(9, 19)
            ..quadraticBezierTo(16, 27, 23, 19),
          p,
        );
      } else {
        // Three nested sound waves inside the circle, without a speaker cone.
        p.strokeCap = StrokeCap.butt;
        for (var i = 0; i < 3; i++) {
          final x = 10.0 + i * 4;
          final halfHeight = 3.0 + i * 3.0;
          canvas.drawPath(
            Path()
              ..moveTo(x, 16 - halfHeight)
              ..quadraticBezierTo(x + halfHeight, 16, x, 16 + halfHeight),
            p,
          );
        }
      }
    } else if (kind == 'chat') {
      final path = Path()
        ..moveTo(16, 3)
        ..cubicTo(0, 3, -1, 23, 10, 25)
        ..lineTo(9, 30)
        ..lineTo(17, 26)
        ..cubicTo(34, 26, 35, 3, 16, 3)
        ..close();
      if (filled) p.style = PaintingStyle.fill;
      canvas.drawPath(path, p);
    } else if (kind == 'discover') {
      canvas.drawCircle(const Offset(16, 16), 13, p);
      canvas.drawPath(
        Path()
          ..moveTo(23, 9)
          ..lineTo(18, 19)
          ..lineTo(8, 24)
          ..lineTo(13, 14)
          ..close(),
        p,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(5, 28)
          ..quadraticBezierTo(3, 25, 10, 22)
          ..quadraticBezierTo(14, 20, 12, 16)
          ..cubicTo(6, 7, 12, 2, 16, 3)
          ..cubicTo(23, 2, 25, 10, 20, 16)
          ..quadraticBezierTo(18, 20, 23, 22)
          ..quadraticBezierTo(30, 25, 28, 28)
          ..close(),
        p,
      );
      if (kind == 'contacts') {
        canvas.drawLine(const Offset(26, 9), const Offset(31, 9), p);
        canvas.drawLine(const Offset(26, 13), const Offset(31, 13), p);
        canvas.drawLine(const Offset(26, 17), const Offset(30, 17), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WechatIconPainter old) =>
      old.kind != kind || old.color != color || old.filled != filled;
}

class WechatBubble extends StatelessWidget {
  const WechatBubble({super.key, required this.isUser, required this.child});
  final bool isUser;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    final color = isUser
        ? theme.wechatOutgoing
        : theme.appearanceColor('bubbleAi') ?? theme.surface;
    return CustomPaint(
      painter: _WechatBubblePainter(color: color, isUser: isUser),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    );
  }
}

/// Draw the tail outside the content box so it never changes text wrapping.
class _WechatBubblePainter extends CustomPainter {
  const _WechatBubblePainter({required this.color, required this.isUser});
  final Color color;
  final bool isUser;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5)),
      );
    final edge = isUser ? size.width : 0.0;
    final direction = isUser ? 1.0 : -1.0;
    final tail = Path()
      ..moveTo(edge - direction, 12)
      ..lineTo(edge + direction * 5, 18)
      ..quadraticBezierTo(edge + direction * 5.5, 19, edge + direction * 5, 20)
      ..lineTo(edge - direction, 25)
      ..close();
    canvas.drawPath(
      Path.combine(PathOperation.union, body, tail),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _WechatBubblePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isUser != isUser;
}

/// Voice waves accumulate one at a time, then clear for the next cycle.
class WechatVoiceIcon extends StatefulWidget {
  const WechatVoiceIcon({
    super.key,
    required this.isUser,
    required this.color,
    required this.playing,
  });
  final bool isUser;
  final Color color;
  final bool playing;

  @override
  State<WechatVoiceIcon> createState() => _WechatVoiceIconState();
}

class _WechatVoiceIconState extends State<WechatVoiceIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant WechatVoiceIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.value = 0;
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 24,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => CustomPaint(
        painter: _WechatVoicePainter(
          color: widget.color,
          isUser: widget.isUser,
          waves: widget.playing ? (_controller.value * 4).floor() : 3,
        ),
      ),
    ),
  );
}

class _WechatVoicePainter extends CustomPainter {
  const _WechatVoicePainter({
    required this.color,
    required this.isUser,
    required this.waves,
  });
  final Color color;
  final bool isUser;
  final int waves;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 22, size.height / 24);
    if (isUser) {
      canvas.translate(22, 0);
      canvas.scale(-1, 1);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < waves; i++) {
      final x = 4.0 + i * 5;
      final halfHeight = 3.0 + i * 3.5;
      canvas.drawPath(
        Path()
          ..moveTo(x, 12 - halfHeight)
          ..quadraticBezierTo(x + halfHeight, 12, x, 12 + halfHeight),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WechatVoicePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.isUser != isUser ||
      oldDelegate.waves != waves;
}

/// 聊天信息页保留宿主提供的四项能力，页面仅负责布局。
class WechatChatInfoPage extends StatelessWidget {
  const WechatChatInfoPage({super.key, required this.actions});
  final List<({String title, VoidCallback onTap})> actions;
  @override
  Widget build(BuildContext context) {
    final theme = TideTheme.of(context);
    return Scaffold(
      backgroundColor: theme.pageBackground,
      appBar: AppBar(
        title: const Text('聊天信息'),
        centerTitle: true,
        backgroundColor: theme.wechatBar,
        foregroundColor: theme.textStrong,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: theme.surface,
                child: ListTile(
                  minTileHeight: 58,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(
                    action.title,
                    style: TextStyle(color: theme.textStrong, fontSize: 16),
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

/// Reports composer layout changes after the frame, including animated panels.
class ThemeMeasuredSize extends SingleChildRenderObjectWidget {
  const ThemeMeasuredSize({
    super.key,
    required this.onChange,
    required super.child,
  });
  final ValueChanged<Size> onChange;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ThemeSizeReporter(onChange);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _ThemeSizeReporter).onChange = onChange;
  }
}

class _ThemeSizeReporter extends RenderProxyBox {
  _ThemeSizeReporter(this.onChange);
  ValueChanged<Size> onChange;
  Size? _reported;
  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    _reported = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onChange(measured);
    });
  }
}
