import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skytide/db.dart';
import 'package:skytide/platform_editor.dart';

import 'support/sqlite_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = DBManager();
  late SqliteBridge sqlite;
  late PlatformEditor editor;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqlite = SqliteBridge();
    await sqlite.open();
    await (await db.database).insert('bots', {'id': 'me', 'name': 'Me'});
    await (await db.database).insert('bots', {'id': 'other', 'name': 'Other'});
    editor = PlatformEditor(
      available: () => true,
      form: (_, _, _, _) async => {},
    );
  });
  tearDown(() async => sqlite.close());

  test(
    'cancellation, another in-flight request, lost foreground and revoked caller do not write',
    () async {
      final started = Completer<void>();
      final selection = Completer<Map<String, Object?>?>();
      var foreground = true;
      editor = PlatformEditor(
        available: () => foreground,
        form: (_, _, _, _) {
          started.complete();
          return selection.future;
        },
      );
      final first = editor.call(
        'robot.update',
        {'name': 'Changed'},
        source: 'bot',
        robotId: 'me',
      );
      await started.future;
      expect(
        (await editor.call('providers.list', {}, source: 'plugin'))['ok'],
        false,
      );
      foreground = false;
      selection.complete({});
      expect((await first)['ok'], false);
      expect(
        (await editor.call(
          'robot.update',
          {'name': 'Changed'},
          source: 'bot',
          robotId: 'me',
        ))['ok'],
        false,
      );
      editor = PlatformEditor(
        available: () => true,
        form: (_, _, _, _) async => null,
      );
      expect(
        (await editor.call(
          'robot.update',
          {'name': 'Changed'},
          source: 'bot',
          robotId: 'me',
        ))['ok'],
        false,
      );
      var checks = 0;
      editor = PlatformEditor(
        available: () => true,
        form: (_, _, _, _) async => {},
      );
      expect(
        (await editor.call(
          'robot.update',
          {'name': 'Changed'},
          source: 'plugin',
          robotId: 'me',
          check: () async {
            if (++checks > 1) throw StateError('revoked');
          },
        ))['ok'],
        false,
      );
      expect((await db.getBotById('me'))?['name'], 'Me');
    },
  );

  test(
    'robot cannot redirect its changes; world book honors enable and ownership',
    () async {
      final changed = await editor.call(
        'robot.update',
        {
          'robotId': 'other',
          'name': 'Changed',
          'personality': 'Curious',
          'speakingStyle': 'Brief',
        },
        robotId: 'me',
        source: 'bot',
      );
      expect(changed['ok'], true);
      expect((await db.getBotById('me'))?['desc'], 'Curious');
      expect((await db.getBotById('me'))?['prompt'], 'Brief');
      expect((await db.getBotById('other'))?['name'], 'Other');
      final add = await editor.call(
        'worldBook.add',
        {
          'content': 'Do not share',
          'category': '规则',
          'enabled': false,
          'keywords': ['privacy'],
        },
        robotId: 'other',
        source: 'bot',
      );
      expect(add['ok'], true);
      final id = add['id'];
      expect(await db.queryMemories('other'), isEmpty);
      expect(
        (await db.queryMemories('other', includeDisabled: true)).single['id'],
        id,
      );
      expect(
        (await editor.call(
          'worldBook.update',
          {'id': id, 'enabled': true},
          robotId: 'me',
          source: 'bot',
        ))['ok'],
        false,
      );
      expect(
        (await editor.call(
          'worldBook.update',
          {'id': id, 'enabled': true},
          robotId: 'other',
          source: 'bot',
        ))['ok'],
        true,
      );
      expect((await db.queryMemories('other')).single['id'], id);
    },
  );

  test(
    'provider needs a native credential, masks reads and stores no plaintext in SQLite',
    () async {
      const key = 'abc-private-secret-xyz';
      editor = PlatformEditor(
        available: () => true,
        form: (_, _, _, fields) async {
          if (fields.isEmpty) return {};
          expect(fields.single.type, 'secret');
          return {'credential': key};
        },
      );
      final add = await editor.call('providers.add', {
        'type': 'chat',
        'name': 'Example',
        'url': 'https://example.invalid/v1',
        'model': 'demo',
      }, source: 'bot');
      expect(add['ok'], true);
      expect(jsonEncode(add), isNot(contains(key)));
      final list = await editor.call('providers.list', {}, source: 'bot');
      expect((list['providers'] as List).single['maskedKey'], 'abc******xyz');
      expect(PlatformEditor.maskKey('short'), '********');
      expect(
        jsonEncode(
          await sqlite.execute(
            "SELECT value FROM kv_store WHERE key='provider_list'",
          ),
        ),
        isNot(contains(key)),
      );
      final wrong = await editor.call('providers.update', {
        'type': 'chat',
        'id': add['id'],
        'url': 'https://other.invalid/v1',
      }, source: 'bot');
      expect(wrong['ok'], false);
      expect(
        (await db.queryChatProviders()).single['base_url'],
        'https://example.invalid/v1',
      );
      expect(
        (await editor.call('providers.update', {
          'type': 'chat',
          'id': add['id'],
          'key': key,
        }, source: 'plugin'))['ok'],
        false,
      );
    },
  );

  test(
    'generic requests accept typed inputs and reject secret fields',
    () async {
      var count = 0;
      editor = PlatformEditor(
        available: () => true,
        form: (_, _, message, fields) async {
          count++;
          expect(message, contains('不要在这里输入密码'));
          expect(fields.single.options, ['A', 'B']);
          return {
            'choices': ['B'],
          };
        },
      );
      final result = await editor.call('user.request', {
        'title': 'Question',
        'message': 'Choose',
        'fields': [
          {
            'id': 'choices',
            'label': 'Items',
            'type': 'multi',
            'options': ['A', 'B'],
          },
        ],
      }, source: 'plugin');
      expect(result['values'], {
        'choices': ['B'],
      });
      expect(
        (await editor.call('user.request', {
          'title': 'Question',
          'message': 'Choose',
          'fields': [
            {'id': 'secret', 'label': 'Secret', 'type': 'secret'},
          ],
        }, source: 'bot'))['ok'],
        false,
      );
      expect(count, 1);
    },
  );

  test(
    'sticker state, paused tasks and proactive settings are honored',
    () async {
      await db.insertSticker({
        'id': 's',
        'emotion': 'happy',
        'file_path': '/unused',
        'created_at': 1,
      });
      expect(
        (await editor.call('stickers.update', {
          'id': 's',
          'enabled': false,
          'category': 'joy',
        }, source: 'plugin'))['ok'],
        true,
      );
      expect(await db.queryStickers(), isEmpty);
      expect(
        (await db.queryStickers(includeDisabled: true)).single['emotion'],
        'joy',
      );
      final args = {
        'title': 'Reminder',
        'runAt': '2099-01-01T10:00:00',
        'enabled': false,
      };
      expect(
        (await editor.call(
          'tasks.add',
          args,
          robotId: 'me',
          source: 'bot',
        ))['ok'],
        true,
      );
      expect(
        (await editor.call(
          'tasks.add',
          args,
          robotId: 'me',
          source: 'bot',
        ))['duplicate'],
        true,
      );
      expect((await db.querySchedules('me')).single['status'], 'paused');
      expect(
        await db.dueFutureTasks(DateTime(2100).millisecondsSinceEpoch),
        isEmpty,
      );
      expect(
        (await editor.call('proactive.get', {}, source: 'plugin'))['enabled'],
        true,
      );
      expect(
        (await editor.call('proactive.update', {
          'enabled': false,
        }, source: 'plugin'))['enabled'],
        false,
      );
      expect(await db.getKV('proactive_reply'), 'false');
      expect(
        (await editor.call('proactive.update', {
          'enabled': true,
          'minMinutes': 100,
          'maxMinutes': 120,
        }, source: 'plugin'))['ok'],
        true,
      );
      final active = await editor.call('proactive.get', {}, source: 'plugin');
      expect(active, {
        'ok': true,
        'enabled': true,
        'minMinutes': 100,
        'maxMinutes': 120,
      });
    },
  );

  test('new MCP tools stay disabled on discovery and later refresh', () async {
    final added = await editor.call('mcp.add', {
      'name': 'Example',
      'url': 'https://example.invalid/mcp',
    }, source: 'plugin');
    expect(added['ok'], true);
    final id = added['id'] as String;
    await db.saveMcpTools(id, [
      {'name': 'one'},
    ]);
    expect((await db.queryMcpTools(id)).single['enabled'], 0);
    expect(
      (await editor.call('mcp.tool', {
        'id': id,
        'toolId': 'mcp_tool_${id}_one',
        'enabled': true,
      }, source: 'plugin'))['ok'],
      true,
    );
    await db.saveMcpTools(id, [
      {'name': 'one'},
      {'name': 'two'},
    ]);
    expect(
      {
        for (final tool in await db.queryMcpTools(id))
          tool['name']: tool['enabled'],
      },
      {'one': 1, 'two': 0},
    );
  });
}
