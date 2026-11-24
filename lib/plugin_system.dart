import 'plugin_interface_theme.dart';
import 'package:crypto/crypto.dart';
import 'plugin_operation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'db.dart';
import 'plugin_archive.dart';
import 'plugin_coordinator.dart';
import 'plugin_install_journal.dart';
import 'plugin_launch_spec.dart';

class TidePluginPackage {
  final Map<String, dynamic> manifest;
  final Directory directory;
  const TidePluginPackage(this.manifest, this.directory);
  String get id => manifest['id'] as String;
  String get name => manifest['name'] as String;
  String get version => manifest['version'] as String;
  bool get hasProgram => manifest['entry'] is String;
  String get entry => manifest['entry'] as String;
  bool get hasUi =>
      manifest['ui'] is Map &&
      (manifest['ui']['entry'] as String?)?.isNotEmpty == true;
}

class PluginSystem {
  PluginSystem._();
  static final instance = PluginSystem._();
  final _interfaceThemeChanges = StreamController<void>.broadcast();
  Stream<void> get interfaceThemeChanges => _interfaceThemeChanges.stream;

  static const _secureStorage = FlutterSecureStorage();
  static final _validId = RegExp(
    r'^[a-z][a-z0-9_.-]{2,63}$',
    caseSensitive: false,
  );
  void _checkId(String id) {
    if (!_validId.hasMatch(id)) throw const FormatException('插件 ID 无效');
  }

  Future<Directory> get _root async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'plugins'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<T> _transaction<T>(Future<T> Function(Directory root) work) =>
      PluginCoordinator.locked('lifecycle', () async {
        final root = await _root;
        await _recover(root);
        return work(root);
      });
  Future<List<Map<String, dynamic>>> list() =>
      _transaction((_) => DBManager().queryPlugins());

