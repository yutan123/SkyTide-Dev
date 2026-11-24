import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'db.dart';
import 'plugin_archive.dart';
import 'plugin_operation.dart';
import 'plugin_market_routes.dart';
import 'plugin_market_version.dart';

class MarketPlugin {
  final String id,
      name,
      author,
      description,
      repository,
      version,
      commit,
      changelog;
  final String? icon, minSkyTideVersion;
  MarketPlugin(Map<String, dynamic> json)
    : minSkyTideVersion = PluginMarketVersion.minimum(
        json['minSkyTideVersion'],
      ),
      id = PluginArchive.marketId(json['id'] as String),
      name = json['name'] as String,
      author = json['author'] as String,
      description = json['description'] as String,
      repository = json['repository'] as String,
      version = json['version'] as String,
      commit = json['commit'] as String,
      icon = json['icon'] is String ? json['icon'] as String : null,
      changelog = json['changelog'] as String? ?? '' {
    if (!RegExp(
          r'^skytide[a-z0-9_.-]{0,57}$',
          caseSensitive: false,
        ).hasMatch(id) ||
        name.isEmpty ||
        !RegExp(
          r'^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
        ).hasMatch(repository) ||
        !RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(commit) ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw const FormatException('市场插件信息无效');
    }
  }
  String get sourceRecord => jsonEncode({
    'repository': repository,
    'commit': commit,
    'version': version,
  });

  Uri get archiveUrl => Uri.parse('$repository/archive/$commit.zip');
  Uri? get iconUrl {
    final path = icon;
    if (path == null ||
        !RegExp(
          r'^[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)*\.(?:png|jpe?g|webp)$',
          caseSensitive: false,
        ).hasMatch(path))
      return null;
    final segments = path.split('/');
    if (segments.any((segment) => segment == '.' || segment == '..'))
      return null;
    return Uri.https(
      'raw.githubusercontent.com',
      '${Uri.parse(repository).path}/$commit/$path',
    );
  }

  bool newerThan(String installed) {
    final old = installed.split('.').map(int.tryParse).toList();
    final next = version.split('.').map(int.parse).toList();
    if (old.length != 3 || old.any((v) => v == null)) return false;
    for (var i = 0; i < 3; i++) {
      if (next[i] != old[i]) return next[i] > old[i]!;
    }
    return false;
  }
}

class PluginMarket extends ChangeNotifier {
  PluginMarket._();
  static final instance = PluginMarket._();
  static final indexUrl = Uri.parse(
    'https://raw.githubusercontent.com/yutan123/TideBot-plugins/main/market/index.json',
  );

  // Ordered from the direct source to public GitHub mirrors. A route is only
  // accepted only after its response body passes validation.
  static List<Uri> _routes(Uri uri) {
    final encoded = Uri.encodeFull(uri.toString());
    return [
      uri,
      Uri.parse('https://ghproxy.net/$encoded'),
      Uri.parse('https://gh-proxy.com/$encoded'),
      Uri.parse('https://ghfast.top/$encoded'),
    ];
  }

  static List<Uri> iconRoutes(MarketPlugin plugin) {
    final url = plugin.iconUrl;
    return url == null ? const [] : _routes(url);
  }

  List<MarketPlugin> plugins = [];
  bool hasIndex = false;
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> _revocations = [];
  Future<void>? _refresh;

  ({List<MarketPlugin> plugins, List<Map<String, dynamic>> revocations}) _parse(
    String text,
  ) {
    final root = jsonDecode(text) as Map<String, dynamic>;
    final list = (root['plugins'] as List)
        .map((v) => MarketPlugin(Map<String, dynamic>.from(v as Map)))
        .toList();
    if (list.map((p) => p.id).toSet().length != list.length) {
      throw const FormatException('市场包含重复插件 ID');
    }
    final revocations = (root['revocations'] as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    return (plugins: list, revocations: revocations);
  }

  Future<void> refresh() =>
      _refresh ??= _load().whenComplete(() => _refresh = null);
  Future<void> _load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final db = DBManager();
      final cache = await db.getKV('plugin_market_index');
      var validCache = false;
      if (cache != null) {
        try {
          final parsed = _parse(cache);
          validCache = true;
          if (!hasIndex) {
            plugins = parsed.plugins;
            _revocations = parsed.revocations;
            hasIndex = true;
            notifyListeners();
          }
        } catch (_) {}
      }
      final etag = await db.getKV('plugin_market_etag');
      final validateCache = validCache && etag != null && etag.isNotEmpty;
      final result = await readMarketRoute(
        routes: _routes(indexUrl),
        timeout: const Duration(seconds: 20),
        connectionTimeout: const Duration(seconds: 15),
        acceptedStatusCodes: {200, if (validateCache) 304},
        configure: (request) {
          if (validateCache) request.headers.set('If-None-Match', etag);
        },
        read: (response) async {
          if (response.statusCode == 304) return null;
          final bytes = <int>[];
          await for (final chunk in response.timeout(
            const Duration(seconds: 20),
          )) {
            bytes.addAll(chunk);
            if (bytes.length > 2 * 1024 * 1024) {
              throw const FormatException('市场索引过大');
            }
          }
          final text = utf8.decode(bytes);
          return (
            text: text,
            parsed: _parse(text),
            etag: response.headers.value('etag') ?? '',
          );
        },
      );
      if (result == null) return;
      await db.setKV('plugin_market_index', result.text);
      await db.setKV('plugin_market_etag', result.etag);
      plugins = result.parsed.plugins;
      _revocations = result.parsed.revocations;
      hasIndex = true;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> source(String id) async {
    final value = await DBManager().getKV('plugin_market_source_$id');
    if (value == null || value.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSource(String id) =>
      DBManager().setKV('plugin_market_source_$id', '');

  Future<File> download(
    MarketPlugin plugin,
    Directory temporary,
    PluginOperation operation,
    void Function(int, int) progress,
  ) async {
    if (_revocations.any(
      (r) =>
          r['id'] is String &&
          PluginArchive.marketId(r['id'] as String) == plugin.id &&
          r['commit'] == plugin.commit,
    )) {
      throw const FormatException('该版本已撤销');
    }
    const timeout = Duration(seconds: 30);
    final package = await readMarketRoute(
      routes: _routes(plugin.archiveUrl),
      timeout: timeout,
      connectionTimeout: const Duration(seconds: 20),
      checkCancelled: operation.check,
      listenForCancellation: operation.listen,
      read: (response) async {
        if (response.contentLength > PluginArchive.maxCompressed) {
          throw const FormatException('插件包超过大小限制');
        }
        final bytes = <int>[];
        progress(0, response.contentLength);
        await for (final chunk in response.timeout(timeout)) {
          operation.check();
          bytes.addAll(chunk);
          if (bytes.length > PluginArchive.maxCompressed) {
            throw const FormatException('插件包超过大小限制');
          }
          progress(bytes.length, response.contentLength);
        }
        final package = PluginArchive.decode(
          bytes,
          githubWrapper: true,
          expectedMarketId: plugin.id,
        );
        if (package.manifest['id'] != plugin.id ||
            package.manifest['version'] != plugin.version) {
          throw const FormatException('下载插件的 ID 或版本与市场不一致');
        }
        return package;
      },
    );
    final archive = Archive();
    for (final entry in package.files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final file = File('${temporary.path}/market.zip');
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    operation.check();
    return file;
  }
}
