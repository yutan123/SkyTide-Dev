import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skytide/ai.dart';
import 'package:skytide/db.dart';
import 'package:skytide/proactive_reply_engine.dart';
import 'package:skytide/proactive_request_gate.dart';
import 'package:skytide/video_request.dart';

import 'support/sqlite_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('skytide/proactive_reply');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final db = DBManager();
  late SqliteBridge sqlite;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'backup_model_bot': 'backup',
      'chat_model_bot': 'stale-primary',
      'stt_model_bot': 'stale-stt',
    });
    sqlite = SqliteBridge();
    await sqlite.open();
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await db.insertBot({'id': 'bot', 'name': '测试角色', 'chat_model': 'primary'});
    await db.setKV('life_schedule_enabled', 'false');
    await db.setKV(
      'provider_list',
      jsonEncode([
        for (final id in ['primary', 'backup'])
          {
            'id': id,
            'name': id,
            'url': 'https://$id.invalid/v1',
            'key': '$id-test-secret',
            'model': '$id-model',
            'thinking_mode': true,
            'reasoning_effort': 'high',
          },
      ]),
    );
  });

  tearDown(() async {
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
    await sqlite.close();
  });

  Future<Map> headless(Map<String, dynamic> args) async {
    final payload = const StandardMethodCodec().encodeMethodCall(
      MethodCall('generate', {'botId': 'bot', ...args}),
    );
    final result = await messenger.handlePlatformMessage(
      channel.name,
      payload,
      (_) {},
    );
    return const StandardMethodCodec().decodeEnvelope(result!) as Map;
  }

  test('foreground and every native reply use the same live model route', () async {
    final attempts = <String>[];
    await http.runWithClient(
      () async {
        // Register inside this zone because the channel retains its handler zone.
        startProactiveReplyEngine();
        final foreground = await AIManager().sendMessage(
          botId: 'bot',
          text: '你好',
          persistResponse: false,
          onDelta: (_) {},
        );
        expect(foreground['reply'], '你好。');
        final generation = jsonDecode(
          (await db.getKV(ProactiveRequestGate.key('bot')))!,
        )['generation'];
        final due = await db.getKV('proactive_due_at_bot');
        for (final args in [
          {'kind': 'proactive', 'generation': generation, 'due': due},
          {'kind': 'future', 'prompt': '定时任务测试'},
          {
            'kind': 'vitals',
            'reason': 'wake',
            'pending': jsonEncode([
              {'time': 1, 'content': '醒了吗'},
            ]),
          },
        ]) {
          attempts.clear();
          final result = await headless(args);
          expect(result['reply'], '你好。', reason: '$result');
          expect(
            attempts,
            ['primary:true', 'backup:true'].map(
              (attempt) => args['kind'] == 'proactive'
                  ? attempt
                  : attempt.replaceAll('true', 'false'),
            ),
          );
        }
        expect(await db.getKV('proactive_due_at_bot'), due);
        // A settings change is visible on the next background request.
        await db.updateBot('bot', {'chat_model': 'backup'});
        attempts.clear();
        expect(
          (await headless({'kind': 'future', 'prompt': '再次执行'}))['success'],
          isTrue,
        );
        expect(attempts, ['backup:false']);
      },
      () => MockClient((request) async {
        final id = request.url.host.split('.').first;
        final body = jsonDecode(request.body) as Map;
        expect(request.url.path, '/v1/chat/completions');
        expect(request.headers['authorization'], 'Bearer $id-test-secret');
        expect(body['model'], '$id-model');
        expect(body['reasoning_effort'], 'high');
        final stream = body['stream'] == true;
        attempts.add('$id:$stream');
        if (id == 'primary') {
          return http.Response(
            '{"error":{"message":"Insufficient balance"}}',
            402,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return stream
            ? http.Response(
                'data: {"choices":[{"delta":{"content":"你好。"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
                200,
                headers: {'content-type': 'text/event-stream; charset=utf-8'},
              )
            : http.Response(
                '{"choices":[{"message":{"content":"你好。"},"finish_reason":"stop"}]}',
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
      }),
    );
  });
  test('background reports the actual model when 402 has no backup', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('backup_model_bot');
    var attempts = 0;
    final result = await http.runWithClient(
      () async {
        startProactiveReplyEngine();
        return headless({'kind': 'future', 'prompt': '定时任务测试'});
      },
      () => MockClient((request) async {
        attempts++;
        expect(request.url.host, 'primary.invalid');
        return http.Response(
          '{"error":{"message":"Insufficient balance"}}',
          402,
        );
      }),
    );
    expect(attempts, 1);
    expect(result['error_code'], 402);
    expect(result['error'], contains('primary-model'));
    expect(result['error'], isNot(contains('test-secret')));
  });

  test(
    'backup-only and deleted-primary routes use the configured backup',
    () async {
      final hosts = <String>[];
      await http.runWithClient(
        () async {
          startProactiveReplyEngine();
          await db.updateBot('bot', {'chat_model': null});
          expect(await AIManager().getDailyQuote('bot'), '你好。');
          final foreground = await AIManager().sendMessage(
            botId: 'bot',
            text: '你好',
            persistResponse: false,
          );
          expect(foreground['reply'], '你好。');
          await db.updateBot('bot', {'chat_model': 'deleted'});
          final result = await headless({'kind': 'future', 'prompt': '定时任务测试'});
          expect(result['reply'], '你好。');
        },
        () => MockClient((request) async {
          hosts.add(request.url.host);
          expect(jsonDecode(request.body)['model'], 'backup-model');
          return http.Response(
            '{"choices":[{"message":{"content":"你好。"},"finish_reason":"stop"}]}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(hosts, List.filled(3, 'backup.invalid'));
      expect((await db.getBotById('bot'))?['chat_model'], 'deleted');
    },
  );

  test(
    'STT follows SQLite primary after a model change and honors clearing',
    () async {
      final temp = await Directory.systemTemp.createTemp('skytide-stt-route-');
      addTearDown(() => temp.delete(recursive: true));
      final audio = await File(
        '${temp.path}/sample.wav',
      ).writeAsBytes([1, 2, 3]);
      final hosts = <String>[];
      await http.runWithClient(
        () async {
          await db.updateBot('bot', {'stt_model': '__use_primary_stt__'});
          Future<String?> transcribe() =>
              AIManager().transcribeAudio(botId: 'bot', audioPath: audio.path);
          expect(await transcribe(), '你好。');
          await db.updateBot('bot', {'chat_model': 'backup'});
          expect(await transcribe(), '你好。');
          await db.updateBot('bot', {'stt_model': ''});
          expect(await transcribe(), isNull);
        },
        () => MockClient((request) async {
          hosts.add(request.url.host);
          final id = request.url.host.split('.').first;
          expect(jsonDecode(request.body)['model'], '$id-model');
          expect(request.headers['authorization'], 'Bearer $id-test-secret');
          return http.Response(
            '{"choices":[{"message":{"content":"你好。"}}]}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(hosts, ['primary.invalid', 'backup.invalid']);
    },
  );

  test(
    'advisor follows the active reply route unless separately configured',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await db.updateBot('bot', {'chat_model': null});
      await db.setKV('jarvis_enabled', 'true');
      final hosts = <String>[];
      await http.runWithClient(
        () async {
          Future<Map> send() => AIManager().sendMessage(
            botId: 'bot',
            text: '你好',
            persistResponse: false,
            useJarvis: true,
          );
          expect((await send())['reply'], '你好。');
          await prefs.setString('jarvis_model_bot', 'primary');
          expect((await send())['reply'], '你好。');
        },
        () => MockClient((request) async {
          final advisor = jsonDecode(request.body)['max_tokens'] == 1200;
          hosts.add('${request.url.host}:$advisor');
          return http.Response(
            '{"choices":[{"message":{"content":"你好。"},"finish_reason":"stop"}]}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(hosts, [
        'backup.invalid:true',
        'backup.invalid:false',
        'primary.invalid:true',
        'backup.invalid:false',
      ]);
    },
  );

  test(
    'video follows the database primary or keeps its explicit provider',
    () async {
      const ffprobe = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
      const events = MethodChannel('flutter.arthenica.com/ffmpeg_kit_event');
      messenger.setMockMethodCallHandler(events, (_) async => null);
      messenger.setMockMethodCallHandler(ffprobe, (call) async {
        return switch (call.method) {
          'mediaInformationSession' => {'sessionId': 1},
          'getMediaInformation' => {
            'streams': [
              {'codec_type': 'video', 'codec_name': 'h264'},
            ],
          },
          'isLTSBuild' => false,
          _ => null,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(events, null);
        messenger.setMockMethodCallHandler(ffprobe, null);
      });
      final temp = await Directory.systemTemp.createTemp(
        'skytide-video-route-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final video = await File(
        '${temp.path}/sample.mp4',
      ).writeAsBytes([1, 2, 3]);
      final hosts = <String>[];
      await http.runWithClient(
        () async {
          Future<String> describe(String id) => AIManager().describeVideoForBot(
            videoPath: video.path,
            providerId: id,
            botId: 'bot',
          );
          expect(await describe(primaryVideoModel), '测试结果');
          await db.updateBot('bot', {'chat_model': 'backup'});
          expect(await describe(primaryVideoModel), '测试结果');
          expect(await describe('primary'), '测试结果');
        },
        () => MockClient((request) async {
          hosts.add(request.url.host);
          final id = request.url.host.split('.').first;
          expect(jsonDecode(request.body)['model'], '$id-model');
          expect(request.headers['authorization'], 'Bearer $id-test-secret');
          return http.Response(
            '{"choices":[{"message":{"content":"测试结果"}}]}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(hosts, ['primary.invalid', 'backup.invalid', 'primary.invalid']);
    },
  );

  test('cleared video primary is not replaced by an old preference', () async {
    final prefs = await SharedPreferences.getInstance();
    // A valid provider in the stale mirror must not bring back a cleared model.
    await prefs.setString('chat_model_bot', 'backup');
    await db.updateBot('bot', {'chat_model': ''});
    await expectLater(
      AIManager().describeVideoForBot(
        videoPath: 'unused.mp4',
        providerId: primaryVideoModel,
        botId: 'bot',
      ),
      throwsA(isStateError.having((e) => e.message, 'message', '请先设置主聊天模型')),
    );
  });
}
