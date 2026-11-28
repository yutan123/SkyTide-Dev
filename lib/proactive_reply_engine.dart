import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ai.dart';
import 'bot_vital_signs_service.dart';
import 'bot_vital_model.dart';
import 'db.dart';
import 'proactive_request_gate.dart';
import 'app_log_service.dart';

/// Android retains ownership of the execution lease and the final transaction.
/// Use the ordinary chat pipeline to assemble context, run tools and split text.
void startProactiveReplyEngine() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('skytide/proactive_reply');
  AICancellationToken? activeToken;
  channel.setMethodCallHandler((call) async {
    if (call.method == 'cancel') {
      activeToken?.cancel();
      return null;
    }
    if (call.method != 'generate') throw MissingPluginException();
    final args = Map<Object?, Object?>.from(call.arguments as Map);
    final botId = args['botId'] as String;
    final kind = args['kind'] as String? ?? 'proactive';
    final generation = args['generation'] as String?;
    final due = args['due'] as String?;
    final token = AICancellationToken(
      beforeRequest: () async {
        if (kind != 'proactive') return;
        final db = await DBManager().database;
        final allowed = await db.transaction(
          (txn) => ProactiveRequestGate.allowed(txn, botId, generation!, due),
        );
        if (!allowed) activeToken?.cancel();
      },
    );
    activeToken = token;
    try {
      await token.checkRequestAllowed();
      await AppLogService.instance.restoreFromPreferences();
      final response = switch (kind) {
        'proactive' => await AIManager().sendMessage(
          botId: botId,
          cancellationToken: token,
          text: '【主动联系时机】主动联系时间已到，请结合当前上下文判断是否适合联系。',
          task: AIRequestTask.proactiveChat,
          persistResponse: false,
          nativeOwnsDelivery: true,
        ),
        'future' => await AIManager().sendMessage(
          botId: botId,
          cancellationToken: token,
          text: '这是一个定时任务，请完成：${args['prompt']}',
          persistResponse: false,
          nativeOwnsDelivery: true,
        ),
        'vitals' => await BotVitalSignsService.sendPendingReply(
          botId,
          args['reason'] as String,
          vitalList(jsonDecode(args['pending'] as String)),
          nativeOwnsDelivery: true,
          cancellationToken: token,
        ),
        _ => throw ArgumentError('Unknown background chat kind: $kind'),
      };
      await token.checkRequestAllowed();
      return {
        ...response,
        if (AppLogService.instance.enabled)
          'request_logs': AppLogService.instance.entries
              .map((e) => e.toJson())
              .toList(),
      };
    } finally {
      activeToken = null;
    }
  });
  channel.invokeMethod<void>('ready');
}
