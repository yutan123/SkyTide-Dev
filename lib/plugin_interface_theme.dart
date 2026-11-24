const pluginThemeOrderKey = '_interfaceThemeEnabledAt';

const pluginPaletteKeys = {
  'primary',
  'primaryLight',
  'pageBackground',
  'surface',
  'surfaceVariant',
  'glass',
  'textStrong',
  'textWeak',
  'textFaint',
  'iconMuted',
  'border',
  'divider',
  'bubbleAi',
  'bubbleUser',
  'buttonSecondary',
  'backgroundOverlay',
};

const pluginSurfaceTargets = {
  'card',
  'card.glass',
  'card.frost',
  'card.bot',
  'card.voiceCall',
  'card.link',
  'card.code',
  'card.video',
  'card.post',
  'card.metrics',
  'card.chart',
  'card.control',
  'dialog',
  'dialog.confirm',
  'dialog.notice',
  'dialog.choice',
  'dialog.form',
  'dialog.progress',
  'dialog.sheet',
  'dialog.popover',
  'chat.header',
  'chat.input',
};

const _materials = {'normal', 'frosted', 'liquid'};
const pluginDecorationAnchors = [
  'topLeft',
  'topCenter',
  'topRight',
  'centerLeft',
  'center',
  'centerRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
];

Never _invalid(String field) =>
    throw FormatException('interfaceTheme.$field 无效');

Map<String, dynamic> _object(Object? value, Set<String> allowed, String field) {
  if (value is! Map || value.keys.any((key) => !allowed.contains(key))) {
    _invalid(field);
  }
  return Map<String, dynamic>.from(value);
}

Object? _optional(Map<String, dynamic> map, String key, Object fallback) =>
    map.containsKey(key) ? map[key] : fallback;

int _color(Object? value, String field) {
  if (value is! String ||
      !RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(value)) {
    _invalid(field);
  }
  return int.parse(
    value.length == 7 ? 'FF${value.substring(1)}' : value.substring(1),
    radix: 16,
  );
}

double _number(Object? value, double min, double max, String field) {
  if (value is! num || !value.isFinite || value < min || value > max)
    _invalid(field);
  return value.toDouble();
}

class PluginThemeDecoration {
  final String asset;
  final int anchor;
  final double x, y, width, height, opacity;
  const PluginThemeDecoration(
    this.asset,
    this.anchor,
    this.x,
    this.y,
    this.width,
    this.height,
    this.opacity,
  );

  factory PluginThemeDecoration.parse(Object? raw) {
    final m = _object(raw, {
      'asset',
      'anchor',
      'offsetX',
      'offsetY',
      'width',
      'height',
      'opacity',
    }, 'decorations');
    final asset = m['asset'];
    if (asset is! String ||
        asset.length > 200 ||
        !asset.endsWith('.png') ||
        !RegExp(r'^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$').hasMatch(asset) ||
        asset.split('/').any((part) => part == '.' || part == '..'))
      _invalid('decorations.asset');
    final anchorName = _optional(m, 'anchor', 'center');
    if (anchorName is! String) _invalid('decorations.anchor');
    final anchor = pluginDecorationAnchors.indexOf(anchorName);
    if (anchor < 0) _invalid('decorations.anchor');
    return PluginThemeDecoration(
      asset,
      anchor,
      _number(_optional(m, 'offsetX', 0), -2048, 2048, 'decorations.offsetX'),
      _number(_optional(m, 'offsetY', 0), -2048, 2048, 'decorations.offsetY'),
      _number(m['width'], 1, 512, 'decorations.width'),
      _number(m['height'], 1, 512, 'decorations.height'),
      _number(_optional(m, 'opacity', 1), 0, 1, 'decorations.opacity'),
    );
  }
}

class PluginSurfaceStyle {
  final int? fill, stroke;
  final double? strokeWidth;
  final List<PluginThemeDecoration>? decorations;
  const PluginSurfaceStyle({
    this.fill,
    this.stroke,
    this.strokeWidth,
    this.decorations,
  });

  PluginSurfaceStyle merge(PluginSurfaceStyle? next) => next == null
      ? this
      : PluginSurfaceStyle(
          fill: next.fill ?? fill,
          stroke: next.stroke ?? stroke,
          strokeWidth: next.strokeWidth ?? strokeWidth,
          decorations: next.decorations ?? decorations,
        );

