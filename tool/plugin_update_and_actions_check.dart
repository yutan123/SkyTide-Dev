import 'dart:io';

import 'package:skytide/plugin_install_journal.dart';
import 'package:skytide/plugin_market_version.dart';
import 'package:skytide/plugin_message_action.dart';
import 'package:skytide/plugin_operation.dart';

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void rejects(Object? value, void Function(Object?) parse) {
  try {
    parse(value);
  } on FormatException {
    return;
  }
  throw StateError('Accepted invalid value: $value');
}

Future<void> recoveryScenario({
  required bool committed,
  required bool swapped,
}) async {
  final root = await Directory.systemTemp.createTemp('plugin-update-check-');
  try {
    const id = 'skytide.test';
    const staging = '$id.installing-test';
    const backup = '$staging.backup';
    final rows = <Map<String, dynamic>>[
      {
        'id': id,
        'updated_at': committed ? 2 : 1,
        'manifest_json': committed ? 'new' : 'old',
      },
    ];
    final journal = PluginInstallJournal(
      queryRows: () async => rows,
      deleteRow: (_) async => throw StateError('unexpected delete'),
      deleteData: (_) async => throw StateError('unexpected delete'),
      invalidate: (_) async {},
    );
    final target = await Directory('${root.path}/$id').create();
    await File('${target.path}/main.js').writeAsString('old');
    final stage = await Directory('${root.path}/$staging').create();
    await File('${stage.path}/main.js').writeAsString('new');
    await journal.write(root, {
      'op': 'install',
      'id': id,
      'existed': true,
      'staging': staging,
      'backup': backup,
      'marker': 2,
      'manifest': 'new',
    });
    if (swapped) {
      await target.rename('${root.path}/$backup');
      await stage.rename(target.path);
    }
    await journal.recover(root);
    await journal.recover(root);
    check(
      await File('${target.path}/main.js').readAsString() ==
          (committed ? 'new' : 'old'),
      'wrong package after recover',
    );
    check(await root.list().length == 1, 'transaction debris after recover');
  } finally {
    await root.delete(recursive: true);
  }
}

Future<void> main() async {
  check(PluginMarketVersion.minimum(null) == null, 'optional minimum');
  check(PluginMarketVersion.minimum('1.2.0') == '1.2.0', 'valid minimum');
  for (final value in [
    '',
    'v1.2.0',
    '01.2.0',
    '1.2',
    '1.2.0+1',
    '1.2.0-beta',
    120,
  ]) {
    rejects(value, PluginMarketVersion.minimum);
  }
  for (final (version, meets) in [
    ('1.2.0', true),
    ('1.2.0+99', true),
    ('1.10.0', true),
    ('1.2.1-beta', true),
    ('1.2.0-beta', false),
    ('1.1.99', false),
    ('unknown', false),
  ]) {
    check(
      PluginMarketVersion.meetsMinimum(version, '1.2.0') == meets,
      'minimum $version',
    );
  }

  const action = {'id': 'save_quote', 'label': '收藏'};
  check(
    PluginMessageAction.parse([action]).single.id == 'save_quote',
    'action declaration',
  );
  for (final value in [
    {},
    [action, action],
    [
      {'id': 'bad-id', 'label': '动作'},
    ],
    [
      {'id': 'bad', 'label': '换\n行'},
    ],
    List.filled(17, action),
  ]) {
    rejects(value, PluginMessageAction.parse);
  }
  final message = {
    'id': 'm1',
    'role': 'assistant',
    'content': '<think>private</think>hello',
    'bot_id': 'secret',
    'error_log': 'secret',
  };
  final payload = PluginMessageAction.payload(message)!;
  check(
    payload.length == 3 && payload['text'] == 'hello' && payload['id'] == 'm1',
    'selected public payload only',
  );
  check(
    PluginMessageAction.payload({...message, 'type': 'image'}) == null,
    'no attachments',
  );
  check(
    PluginMessageAction.payload({...message, 'content': '汉' * 22000}) == null,
    'UTF-8 bound',
  );

  final operation = PluginOperation();
  operation.beginCommit();
  check(!operation.cancel(), 'filesystem swap cannot be interrupted');
  operation.endCommit();
  check(operation.cancel(), 'candidate startup can be cancelled');
  var blockedCommit = false;
  try {
    operation.beginCommit();
  } on PluginOperationCancelled {
    blockedCommit = true;
  }
  check(blockedCommit, 'cancelled candidate cannot be published');
  operation.dispose();

  await recoveryScenario(committed: false, swapped: false);
  await recoveryScenario(committed: false, swapped: true);
  await recoveryScenario(committed: true, swapped: true);
  stdout.writeln(
    'Plugin update, minimum version and message action checks passed',
  );
}