  late final _recovery = PluginInstallJournal(
    queryRows: () => DBManager().queryPlugins(),
    deleteRow: (id) => DBManager().deletePlugin(id),
    invalidate: PluginCoordinator.invalidate,
    deleteData: (id) => PluginCoordinator.locked('storage:$id', () async {
      final files = Directory(
        '${(await getApplicationSupportDirectory()).path}/plugin_files/$id',
      );
      if (await files.exists()) await files.delete(recursive: true);
      await _secureStorage.delete(key: 'plugin_data_$id');
      await _secureStorage.delete(key: 'plugin_bot_data_$id');
      await _secureStorage.delete(key: 'plugin_prompts_$id');
      await _secureStorage.delete(key: 'plugin_credentials_$id');
      await _secureStorage.delete(key: _configKey(id));
      final db = await DBManager().database;
      await db.delete(
        'kv_store',
        where: 'key = ?',
        whereArgs: ['plugin_disabled_bots_$id'],
      );
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'plugin_tasks'",
      );
      final eventTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'plugin_events'",
      );
      if (eventTables.isNotEmpty)
        await db.delete(
          'plugin_events',
          where: 'plugin_id = ?',
          whereArgs: [id],
        );
      if (tables.isNotEmpty) {
        await db.delete(
          'plugin_tasks',
          where: 'plugin_id = ?',
          whereArgs: [id],
        );
      }
    }),
  );
  Future<void> _recover(Directory root) => _recovery.recover(root);
  Future<void> _journal(Directory root, Map<String, dynamic> record) =>
      _recovery.write(root, record);

  Future<bool> installZip(
    String zipPath, {
    bool update = false,
    String? expectedId,
    String? marketSource,
    Future<void> Function()? beforeSwap,
    Future<void> Function(TidePluginPackage)? verifyUpdate,
    Future<void> Function()? stopCandidate,
    PluginOperation? operation,
  }) => _transaction((root) async {
    operation?.check();
    final file = File(zipPath);
    if (await file.length() > PluginArchive.maxCompressed) {
      throw const FormatException('插件包超过 256 MiB 限制');
    }
    final bytes = await file.readAsBytes();
    final archive = await _decodeArchive(bytes, operation);
    operation?.check();
    final manifest = Map<String, dynamic>.from(archive.manifest)
      ..remove(pluginLaunchEnabledOrderKey)
      ..remove(pluginThemeOrderKey);
    manifest['_installedPackage'] = {
      'source': 'local',
      'sha256': sha256.convert(bytes).toString(),
    };
    final id = manifest['id'] as String;
    _checkId(id);
    if (expectedId != null && id != expectedId) {
      throw const FormatException('更新包 ID 与当前插件不一致');
    }
    final rows = await DBManager().queryPlugins();
    final previous = rows.where((row) => row['id'] == id).firstOrNull;
    final launch = pluginLaunchDeclaration(manifest) != null;
    final enabled = update && previous?['enabled'] == 1;
    final customTheme = _hasInterfaceTheme(manifest);
    if (customTheme && enabled) {
      final old = jsonDecode(previous!['manifest_json'] as String);
      final order = _themeOrder(old);
      manifest[pluginThemeOrderKey] = order > 0 ? order : _nextThemeOrder(rows);
    }
    if (launch && enabled) {
      var order = _launchOrder(
        jsonDecode(previous!['manifest_json'] as String),
      );
      if (order == 0) {
        order = DateTime.now().microsecondsSinceEpoch;
        for (final row in rows.where((row) => row['enabled'] == 1)) {
          final other = _launchOrder(
            jsonDecode(row['manifest_json'] as String),
          );
          if (other >= order) order = other + 1;
        }
      }
      manifest[pluginLaunchEnabledOrderKey] = order;
    }
    final target = Directory(p.join(root.path, id));
    final existed = await target.exists();
    if ((existed || previous != null) && !update) {
      throw FormatException('插件 $id 已安装，请使用更新操作');
    }
    if (update && (previous == null || !existed)) {
      throw StateError('待更新插件不存在或文件缺失');
    }
    final staging = await root.createTemp('$id.installing-');
    final backupName = '${p.basename(staging.path)}.backup';
    var journaled = false;
    var committed = false;
    var checkingCandidate = false;
    try {
      for (final entry in archive.files.entries) {
        operation?.check();
        final out = File(p.join(staging.path, entry.key));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.value, flush: true);
      }
      operation?.check();
      if (update) {
        await beforeSwap?.call();
        await PluginCoordinator.invalidate(id);
      }
      operation?.beginCommit();
      final marker = DateTime.now().microsecondsSinceEpoch;
      final encodedManifest = jsonEncode(manifest);
      await _journal(root, {
        'op': 'install',
        'id': id,
        'staging': p.basename(staging.path),
        'backup': backupName,
        'existed': existed,
        'marker': marker,
        'manifest': encodedManifest,
      });
      journaled = true;
      if (existed) await target.rename(p.join(root.path, backupName));
      await staging.rename(target.path);
      if (enabled && verifyUpdate != null) {
        // Keep the old DB marker until activation succeeds so recovery restores
        // the old directory after a crash or a cancelled candidate startup.
        operation?.endCommit();
        checkingCandidate = true;
        await verifyUpdate(TidePluginPackage(manifest, target));
        operation?.beginCommit();
      }
      await DBManager().savePlugin({
        'id': id,
        'name': manifest['name'],
        'version': manifest['version'],
        'description': manifest['description'] ?? '',
        'author': manifest['author'] ?? '',
        'manifest_json': encodedManifest,
        'enabled': enabled ? 1 : 0,
        'updated_at': marker,
      }, marketSource: marketSource);
      committed = true;
      if (customTheme ||
          (previous != null &&
              _hasInterfaceTheme(
                jsonDecode(previous['manifest_json'] as String),
              ))) {
        _interfaceThemeChanges.add(null);
      }
      // Retain a committed journal if backup cleanup fails.
      try {
        await _recover(root);
      } catch (_) {}
    } catch (_) {
      if (journaled && !committed) {
        try {
          if (checkingCandidate && stopCandidate != null) await stopCandidate();
        } finally {
          await _recover(root);
        }
      } else if (!journaled && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    } finally {
      operation?.endCommit();
    }
    return launch;
  });

  static int _launchOrder(Object? manifest) {
    final value = manifest is Map
        ? manifest[pluginLaunchEnabledOrderKey]
        : null;
    return value is int && value > 0 ? value : 0;
  }

  static bool _hasInterfaceTheme(Map<String, dynamic> manifest) {
    final appearance = manifest['appearance'];
    return appearance is Map && appearance.containsKey('interfaceTheme');
  }

  static int _themeOrder(Map<String, dynamic> manifest) {
    final order = manifest[pluginThemeOrderKey];
    return order is int && order > 0 ? order : 0;
  }

  static int _nextThemeOrder(List<Map<String, dynamic>> rows) {
    var order = DateTime.now().microsecondsSinceEpoch;
    for (final row in rows.where((row) => row['enabled'] == 1)) {
      final previous = _themeOrder(jsonDecode(row['manifest_json'] as String));
      if (previous >= order) order = previous + 1;
    }
    return order;
  }

  Future<TidePluginPackage?> interfaceThemePackage() => _transaction((
    root,
  ) async {
    final rows = await DBManager().queryPlugins();
    TidePluginPackage? selected;
    var order = -1;
    for (final row in rows.where((row) => row['enabled'] == 1)) {
      final manifest =
          jsonDecode(row['manifest_json'] as String) as Map<String, dynamic>;
      if (!_hasInterfaceTheme(manifest)) continue;
      final id = row['id'] as String;
      _checkId(id);
      final candidate = _themeOrder(manifest);
      if (candidate > order ||
          (candidate == order && id.compareTo(selected!.id) < 0)) {
        final directory = Directory(p.join(root.path, id));
        if (!await directory.exists()) continue;
        selected = TidePluginPackage(manifest, directory);
        order = candidate;
      }
    }
    return selected;
  });

  Future<TidePluginPackage?> launchAnimationPackage() => _transaction((
    root,
  ) async {
    final rows = await DBManager().queryPlugins();
    TidePluginPackage? selected;
    var selectedOrder = -1;
    for (final row in rows) {
      if (row['enabled'] != 1) continue;
      final manifest =
          jsonDecode(row['manifest_json'] as String) as Map<String, dynamic>;
      if (pluginLaunchDeclaration(manifest) == null) continue;
      final id = row['id'] as String;
      _checkId(id);
      final order = _launchOrder(manifest);
      if (selected == null ||
          order > selectedOrder ||
          (order == selectedOrder && id.compareTo(selected.id) < 0)) {
        selected = TidePluginPackage(
          manifest,
          Directory(p.join(root.path, id)),
        );
        selectedOrder = order;
      }
    }
    return selected;
  });

  Future<void> setEnabled(String id, bool enabled) => _transaction((_) async {
    _checkId(id);
    if (!enabled) await PluginCoordinator.invalidate(id);
    final db = DBManager();
    final rows = await db.queryPlugins();
    final row = rows.where((row) => row['id'] == id).firstOrNull;
    String? manifestJson;
    var changesTheme = false;
    if (row != null) {
      final manifest =
          jsonDecode(row['manifest_json'] as String) as Map<String, dynamic>;
      if (pluginLaunchDeclaration(manifest) != null) {
        if (!enabled) {
          manifest.remove(pluginLaunchEnabledOrderKey);
        } else if (_launchOrder(manifest) == 0) {
          var order = DateTime.now().microsecondsSinceEpoch;
          for (final other in rows.where((row) => row['enabled'] == 1)) {
            final previous = _launchOrder(
              jsonDecode(other['manifest_json'] as String),
            );
            if (previous >= order) order = previous + 1;
          }
          manifest[pluginLaunchEnabledOrderKey] = order;
        }
        manifestJson = jsonEncode(manifest);
      }
      if (_hasInterfaceTheme(manifest)) {
        changesTheme = true;
        if (enabled && row['enabled'] != 1) {
          manifest[pluginThemeOrderKey] = _nextThemeOrder(rows);
        } else if (!enabled) {
          manifest.remove(pluginThemeOrderKey);
        }
        manifestJson = jsonEncode(manifest);
      }
    }
    await db.setPluginEnabled(id, enabled, manifestJson: manifestJson);
    if (changesTheme) _interfaceThemeChanges.add(null);
  });
  Future<void> delete(String id) => _transaction((root) async {
    _checkId(id);
    await PluginCoordinator.invalidate(id);
    await _journal(root, {'op': 'delete', 'id': id});
    await _recover(root);
    _interfaceThemeChanges.add(null);
  });
  String _configKey(String id) => 'plugin_config_$id';
  Future<void> saveConfig(String id, Map<String, dynamic> values) =>
      _transaction((_) async {
        _checkId(id);
        await PluginCoordinator.invalidate(id);
        await _secureStorage.write(
          key: _configKey(id),
          value: jsonEncode(values),
        );
      });
  Future<Map<String, dynamic>> loadConfig(String id) async {
    _checkId(id);
    final value = await _secureStorage.read(key: _configKey(id));
    if (value == null || value.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<TidePluginPackage> packageFor(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    _checkId(id);
    return TidePluginPackage(
      jsonDecode(row['manifest_json'] as String) as Map<String, dynamic>,
      Directory(p.join((await _root).path, id)),
    );
  }
}

void _decodeArchiveWorker(List<dynamic> args) {
  final port = args[0] as SendPort;
  try {
    port.send(PluginArchive.decode(args[1] as List<int>));
  } catch (error, stack) {
    port.send([error.toString(), stack.toString()]);
  }
}

Future<PluginArchive> _decodeArchive(
  List<int> bytes,
  PluginOperation? operation,
) async {
  if (operation == null) return Isolate.run(() => PluginArchive.decode(bytes));
  operation.check();
  final port = ReceivePort();
  final result = Completer<PluginArchive>();
  Isolate? worker;
  final subscription = port.listen((message) {
    if (result.isCompleted) return;
    if (message is PluginArchive) {
      result.complete(message);
    } else {
      result.completeError(
        FormatException(
          message is List ? message.first.toString() : '插件解压进程提前结束',
        ),
      );
    }
  });
  final detach = operation.listen(() {
    worker?.kill(priority: Isolate.immediate);
    // The result listener is attached below before any cancellation can fire.
    if (!result.isCompleted)
      result.completeError(const PluginOperationCancelled());
  });
  try {
    final spawning =
        Isolate.spawn<List<dynamic>>(
          _decodeArchiveWorker,
          [port.sendPort, bytes],
          onError: port.sendPort,
          onExit: port.sendPort,
        ).then((isolate) {
          worker = isolate;
          if (operation.cancelled) isolate.kill(priority: Isolate.immediate);
        });
    final values = await Future.wait<dynamic>([
      spawning,
      result.future,
    ], eagerError: true);
    operation.check();
    return values[1] as PluginArchive;
  } finally {
    detach();
    worker?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    port.close();
  }
}
