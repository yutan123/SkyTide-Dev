import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:skytide/db.dart';

/// Runs the application's actual sqflite SQL against isolated Python SQLite.
/// Starts empty so DBManager runs its real onCreate and onOpen migrations.
class SqliteBridge {
  static const _channel = MethodChannel('com.tekartik.sqflite');
  static const _paths = MethodChannel('plugins.flutter.io/path_provider');
  static const _secure = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late Process _process;
  late StreamIterator<String> _replies;
  late Directory _directory;

  Future<void> open() async {
    _directory = await Directory.systemTemp.createTemp('skytide-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_paths, (_) async => _directory.path);
    final secrets = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String?;
          switch (call.method) {
            case 'read':
              return secrets[key];
            case 'readAll':
              return Map<String, String>.of(secrets);
            case 'write':
              secrets[key!] = args['value'] as String;
              return null;
            case 'delete':
              secrets.remove(key);
              return null;
            default:
              throw StateError(
                'Unexpected secure storage method: ${call.method}',
              );
          }
        });
    _process = await Process.start(Platform.isWindows ? 'python' : 'python3', [
      '-u',
      '-c',
      r'''
import sys, json, sqlite3
sys.stdin.reconfigure(encoding='utf-8')
con = sqlite3.connect(':memory:', isolation_level=None)
con.row_factory = sqlite3.Row
for line in sys.stdin:
    try:
        req = json.loads(line)
        cursor = con.execute(req['sql'], req['args'])
        result = [dict(row) for row in cursor] if cursor.description else {
            'changes': cursor.rowcount, 'id': cursor.lastrowid
        }
        print(json.dumps({'result': result}), flush=True)
    except Exception as e:
        print(json.dumps({'error': str(e)}), flush=True)
''',
    ]);
    _process.stdin.encoding = utf8;
    _replies = StreamIterator(
      _process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    databaseFactory = databaseFactorySqflitePlugin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = call.arguments as Map? ?? {};
          switch (call.method) {
            case 'getDatabasesPath':
              return '/test/chat_cache';
            case 'openDatabase':
              return {'id': 1};
            case 'closeDatabase':
              return null;
            case 'query':
              return execute(
                args['sql'] as String,
                List<Object?>.from(args['arguments'] as List? ?? []),
              );
            case 'execute':
              await execute(
                args['sql'] as String,
                List<Object?>.from(args['arguments'] as List? ?? []),
              );
              return null;
            case 'insert':
            case 'update':
              final result =
                  await execute(
                        args['sql'] as String,
                        List<Object?>.from(args['arguments'] as List? ?? []),
                      )
                      as Map;
              if (call.method == 'insert') return result['id'];
              if (call.method == 'update') return result['changes'];
              return null;
            default:
              throw StateError('Unexpected SQLite method: ${call.method}');
          }
        });
  }

  Future<dynamic> execute(String sql, [List<Object?> args = const []]) async {
    _process.stdin.writeln(jsonEncode({'sql': sql, 'args': args}));
    if (!await _replies.moveNext()) throw StateError('SQLite process exited');
    final reply = jsonDecode(_replies.current) as Map;
    if (reply.containsKey('error')) {
      throw PlatformException(
        code: 'sqlite_error',
        message: reply['error'] as String,
      );
    }
    return reply['result'];
  }

  Future<void> close() async {
    await DBManager().close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_paths, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure, null);
    await _process.stdin.close();
    await _replies.cancel();
    await _process.exitCode;
    await _directory.delete(recursive: true);
  }
}
