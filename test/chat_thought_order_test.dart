import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skytide/ai.dart';
import 'package:skytide/db.dart';

import 'support/sqlite_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = DBManager();
  late SqliteBridge sqlite;
  final previews = <String>[];
  final progress = <Map<String, dynamic>>[];
  final requests = <Map<String, dynamic>>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqlite = SqliteBridge();
    await sqlite.open();
    previews.clear();
    progress.clear();
    requests.clear();
    await db.insertBot({
      'id': 'thought-bot',
      'name': '测试角色',
      'chat_model': 'thought-provider',
    });
    await db.setKV('inner_thought_enabled', 'true');
    await db.setKV(
      'provider_list',
      jsonEncode([
        {
          'id': 'thought-provider',
          'name': 'test',
          'url': 'https://thought.invalid/v1',
          'key': 'test-only',
          'model': 'thought-model',
        },
      ]),
    );
  });

  tearDown(() async => sqlite.close());

  Future<Map<String, dynamic>> send(
    List<String> chunks, {
    bool callTool = false,
  }) => http.runWithClient(
    () => AIManager().sendMessage(
      botId: 'thought-bot',
      text: '你好',
      enableAutoSummary: false,
      skipLifeState: true,
      showInnerThoughtFirst: true,
      onDelta: previews.add,
      onToolProgress: progress.add,
    ),
    () => MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      final firstToolRound = callTool && requests.length == 1;
      String event(Map<String, dynamic> delta, [String? finish]) =>
          'data: ${jsonEncode({
            'choices': [
              {'delta': delta, 'finish_reason': finish},
            ],
          })}\n\n';
      final stream = [
        event({'reasoning_content': '不得进入独白的模型推理'}),
        if (firstToolRound)
          event({
            'content': '先查一下。<inner_thought>工具阶段的独白</inner_thought>',
            'tool_calls': [
              {
                'index': 0,
                'id': 'call-1',
                'type': 'function',
                'function': {
                  'name': 'inspect_image',
                  'arguments': jsonEncode({'image_number': 999}),
                },
              },
            ],
          })
        else
          for (final chunk in chunks) event({'content': chunk}),
        event({}, firstToolRound ? 'tool_calls' : 'stop'),
        'data: [DONE]\n\n',
      ].join();
      return http.Response(
        stream,
        200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
    }),
  );

  List<(Object?, Object?)> timeline(Map<String, dynamic> result) {
    expect(result['success'], isTrue, reason: '$result');
    return [
      for (final row in (result['messages'] as List).cast<Map>())
        (row['type'], row['content']),
    ];
  }

  test('body received before a split thought never previews first', () async {
    final result = await send([
      '正文开头',
      '<inner_',
      'thought>此刻很开心',
      '</inner_thought>和后半句。',
      '第二句。',
    ]);
    expect(previews, isEmpty);
    expect(requests.single['stream'], isTrue);
    expect(timeline(result), [
      ('inner_thought', '此刻很开心'),
      ('text', '正文开头和后半句。'),
      ('text', '第二句。'),
    ]);
  });

  test('missing thought returns body without an empty thought row', () async {
    final result = await send(['只有正文。']);
    expect(previews, isEmpty);
    expect(timeline(result), [('text', '只有正文。')]);
  });

  test('disabled thoughts still allow live body previews', () async {
    await db.setKV('inner_thought_enabled', 'false');
    final result = await send(['第一段', '<inner_thought>隐藏</inner_thought>。']);
    expect(previews.first, '第一段');
    expect(previews.join(), '第一段。');
    expect(timeline(result), [('text', '第一段。')]);
  });

  test(
    'tool rounds keep SSE and only display the final thought and body',
    () async {
      final result = await send([
        '工具完成后的正文。',
        '<inner_thought>最终的独白</inner_thought>',
      ], callTool: true);
      expect(requests.map((request) => request['stream']), [true, true]);
      expect(previews, isEmpty);
      expect(progress, isEmpty);
      expect(timeline(result), [
        ('inner_thought', '最终的独白'),
        ('text', '工具完成后的正文。'),
      ]);
    },
  );
}