  static PluginSurfaceStyle parse(Map<String, dynamic> m) {
    final raw = m['decorations'];
    if (m.containsKey('decorations') && (raw is! List || raw.length > 16))
      _invalid('decorations');
    return PluginSurfaceStyle(
      fill: m.containsKey('fill') ? _color(m['fill'], 'fill') : null,
      stroke: m.containsKey('stroke') ? _color(m['stroke'], 'stroke') : null,
      strokeWidth: m.containsKey('strokeWidth')
          ? _number(m['strokeWidth'], 0, 8, 'strokeWidth')
          : null,
      decorations: raw is List
          ? List.unmodifiable(raw.map(PluginThemeDecoration.parse))
          : null,
    );
  }

  bool get isEmpty =>
      fill == null &&
      stroke == null &&
      strokeWidth == null &&
      (decorations?.isEmpty ?? true);
}

class _Layer {
  final Map<String, int> colors;
  final Map<String, Map<String, PluginSurfaceStyle>> surfaces;
  _Layer(Object? raw)
    : colors = _object(
        _optional(_object(raw, {'colors', 'surfaces'}, 'mode'), 'colors', {}),
        pluginPaletteKeys,
        'colors',
      ).map((key, value) => MapEntry(key, _color(value, 'colors.$key'))),
      surfaces =
          _object(
            _optional(
              _object(raw, {'colors', 'surfaces'}, 'mode'),
              'surfaces',
              {},
            ),
            pluginSurfaceTargets,
            'surfaces',
          ).map((key, value) {
            const properties = {'fill', 'stroke', 'strokeWidth', 'decorations'};
            final rules = _object(value, {...properties, ..._materials}, key);
            return MapEntry(key, {
              'base': PluginSurfaceStyle.parse(rules),
              for (final material in _materials)
                if (rules.containsKey(material))
                  material: PluginSurfaceStyle.parse(
                    _object(rules[material], properties, material),
                  ),
            });
          });
}

class PluginInterfaceTheme {
  final List<_Layer> _layers;
  PluginInterfaceTheme._(Object? raw)
    : _layers = [
        for (final key in ['common', 'light', 'dark'])
          _Layer(
            _optional(
              _object(raw, {'common', 'light', 'dark'}, 'root'),
              key,
              {},
            ),
          ),
      ];

  static PluginInterfaceTheme? fromManifest(Map<String, dynamic> manifest) {
    if (!manifest.containsKey('appearance')) return null;
    final appearance = _object(manifest['appearance'], {
      'launchAnimation',
      'interfaceTheme',
    }, 'appearance');
    if (appearance.isEmpty) _invalid('appearance');
    return appearance.containsKey('interfaceTheme')
        ? PluginInterfaceTheme._(appearance['interfaceTheme'])
        : null;
  }

  int? color(String key, bool dark) =>
      _layers[dark ? 2 : 1].colors[key] ?? _layers[0].colors[key];

  PluginSurfaceStyle surface(String target, String material, bool dark) {
    final fallback = target.split('.').first;
    var result = const PluginSurfaceStyle();
    for (final key in {fallback, target}) {
      for (final layer in [_layers[0], _layers[dark ? 2 : 1]]) {
        result = result
            .merge(layer.surfaces[key]?['base'])
            .merge(layer.surfaces[key]?[material]);
      }
    }
    return result;
  }

  void validateFiles(Map<String, List<int>> files) {
    final assets = {
      for (final layer in _layers)
        for (final variants in layer.surfaces.values)
          for (final style in variants.values)
            for (final decoration
                in style.decorations ?? const <PluginThemeDecoration>[])
              decoration.asset,
    };
    if (assets.length > 64) _invalid('assets');
    var total = 0;
    for (final asset in assets) {
      final data = files[asset];
      if (data == null || data.length < 33 || data.length > 1024 * 1024)
        _invalid('asset $asset');
      total += data.length;
      if (total > 8 * 1024 * 1024) _invalid('assets');
      const header = [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
      ];
      for (var i = 0; i < header.length; i++) {
        if (data[i] != header[i]) _invalid('asset $asset');
      }
      int dimension(int index) =>
          data.sublist(index, index + 4).fold(0, (n, byte) => (n << 8) | byte);
      for (final size in [dimension(16), dimension(20)]) {
        if (size < 1 || size > 1024) _invalid('asset $asset');
      }
    }
  }
}
