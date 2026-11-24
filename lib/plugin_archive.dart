import 'plugin_interface_theme.dart';
import 'plugin_media_contract.dart';
import 'plugin_launch_spec.dart';
import 'dart:convert';
import 'plugin_worker_policy.dart';
import 'plugin_event_policy.dart';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'plugin_contract.dart';
import 'plugin_message_action.dart';
import 'plugin_connections.dart';

/// Pure Dart package validation, shared by installation and package checks.
class PluginArchive {
  static const maxCompressed = 256 * 1024 * 1024;
  static const maxExpanded = 512 * 1024 * 1024;
  static const maxEntries = 10000;
  final Map<String, dynamic> manifest;
  final Map<String, List<int>> files;
  PluginArchive._(this.manifest, this.files);

  static String marketId(String id) =>
      id.toLowerCase().startsWith('tidebot') ? 'skytide${id.substring(7)}' : id;

  static PluginArchive decode(
    List<int> bytes, {
    bool githubWrapper = false,
    String? expectedMarketId,
  }) {
    if (bytes.length > maxCompressed) {
      throw const FormatException('插件包超过 256 MiB 限制');
    }
    try {
      final directory = ZipDirectory()..read(InputMemoryStream(bytes));
      if (directory.filePosition < 0 ||
          directory.numberOfThisDisk != 0 ||
          directory.diskWithTheStartOfTheCentralDirectory != 0 ||
          directory.fileHeaders.length !=
              directory.totalCentralDirectoryEntries ||
          directory.fileHeaders.length > maxEntries) {
        throw const FormatException('ZIP 目录无效、分卷或条目超过 10000');
      }
      final entries = <String, ZipFileHeader>{};
      final directories = <String>{};
      var expanded = 0;
      // Inspect every central-directory entry before decompressing any content.
      // ZipDecoder merges duplicate names, and its verify flag does not check CRC.
      var central = directory.centralDirectoryOffset;
      final centralEnd = central + directory.centralDirectorySize;
      int word(int offset) => bytes[offset] | (bytes[offset + 1] << 8);
      for (final header in directory.fileHeaders) {
        // The archive library exposes the central name even on the local entry.
        final local = header.localHeaderOffset;
        if (central < 0 ||
            central + 46 > centralEnd ||
            centralEnd > bytes.length ||
            local < 0 ||
            local + 30 > directory.centralDirectoryOffset ||
            word(local) != 0x4b50 ||
            word(local + 2) != 0x0403) {
          throw const FormatException('ZIP 文件头无效');
        }
        final nameLength = word(central + 28);
        if (nameLength != word(local + 26) ||
            central + 46 + nameLength > centralEnd ||
            local + 30 + nameLength > directory.centralDirectoryOffset) {
          throw const FormatException('ZIP 文件名记录不一致');
        }
        for (var i = 0; i < nameLength; i++) {
          if (bytes[central + 46 + i] != bytes[local + 30 + i]) {
            throw const FormatException('ZIP 文件名记录不一致');
          }
        }
        central += 46 + nameLength + word(central + 30) + word(central + 32);
        final file = header.file;
        final raw = header.filename.replaceAll('\\', '/');
        final name = p.posix.normalize(raw);
        final mode = (header.externalFileAttributes >> 16) & 0xf000;
        if (file == null ||
            !_safeRelative(raw) ||
            file.filename.replaceAll('\\', '/') != raw ||
            (mode != 0 && mode != 0x8000 && mode != 0x4000) ||
            header.generalPurposeBitFlag & 1 != 0 ||
            !{0, 8}.contains(header.compressionMethod)) {
          throw const FormatException('ZIP 路径、文件类型、加密或压缩方式不支持');
        }
        final isDirectory = raw.endsWith('/') || mode == 0x4000;
        if (entries.containsKey(name) || directories.contains(name)) {
          throw const FormatException('ZIP 包含重复路径');
        }
        if (isDirectory) {
          if (header.uncompressedSize != 0) {
            throw const FormatException('ZIP 目录不能包含文件数据');
          }
          directories.add(name);
        } else {
          expanded += header.uncompressedSize;
          if (header.uncompressedSize < 0 || expanded > maxExpanded) {
            throw const FormatException('插件解压后超过 512 MiB 限制');
          }
          entries[name] = header;
        }
      }
      for (final name in [...entries.keys, ...directories]) {
        var parent = p.posix.dirname(name);
        while (parent != '.') {
          if (entries.containsKey(parent)) {
            throw const FormatException('ZIP 文件与目录路径冲突');
          }
          parent = p.posix.dirname(parent);
        }
      }
      final files = <String, List<int>>{};
      for (final entry in entries.entries) {
        final output = OutputMemoryStream();
        entry.value.file!.decompress(output);
        final content = output.getBytes();
        if (content.length != entry.value.uncompressedSize ||
            getCrc32(content) != entry.value.crc32) {
          throw const FormatException('ZIP 文件长度或 CRC 校验失败');
        }
        files[entry.key] = content;
      }
      if (githubWrapper &&
          !files.containsKey('manifest.json') &&
          files.isNotEmpty) {
        final root = files.keys.first.split('/').first;
        final prefix = '$root/';
        if (!files.keys.every((name) => name.startsWith(prefix)) ||
            !files.containsKey('${prefix}manifest.json')) {
          throw const FormatException('仓库根目录缺少插件清单');
        }
        final stripped = {
          for (final entry in files.entries)
            entry.key.substring(prefix.length): entry.value,
        };
        files
          ..clear()
          ..addAll(stripped);
      }
      final manifestBytes = files['manifest.json'];
      if (manifestBytes == null || manifestBytes.length > 1024 * 1024) {
        throw const FormatException('缺少根目录 manifest.json 或清单超过 1 MB');
      }
      final raw = jsonDecode(utf8.decode(manifestBytes));
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('manifest.json 必须是 JSON 对象');
      }
      final manifest = Map<String, dynamic>.from(raw);
      final originalId = manifest['id'];
      if (expectedMarketId != null &&
          originalId is String &&
          originalId != expectedMarketId &&
          marketId(originalId) == expectedMarketId) {
        manifest['id'] = expectedMarketId;
        files['manifest.json'] = utf8.encode(jsonEncode(manifest));
      }
      if (manifest['config'] == null &&
          files.containsKey('config.schema.json')) {
        if (files['config.schema.json']!.length > 1024 * 1024) {
          throw const FormatException('配置 Schema 超过 1 MB');
        }
        manifest['config'] = jsonDecode(
          utf8.decode(files['config.schema.json']!),
        );
      }
      validateManifest(manifest, files);
      return PluginArchive._(manifest, files);
    } on FormatException {
      rethrow;
    } on RangeError catch (error) {
      throw FormatException('ZIP 数据被截断：$error');
    }
  }

  static void validateManifest(
    Map<String, dynamic> m,
    Map<String, List<int>> files,
  ) {
    final id = m['id'];
    final version = m['version'];
    final name = m['name'];
    final entry = m['entry'];
    final launch = PluginLaunchSpec.fromManifest(m);
    launch?.validateFiles(files);
    final interfaceTheme = PluginInterfaceTheme.fromManifest(m);
    interfaceTheme?.validateFiles(files);
    final hasProgram =
        entry is String && _safeRelative(entry) && files.containsKey(entry);
    final appearanceOnly =
        !m.containsKey('entry') && (launch != null || interfaceTheme != null);
    if (appearanceOnly &&
        m.keys.any(
          (key) => !const {
            'id',
            'name',
            'version',
            'description',
            'author',
            'icon',
            'apiVersion',
            'appearance',
            'requiredCapabilities',
          }.contains(key),
        )) {
      throw const FormatException('无 entry 的外观插件只允许声明外观和元数据');
    }
    final idPattern = RegExp(
      r'^skytide[a-z0-9_.-]{0,57}$',
      caseSensitive: false,
    );
    if (id is! String ||
        !idPattern.hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        version is! String ||
        !RegExp(
          r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
        ).hasMatch(version) ||
        (!hasProgram && !appearanceOnly)) {
      throw const FormatException('插件 manifest 的 id/name/version/entry 无效');
    }
    if (!{'script', 'commonjs'}.contains(m['entryFormat'] ?? 'script'))
      throw const FormatException('entryFormat 必须为 script/commonjs');
    for (final field in ['modules', 'resources']) {
      final paths = m[field] ?? [];
      if (paths is! List ||
          paths.length > 255 ||
          paths.toSet().length != paths.length)
        throw FormatException('$field 必须为不重复的包内路径数组，最多 255 项');
      var total = files[entry]?.length ?? 0;
      for (final path in paths) {
        if (path is! String || !_safeRelative(path) || !files.containsKey(path))
          throw FormatException('$field 路径无效或不存在');
        if (field == 'modules') {
          if ((!path.endsWith('.js') && !path.endsWith('.json')) ||
              files[path]!.length > 2 * 1024 * 1024)
            throw const FormatException('模块必须是 JS/JSON，单文件不超过 2 MiB');
          total += files[path]!.length;
        }
      }
      if (field == 'modules' && total > 3 * 1024 * 1024)
        throw const FormatException('入口与模块合计超过 3 MiB');
    }
    final icon = m['icon'];
    if (icon != null &&
        (icon is! String || !_safeRelative(icon) || !files.containsKey(icon))) {
      throw const FormatException('插件 icon 路径无效或文件不存在');
    }
    final ui = m['ui'];
    if (ui != null) {
      if (ui is! Map ||
          ui['entry'] is! String ||
          !_safeRelative(ui['entry'] as String) ||
          !files.containsKey(ui['entry'])) {
        throw const FormatException('插件 ui.entry 无效或文件不存在');
      }
    }
    if ((m['apiVersion'] ?? 1) != 1)
      throw const FormatException('不支持的 apiVersion');
    final requiredCapabilities = m['requiredCapabilities'] ?? [];
    if (requiredCapabilities is! List ||
        requiredCapabilities.any(
          (item) => !PluginContract.capabilities.contains(item),
        )) {
      throw const FormatException('插件要求当前宿主不支持的 requiredCapabilities');
    }
    if (entry is String &&
        (!entry.endsWith('.js') || files[entry]!.length > 2 * 1024 * 1024)) {
      throw const FormatException('entry 必须为不超过 2 MB 的 JS bundle');
    }
    for (final field in ['description', 'author']) {
      if (m[field] != null && m[field] is! String)
        throw FormatException('$field 必须是文本');
    }
    final config = m['config'];
    if (config != null) {
      if (config is! Map) throw const FormatException('config 必须为对象');
      PluginContract.schema(config);
    }
    final tools = m['tools'] ?? [];
    if (tools is! List || tools.length > 32)
      throw const FormatException('tools 必须为数组，最多 32 项');
    final names = <String>{};
    for (final tool in tools) {
      if (tool is! Map ||
          tool['name'] is! String ||
          !PluginContract.identifier.hasMatch(tool['name'] as String) ||
          !names.add(tool['name'] as String) ||
          tool['description'] is! String ||
          tool['parameters'] is! Map) {
        throw const FormatException('工具 name/description/parameters 无效或名称重复');
      }
      PluginContract.schema(tool['parameters'] as Map);
    }
    PluginMessageAction.parse(m['messageActions']);
    final commands = PluginEventPolicy.commands(m['commands']);
    PluginEventPolicy.priority(m['eventPriority']);
    if (commands.isNotEmpty &&
        !(m['permissions'] is List &&
            (m['permissions'] as List).contains('chat.read')))
      throw const FormatException('commands 需要 chat.read 权限');
    final workers = PluginWorkerPolicy.validate(m['workers']);
    if (workers.isNotEmpty &&
        !(m['permissions'] is List &&
            (m['permissions'] as List).contains('workers'))) {
      throw const FormatException('workers 需要 workers 权限');
    }
    final hooks = m['hooks'] ?? [];
    if (hooks is! List ||
        hooks.any((hook) => !PluginContract.hooks.contains(hook))) {
      throw const FormatException('hooks 包含不支持的事件');
    }
    final systemPermissions = m['systemPermissions'];
    if (m.containsKey('systemPermissions') &&
        (systemPermissions is! List ||
            systemPermissions.any(
              (key) => !const {
                'overlay',
                'location',
                'microphone',
                'photos',
                'videos',
                'motion',
              }.contains(key),
            ))) {
      throw const FormatException('systemPermissions 包含不支持的系统权限');
    }
    final permissions = m['permissions'] ?? [];
    if (permissions is! List ||
        permissions.any(
          (item) => !PluginMediaContract.permissions.contains(item),
        )) {
      throw const FormatException('permissions 包含不支持的权限');
    }
    final endpoints = m['networkEndpoints'] ?? [];
    if (endpoints is! List ||
        endpoints.length > 64 ||
        endpoints.any((e) => !PluginConnectionPolicy.validEndpoint(e))) {
      throw const FormatException('networkEndpoints 必须为最多 64 个精确协议、主机和端口地址');
    }
    final origins = m['networkOrigins'] ?? [];
    if (origins is! List) throw const FormatException('networkOrigins 必须为数组');
    for (final origin in origins) {
      if (!PluginMediaContract.validOrigin(origin)) {
        throw const FormatException(
          'networkOrigins 必须为 HTTPS origin、https://*.example.com 或 *',
        );
      }
    }
    if (ui is Map) {
      final content = files[ui['entry']]!;
      if (content.length > 1024 * 1024)
        throw const FormatException('UI 布局超过 1 MB');
      final type = ui['type'] ?? 'declarative';
      if (!{'declarative', 'web'}.contains(type))
        throw const FormatException('ui.type 必须为 declarative/web');
      if (type == 'web') {
        if (!(ui['entry'] as String).endsWith('.html'))
          throw const FormatException('网页入口必须为 .html');
      } else {
        final layout = jsonDecode(utf8.decode(content));
        if (layout is! Map)
          throw const FormatException('ui.entry 必须是声明式 JSON 对象');
        PluginContract.layout(layout);
      }
    }
    // Reject file/directory conflicts before any filesystem mutation.
    for (final name in files.keys) {
      var parent = p.posix.dirname(name);
      while (parent != '.') {
        if (files.containsKey(parent))
          throw const FormatException('插件文件与目录路径冲突');
        parent = p.posix.dirname(parent);
      }
    }
  }

  static bool _safeRelative(String path) {
    final normalized = p.posix.normalize(path.replaceAll('\\', '/'));
    return normalized.isNotEmpty &&
        normalized != '.' &&
        !normalized.contains(':') &&
        !normalized.contains('\u0000') &&
        !normalized.startsWith('/') &&
        normalized != '..' &&
        !normalized.startsWith('../');
  }
}
