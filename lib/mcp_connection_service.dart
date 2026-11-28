import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'db.dart';
import 'skill_runtime.dart';

class McpConnectionService {
  McpConnectionService._();

  static final instance = McpConnectionService._();
  bool _running = false;

  /// Discover without executing any tools or enabling new tools.
  Future<bool> discover(
    Map<String, dynamic> server,
    Future<void> Function() guard,
  ) async {
    final id = server['id'] as String;
    final url = server['url'] as String;
    final stored = await const FlutterSecureStorage().read(key: 'mcp_headers_$id');
    final client = McpClient(
      url: url,
      headers: stored == null
          ? const {}
          : Map<String, String>.from(jsonDecode(stored) as Map),
    );
    try {
      await guard();
      await client.initialize();
      final tools = await client.listTools();
      await guard();
      await DBManager().saveMcpTools(id, tools, requireApproval: true, expectedUrl: url);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await client.close();
      } catch (_) {
        // Session cleanup is best effort.
      } finally {
        client.dispose();
      }
    }
  }

  Future<void> connectAuto() async {
    if (_running) return;
    _running = true;
    try {
      final servers = await DBManager().queryMcpServers();
      await Future.wait(
        servers
            .where((server) =>
                server['enabled'] == 1 && server['auto_connect'] == 1)
            .map(_connectOne),
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _connectOne(Map<String, dynamic> server) async {
    final id = server['id']?.toString() ?? '';
    final url = server['url']?.toString() ?? '';
    if (id.isEmpty || url.isEmpty) return;
    await DBManager().updateMcpStatus(id, 'connecting');
    try {
      final stored =
          await const FlutterSecureStorage().read(key: 'mcp_headers_$id');
      final headers = <String, String>{};
      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            headers[key.toString()] = value.toString();
          });
        }
      }
      final timeoutMs = (server['timeout_ms'] as num?)?.toInt() ?? 20000;
      final client = McpClient(
        url: url,
        headers: headers,
        timeout: Duration(milliseconds: timeoutMs),
      );
      try {
        final initialized = await client.initialize();
        final tools = await client.listTools();
        final resources = await client.listResourcesSafe();
        final prompts = await client.listPromptsSafe();
        await DBManager().saveMcpTools(id, tools);
        await DBManager().saveMcpMetadata(
          id,
          resources: resources,
          prompts: prompts,
          serviceDescription: initialized['instructions']?.toString() ?? '',
        );
      } finally {
        try {
          await client.close();
        } catch (_) {
          // A failed session DELETE must not invalidate discovered tools.
        } finally {
          client.dispose();
        }
      }
    } catch (error) {
      await DBManager().updateMcpStatus(
        id,
        'error',
        McpClient.describeError(error),
      );
    }
  }
}
