final class PluginMarketVersion {
  static final _version = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );
  static final _minimum = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
  );

  static String? minimum(Object? value) {
    if (value == null) return null;
    if (value is! String || !_minimum.hasMatch(value)) {
      throw const FormatException('市场插件 minSkyTideVersion 必须为 X.Y.Z');
    }
    return value;
  }

  static bool meetsMinimum(String installed, String minimum) {
    final actual = _version.firstMatch(installed);
    final required = _minimum.firstMatch(minimum);
    if (actual == null || required == null) return false;
    for (var i = 1; i <= 3; i++) {
      final order = BigInt.parse(
        actual[i]!,
      ).compareTo(BigInt.parse(required[i]!));
      if (order != 0) return order > 0;
    }
    return actual[4] == null;
  }
}
