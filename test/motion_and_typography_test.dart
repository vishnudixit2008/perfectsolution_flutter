import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_management_flutter/ui/core/app_theme.dart';
import 'package:shop_management_flutter/ui/core/motion/motion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Apple-Grade Motion & Typography System Tests', () {
    test('AppTypography tokens have correct SF Pro / HIG tracking and weights', () {
      expect(AppTypography.largeTitle.fontSize, 30);
      expect(AppTypography.largeTitle.letterSpacing, -0.7);
      expect(AppTypography.largeTitle.fontWeight, FontWeight.w700);

      expect(AppTypography.title1.fontSize, 22);
      expect(AppTypography.title1.letterSpacing, -0.5);

      expect(AppTypography.headline.fontSize, 15);
      expect(AppTypography.headline.letterSpacing, -0.2);

      expect(AppTypography.badge.fontSize, 10);
      expect(AppTypography.badge.letterSpacing, 0.6);
      expect(AppTypography.badge.fontWeight, FontWeight.w700);

      expect(AppTypography.currencyLarge.fontSize, 20);
      expect(AppTypography.currencyLarge.letterSpacing, -0.5);
    });

    testWidgets('BouncyPressable handles tap and triggers callback', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BouncyPressable(
              onTap: () => tapped = true,
              child: const Text('Tap Me'),
            ),
          ),
        ),
      );

      expect(find.text('Tap Me'), findsOneWidget);

      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('StaggeredSlideFade renders child widget cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaggeredSlideFade(
              index: 2,
              child: const Text('Animated Item'),
            ),
          ),
        ),
      );

      // Advance timers past stagger delay
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Animated Item'), findsOneWidget);
    });

    testWidgets('RollingNumberTicker renders and formats currency correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RollingNumberTicker(
              value: 4800,
              prefix: '₹',
              decimalDigits: 2,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('₹4,800.00'), findsOneWidget);
    });

    testWidgets('ShimmerSkeleton mounts with custom dimensions', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShimmerSkeleton.card(height: 90),
          ),
        ),
      );

      expect(find.byType(ShimmerSkeleton), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('showAppModalDialog presents and dismisses content with snappy Apple curve', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showAppModalDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Spring Modal Header'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open Modal'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Spring Modal Header'), findsOneWidget);

      // Tap close and verify snappy dismissal without lag
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('Spring Modal Header'), findsNothing);
    });

    testWidgets('AppAnimatedSearchBar renders search input and clear button', (WidgetTester tester) async {
      final controller = TextEditingController();
      String query = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppAnimatedSearchBar(
              controller: controller,
              onChanged: (val) => query = val,
              hintText: 'Search items...',
            ),
          ),
        ),
      );

      expect(find.text('Search items...'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Asus Laptop');
      await tester.pumpAndSettle();

      expect(query, 'Asus Laptop');
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
    });
  });
}
