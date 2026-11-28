import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skytide/daily_launch_animation.dart';

void main() {
  const curtain = ValueKey('builtin-launch-curtain');

  testWidgets('tapping the opening skips without tapping the hidden home', (
    tester,
  ) async {
    String? savedDate;
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyLaunchAnimation(
            lastPlayedDate: null,
            savePlayedDate: (date) async {
              savedDate = date;
            },
            child: Center(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    final home = tester.element(find.text('打开'));
    await tester.tapAt(tester.getCenter(find.text('打开')));
    await tester.pump();

    expect(taps, 0);
    expect(find.byType(Image), findsNothing);
    expect(tester.element(find.text('打开')), same(home));
    expect(savedDate, isNotNull);
    await tester.tap(find.text('打开'));
    expect(taps, 1);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the ${brightness.name} opening is opaque until the reveal', (
      tester,
    ) async {
      var saveCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: DailyLaunchAnimation(
            lastPlayedDate: null,
            savePlayedDate: (_) async {
              saveCalls++;
            },
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      );

      final overlay = find.byKey(curtain);
      double opacity() => tester.widget<Opacity>(overlay).opacity;
      expect(opacity(), 1);
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(of: overlay, matching: find.byType(ColoredBox)),
            )
            .color,
        brightness == Brightness.dark
            ? DailyLaunchAnimation.darkBackground
            : DailyLaunchAnimation.lightBackground,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1750));
      expect(opacity(), 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(), allOf(greaterThan(0), lessThan(1)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(overlay, findsNothing);
      expect(saveCalls, 1);
    });
  }

  testWidgets('reduced motion shows a short static opening', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: DailyLaunchAnimation(
          lastPlayedDate: null,
          savePlayedDate: (_) async {},
          child: const Center(child: Text('首页')),
        ),
      ),
    );

    expect(find.byKey(curtain), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(curtain), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('same-day restart shows the destination without animation', (
    tester,
  ) async {
    final now = DateTime.now();
    var saveCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DailyLaunchAnimation(
          lastPlayedDate: '${now.year}-${now.month}-${now.day}',
          savePlayedDate: (_) async {
            saveCalls++;
          },
          child: const Center(child: Text('首页')),
        ),
      ),
    );

    expect(find.text('首页'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(saveCalls, 0);
  });
}
