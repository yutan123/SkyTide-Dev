import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'theme.dart';

class _AppearanceImage extends FileImage {
  const _AppearanceImage(super.file, this.revision);
  final String? revision;

  @override
  bool operator ==(Object other) =>
      other is _AppearanceImage &&
      other.file.path == file.path &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(file.path, revision);
}

/// Renders a normal Material card while targeting only its painted area.
class TideMaterialCard extends StatelessWidget {
  const TideMaterialCard({
    super.key,
    required this.child,
    this.color,
    this.target = 'card',
  });

  final Widget child;
  final Color? color;
  final String target;

  @override
  Widget build(BuildContext context) {
    final fill = tideAppearanceFill(context, target);
    final shape = CardTheme.of(context).shape;
    final radius = shape is RoundedRectangleBorder
        ? shape.borderRadius
        : BorderRadius.circular(Theme.of(context).useMaterial3 ? 12 : 4);
    return Card(
      color: fill ?? color,
      surfaceTintColor: fill == null ? null : Colors.transparent,
      child: tideAppearanceSurface(
        context,
        target,
        child,
        paintFill: false,
        radius: radius,
      ),
    );
  }
}

/// Styles a host-owned surface without changing its layout or hit testing.
Widget tideAppearanceSurface(
  BuildContext context,
  String target,
  Widget child, {
  String material = 'normal',
  BorderRadiusGeometry? radius,
  bool opaque = false,
  bool paintFill = true,
}) {
  final theme = TideTheme.of(context);
  final style = theme.appearanceSurface(target, material);
  if (style == null || style.isEmpty) return child;
  var fill = !paintFill || style.fill == null ? null : Color(style.fill!);
  if (opaque) fill = fill?.withValues(alpha: 1);
  final box = child is Container
      ? (child.decoration ?? const BoxDecoration())
      : null;
  final circle = box is BoxDecoration && box.shape == BoxShape.circle;
  if (box is BoxDecoration &&
      fill != null &&
      material != 'liquid' &&
      child is Container) {
    child = Container(
      key: child.key,
      alignment: child.alignment,
      padding: child.padding,
      decoration: BoxDecoration(
        color: fill,
        image: box.image,
        border: box.border,
        borderRadius: box.borderRadius,
        boxShadow: box.boxShadow,
        shape: box.shape,
      ),
      foregroundDecoration: child.foregroundDecoration,
      constraints: child.constraints,
      margin: child.margin,
      transform: child.transform,
      transformAlignment: child.transformAlignment,
      clipBehavior: child.clipBehavior,
      child: child.child,
    );
    fill = null;
  }
  radius ??= box is BoxDecoration ? box.borderRadius : null;
  final imageRoot = theme.appearanceRoot;
  final decorations = style.decorations ?? [];
  final direction = Directionality.of(context);
  final stroke = style.stroke == null ? theme.border : Color(style.stroke!);
  final outline =
      (style.stroke != null || style.strokeWidth != null) &&
      style.strokeWidth != 0;
  Widget clipped(Widget layer) => IgnorePointer(
    child: ExcludeSemantics(
      child: circle
          ? ClipOval(child: layer)
          : ClipRRect(
              borderRadius: radius?.resolve(direction) ?? BorderRadius.zero,
              child: layer,
            ),
    ),
  );
  return Stack(
    fit: StackFit.passthrough,
    clipBehavior: Clip.none,
    children: [
      if (fill != null)
        Positioned.fill(
          child: clipped(
            ColoredBox(
              color: material == 'liquid' && fill.a > .45
                  ? fill.withValues(alpha: .45)
                  : fill,
            ),
          ),
        ),
      child,
      if (outline || (imageRoot != null && decorations.isNotEmpty))
        Positioned.fill(
          child: clipped(
            Stack(
              fit: StackFit.expand,
              children: [
                if (imageRoot != null)
                  for (final image in decorations)
                    OverflowBox(
                      minWidth: image.width,
                      maxWidth: image.width,
                      minHeight: image.height,
                      maxHeight: image.height,
                      alignment: Alignment(
                        (image.anchor % 3 - 1).toDouble(),
                        (image.anchor ~/ 3 - 1).toDouble(),
                      ),
                      child: Transform.translate(
                        offset: Offset(image.x, image.y),
                        child: Opacity(
                          opacity: image.opacity,
                          child: Image(
                            image: ResizeImage(
                              _AppearanceImage(
                                File(p.join(imageRoot, image.asset)),
                                theme.appearanceRevision,
                              ),
                              width:
                                  (image.width *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .ceil()
                                      .clamp(1, 1024),
                              height:
                                  (image.height *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .ceil()
                                      .clamp(1, 1024),
                              policy: ResizeImagePolicy.fit,
                            ),
                            width: image.width,
                            height: image.height,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                if (outline)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: circle ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: circle ? null : radius,
                      border: Border.all(
                        color: stroke,
                        width: style.strokeWidth ?? 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
}

Color? tideAppearanceFill(
  BuildContext context,
  String target, [
  String material = 'normal',
]) {
  final fill = TideTheme.of(context).appearanceSurface(target, material)?.fill;
  return fill == null ? null : Color(fill);
}
