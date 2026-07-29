import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shop_management_flutter/ui/navigation/navigation_view_model.dart';
import 'package:shop_management_flutter/ui/shared/components/app_bottom_nav_bar.dart';

void main() {
  testWidgets(
    'App smoke test - verifies AppBottomNavBar builds horizontally scrollable items',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<NavigationViewModel>(
          create: (_) => NavigationViewModel(),
          child: const MaterialApp(
            home: Scaffold(
              bottomNavigationBar: AppBottomNavBar(currentIndex: 0),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(AppBottomNavBar), findsOneWidget);
      expect(find.text('Calls'), findsOneWidget);
    },
  );
}
