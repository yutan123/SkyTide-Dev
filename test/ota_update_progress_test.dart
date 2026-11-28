import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:skytide/ota_update.dart';

void main() {
  testWidgets('manual check can cancel and retry without late update prompts', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'SkyTide',
      packageName: 'skytide',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final pending = Completer<http.Response>();
    final requests = <Uri>[];
    final clients = <_TrackedClient>[];
    final response = http.Response(
      '{"versionCode":2,"versionName":"2.0.0",'
      '"downloadUrl":"https://example.com/app.apk","releaseNotes":"New"}',
      200,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  http.runWithClient(() => OtaUpdate.checkNow(context), () {
                    final client = _TrackedClient((request) {
                      requests.add(request.url);
                      return requests.length == 1
                          ? pending.future
                          : Future.value(response);
                    });
                    clients.add(client);
                    return client;
                  }),
              child: const Text('Check'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('正在检测新版本…'), findsOneWidget);
    expect(requests, hasLength(1));

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(clients.first.closed, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    pending.complete(response);
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(find.text('发现新版本 2.0.0'), findsNothing);

    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('发现新版本 2.0.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TrackedClient extends MockClient {
  _TrackedClient(super.fn);
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
