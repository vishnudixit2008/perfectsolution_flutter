import 'package:flutter_test/flutter_test.dart';
import 'package:shop_management_flutter/data/models/app_user.dart';

void main() {
  group('AppUser & Granular Permissions System Tests', () {
    test('Default Admin has full unrestricted page, action, and column permissions', () {
      final admin = AppUser.defaultAdmin();

      expect(admin.isAdmin, isTrue);
      expect(admin.pageAccess['inward'], isTrue);
      expect(admin.pageAccess['sales'], isTrue);

      // Actions
      expect(admin.pageActionAccess['inward']?['canAdd'], isTrue);
      expect(admin.pageActionAccess['sales']?['canApplyDiscount'], isTrue);

      // Field column permissions
      final estimateField = admin.fieldAccess['inward']?['estimateItems'];
      expect(estimateField?.visible, isTrue);
      expect(estimateField?.creatable, isTrue);
      expect(estimateField?.editable, isTrue);
    });

    test('Employee custom per-page action permissions enforce boundaries', () {
      final employee = AppUser.defaultEmployee('staff@shop.com', 'Staff Member');

      expect(employee.isAdmin, isFalse);
      expect(employee.pageAccess['settings'], isFalse);

      // Inward page actions
      expect(employee.pageActionAccess['inward']?['canAdd'], isTrue);
      expect(employee.pageActionAccess['inward']?['canDelete'], isFalse);
    });

    test('Column-level field permission matrix (Visibility, Creatable, Editable)', () {
      final employee = AppUser.defaultEmployee('staff@shop.com', 'Staff Member');

      // Customize field permissions for inward module: estimate is creatable but NOT editable after entry
      final updatedFieldAccess = Map<String, Map<String, FieldPermission>>.from(employee.fieldAccess);
      updatedFieldAccess['inward'] = Map<String, FieldPermission>.from(updatedFieldAccess['inward'] ?? {});
      updatedFieldAccess['inward']!['estimateItems'] = const FieldPermission(
        visible: true,
        creatable: true,
        editable: false,
      );

      final restrictedUser = employee.copyWith(fieldAccess: updatedFieldAccess);

      final field = restrictedUser.fieldAccess['inward']?['estimateItems'];
      expect(field?.visible, isTrue);
      expect(field?.creatable, isTrue);
      expect(field?.editable, isFalse);
    });

    test('JSON Serialization & Backward Compatibility', () {
      final user = AppUser.defaultEmployee('test@shop.com', 'Test User');
      final json = user.toJson();
      final parsed = AppUser.fromJson(json);

      expect(parsed.email, equals('test@shop.com'));
      expect(parsed.name, equals('Test User'));
      expect(parsed.pageActionAccess.keys, containsAll(AppUser.modules));
      expect(parsed.fieldAccess.keys, containsAll(AppUser.modules));
    });
  });
}
