import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skytide/app_navigation.dart';
import 'package:skytide/platform_editor_form.dart';

void main() {
  testWidgets('requires a selection and returns it only after confirmation', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(navigatorKey: appNavigatorKey, home: const Scaffold()),
    );
    final reply = showPlatformEditorForm('插件 · example', '选择分类', '请选择', const [
      EditorField(
        'type',
        '分类',
        'single',
        options: ['开心', '惊讶'],
        required: true,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('请求来源：插件 · example'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text('请选择一项'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('惊讶').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(await reply, {'type': '惊讶'});
  });

  testWidgets('cancels the request when the app becomes hidden', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(navigatorKey: appNavigatorKey, home: const Scaffold()),
    );
    final reply = showPlatformEditorForm(
      '机器人 · example',
      '允许修改？',
      '修改设置',
      const [],
    );
    await tester.pumpAndSettle();
    expect(find.text('允许此操作'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(await reply, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('允许此操作'), findsNothing);
  });
}
