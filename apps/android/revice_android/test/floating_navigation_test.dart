import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revice_android/core/theme.dart';
import 'package:revice_android/features/floating_navigation_bar.dart';

void main() {
  testWidgets('Five tabs retain selection and theme with floating safe area', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: reviceTheme(),
        home: StatefulBuilder(
          builder: (context, setState) => MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              padding: EdgeInsets.only(bottom: 24),
            ),
            child: Scaffold(
              body: const Center(child: Text('Page content')),
              bottomNavigationBar: ReviceFloatingNavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (i) => setState(() => selected = i),
              ),
            ),
          ),
        ),
      ),
    );
    for (final label in [
      'Home',
      'Devices',
      'Insights',
      'Activity',
      'Settings',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        ['Home', 'Devices', 'Insights', 'Activity', 'Settings'].indexOf(label),
      );
    }
    final rect = tester.getRect(find.byType(NavigationBar));
    expect(rect.left, 16);
    expect(
      rect.bottom,
      lessThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 24,
      ),
    );
    final theme = NavigationBarTheme.of(
      tester.element(find.byType(NavigationBar)),
    );
    expect(theme.iconTheme!.resolve({WidgetState.selected})!.color, lime);
    expect(theme.labelTextStyle!.resolve({WidgetState.selected})!.color, lime);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small screen, large text, reduced motion and keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<void> show({double keyboard = 0, bool systemMotion = false}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: reviceTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 640),
                textScaler: TextScaler.linear(2),
                padding: const EdgeInsets.only(bottom: 48),
                viewInsets: EdgeInsets.only(bottom: keyboard),
                disableAnimations: systemMotion,
              ),
              child: Scaffold(
                bottomNavigationBar: ReviceFloatingNavigationBar(
                  selectedIndex: 0,
                  reduceMotion: !systemMotion,
                  onDestinationSelected: (_) {},
                ),
              ),
            ),
          ),
        );
    await show();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .animationDuration,
      Duration.zero,
    );
    await show(systemMotion: true);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .animationDuration,
      Duration.zero,
    );
    await show(keyboard: 280);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
