import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shop_management_flutter/ui/navigation/navigation_view_model.dart';
import 'package:shop_management_flutter/ui/shared/components/app_bottom_nav_bar.dart';

void main() {
  testWidgets(
    'Mobile UI (375x667) verifies horizontally draggable bottom navigation bar rendering',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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
      expect(find.text('Inward'), findsOneWidget);
      expect(find.text('Replacements'), findsOneWidget);
      expect(find.text('Pricelist'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Purchases'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    },
  );
}
