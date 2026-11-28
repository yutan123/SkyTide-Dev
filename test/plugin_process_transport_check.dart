import 'dart:async';
import 'dart:convert';
import 'package:skytide/plugin_process_transport.dart';

// Exercises the production session/RPC state machine with an injected IPC edge.
// Does not execute Kotlin, Binder, FlutterEngine or QuickJS.
class Bridge implements PluginProcessBridge {
  late void Function(String) receive;
  final messages = <Map<String, dynamic>>[];
  bool failOpen = false;
  bool failSend = false;
  bool autoReady = true;
  @override
  void setReceiver(void Function(String) receiver) => receive = receiver;
  @override
  Future<void> send(String method, String payload) async {
    final value = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    messages.add({...value, 'methodName': method});
    if (method == 'open') {
      if (failOpen) throw StateError('bind failed');
      if (autoReady) event(value['token'] as String, {'type': 'ready'});
    }
    if (method == 'send' && failSend) throw StateError('binder send failed');
  }

  void event(String token, Map<String, dynamic> value) =>
      receive(jsonEncode({...value, 'token': token}));
  List<Map<String, dynamic>> get opens =>
      messages.where((m) => m['methodName'] == 'open').toList();
  List<Map<String, dynamic>> get calls =>
      messages.where((m) => m['op'] == 'call').toList();
}

int checks = 0;
void check(bool value) {
  if (!value) throw StateError('Check ${checks + 1} failed');
  checks++;
}

Future<void> rejected(Future<dynamic> future, {String? contains}) async {
  try {
    await future;
  } catch (error) {
    if (contains != null) check(error.toString().contains(contains));
    checks++;
    return;
  }
  throw StateError('Expected rejection');
}

Future<void> turn() => Future<void>.delayed(Duration.zero);

Future<void> main() async {
  final bridge = Bridge();
  var closed = 0;
  final a = PluginProcessTransport(
    (_, args) async {
      if (args['invalid'] == true) return Object();
      if (args['large'] == true) return 'x' * (1024 * 1024);
      return args;
    },
    bridge: bridge,
    onClosed: () => closed++,
  );
  final b = PluginProcessTransport((_, args) async => args, bridge: bridge);
  await a.start('sdk', 'script', {});
  await b.start('sdk', 'script', {});
  final ta = bridge.opens[0]['token'] as String;
  final tb = bridge.opens[1]['token'] as String;
  check(ta != tb && !a.closed && !b.closed);
  await rejected(a.start('', '', {}));
  final pending = List.generate(32, (i) => a.call('tool', 'echo', i));
  await rejected(a.call('tool', 'overflow', {}));
  for (final request in bridge.calls.reversed) {
    bridge.event(ta, {
      'type': 'result',
      'id': request['id'],
      'value': request['payload'],
    });
  }
  check(
    (await Future.wait(pending)).join(',') ==
        List.generate(32, (i) => i).join(','),
  );
  for (var i = 0; i < 40; i++) {
    await rejected(a.call('tool', 'bad', Object()));
  }
  check(!a.closed);
  await rejected(
    a.call('tool', 'oversized', 'x' * (8 * 1024 * 1024)),
    contains: 'IPC 消息过大',
  );
  check(!a.closed);

  final rejectedCall = a.call('event', 'hook', {});
  final pluginError = rejected(rejectedCall, contains: 'temporary API error');
  final rejectedId = bridge.calls.last['id'];
  final concurrentCall = a.call('tool', 'concurrent', {});
  final concurrentId = bridge.calls.last['id'];
  bridge.event(ta, {
    'type': 'result',
    'id': rejectedId,
    'error': 'temporary API error',
  });
  await pluginError;
  check(!a.closed && closed == 0);
  bridge.event(ta, {'type': 'result', 'id': concurrentId, 'value': 'ok'});
  check(await concurrentCall == 'ok');
  final nextCall = a.call('tool', 'afterError', {});
  bridge.event(ta, {
    'type': 'result',
    'id': bridge.calls.last['id'],
    'value': 'still running',
  });
  check(await nextCall == 'still running');

  for (final args in [
    {},
    {'invalid': true},
    {'large': true},
  ]) {
    bridge.event(ta, {
      'type': 'host',
      'id': 80 + args.length,
      'method': 'test',
      'args': args,
    });
    await turn();
    final reply = bridge.messages.lastWhere((m) => m['op'] == 'resolve');
    check(args.isEmpty ? reply['error'] == null : reply['error'] != null);
  }
  final dying = a.call('tool', 'waiting', {});
  final failure = rejected(dying, contains: 'native process exited');
  bridge.event(ta, {'type': 'fatal', 'error': 'native process exited'});
  await failure;
  check(a.closed && closed == 1 && !b.closed);
  a.close();
  check(closed == 1);
  final live = b.call('tool', 'alive', {});
  final request = bridge.calls.last;
  bridge.event(tb, {'type': 'result', 'id': request['id'], 'value': 'ok'});
  check(await live == 'ok');
  bridge.event(ta, {'type': 'ready'});
  check(a.closed);
  final toClose = b.call('tool', 'pending', {});
  final stopped = rejected(toClose);
  b.close();
  await stopped;
  await rejected(b.call('tool', 'closed', {}));
  final failingBridge = Bridge()..failOpen = true;
  final failing = PluginProcessTransport(
    (_, _) async => null,
    bridge: failingBridge,
  );
  await rejected(failing.start('', '', {}));
  check(failing.closed);
  final slowBridge = Bridge()..autoReady = false;
  final slow = PluginProcessTransport((_, _) async => null, bridge: slowBridge);
  final starting = rejected(slow.start('', '', {}));
  slow.close();
  await starting;
  check(slow.closed);

  final brokenBridge = Bridge();
  final broken = PluginProcessTransport(
    (_, _) async => null,
    bridge: brokenBridge,
  );
  await broken.start('', '', {});
  final interrupted = rejected(
    broken.call('tool', 'waiting', {}),
    contains: 'binder send failed',
  );
  brokenBridge.failSend = true;
  await rejected(
    broken.call('tool', 'cannotSend', {}),
    contains: 'binder send failed',
  );
  await interrupted;
  check(broken.closed);

  final timeout = PluginProcessTransport(
    (_, _) async => null,
    bridge: Bridge(),
    callTimeout: const Duration(milliseconds: 30),
  );
  await timeout.start('', '', {});
  await rejected(
    timeout.call('tool', 'hang', {}),
    contains: 'TimeoutException',
  );
  check(timeout.closed);
  await turn();
  print('Plugin process transport: $checks checks passed');
}
