import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

class UserPermissionService {
  static const String _boxName = 'app_users_box';
  static const String _currentEmailKey = 'current_user_email';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    final box = Hive.box(_boxName);

    // Seed permanent admins
    final pureAdmins = [
      AppUser.defaultAdmin(
        email: 'perfectsolutionnoida@gmail.com',
        name: 'Perfect Solution (Admin)',
      ),
      AppUser.defaultAdmin(
        email: 'vishnudixit2008@gmail.com',
        name: 'Vishnu Dixit (Admin)',
      ),
      AppUser.defaultAdmin(
        email: 'admin@perfectsolution.com',
        name: 'System Administrator',
      ),
    ];

    for (var admin in pureAdmins) {
      if (!box.containsKey(admin.email.toLowerCase())) {
        await box.put(admin.email.toLowerCase(), admin.toJson());
      }
    }

    // Seed testing employee accounts if missing
    const staffEmail = 'staff@perfectsolution.com';
    if (!box.containsKey(staffEmail)) {
      final staffUser = AppUser.defaultEmployee(staffEmail, 'Standard Staff Member');
      await box.put(staffEmail, staffUser.toJson());
    }

    const viewOnlyEmail = 'viewonly@perfectsolution.com';
    if (!box.containsKey(viewOnlyEmail)) {
      final viewOnlyUser = AppUser(
        email: viewOnlyEmail,
        name: 'View-Only Staff',
        role: 'employee',
        isActive: true,
        pageAccess: {for (var m in AppUser.modules) m: true},
        actionAccess: {for (var k in ['canAdd', 'canEdit', 'canDelete', 'canPrint', 'canExport']) k: false},
        pageActionAccess: {
          for (var m in AppUser.modules)
            m: {for (var act in (AppUser.moduleActions[m] ?? {}).keys) act: false},
        },
        fieldAccess: {
          for (var m in AppUser.modules)
            m: {
              for (var f in (AppUser.moduleFields[m] ?? {}).keys)
                f: FieldPermission.readOnly(),
            },
        },
      );
      await box.put(viewOnlyEmail, viewOnlyUser.toJson());
    }

    // Explicitly purge vishnu2008dixit@gmail.com from local storage and remote database if present
    const removedEmail = 'vishnu2008dixit@gmail.com';
    if (box.containsKey(removedEmail)) {
      await box.delete(removedEmail);
    }
    if (box.get(_currentEmailKey) == removedEmail) {
      await box.put(_currentEmailKey, 'perfectsolutionnoida@gmail.com');
    }
    try {
      await Supabase.instance.client
          .from('app_users')
          .delete()
          .eq('email', removedEmail);
    } catch (_) {}

    // Set active user default if empty
    final current = box.get(_currentEmailKey);
    if (current == null) {
      await setCurrentUser('perfectsolutionnoida@gmail.com');
    }
  }

  static Box? _getBox() {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box(_boxName);
    }
    return null;
  }

  static String getCurrentUserEmail() {
    final box = _getBox();
    if (box == null) return 'perfectsolutionnoida@gmail.com';
    return box.get(_currentEmailKey, defaultValue: 'perfectsolutionnoida@gmail.com');
  }

  static Future<void> setCurrentUser(String email) async {
    final box = _getBox();
    if (box != null) {
      await box.put(_currentEmailKey, email.toLowerCase().trim());
    }
  }

  static AppUser getCurrentUser() {
    try {
      final email = getCurrentUserEmail().toLowerCase().trim();

      // Permanent Pure Admins override everything
      if (AppUser.isPermanentAdmin(email)) {
        final name = email.contains('vishnu') ? 'Vishnu Dixit (Admin)' : 'Perfect Solution Admin';
        return AppUser.defaultAdmin(email: email, name: name);
      }

      final box = _getBox();
      if (box != null) {
        final raw = box.get(email);
        if (raw != null && raw is Map) {
          return AppUser.fromJson(Map<String, dynamic>.from(raw));
        }
      }
    } catch (_) {}
    return AppUser.defaultAdmin(
      email: 'perfectsolutionnoida@gmail.com',
      name: 'Perfect Solution Admin',
    );
  }

  static List<AppUser> getAllUsers() {
    final box = _getBox();
    if (box == null) return [AppUser.defaultAdmin()];
    final List<AppUser> users = [];
    for (var key in box.keys) {
      if (key == _currentEmailKey) continue;
      final raw = box.get(key);
      if (raw is Map) {
        users.add(AppUser.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return users;
  }

  static Future<void> saveUser(AppUser user) async {
    final box = _getBox();
    if (box != null) {
      await box.put(user.email.toLowerCase().trim(), user.toJson());
    }
    try {
      await Supabase.instance.client.from('app_users').upsert({
        'email': user.email.toLowerCase().trim(),
        'name': user.name,
        'role': user.role,
        'is_active': user.isActive,
        'page_access': user.pageAccess,
        'action_access': user.actionAccess,
        'page_action_access': user.pageActionAccess,
        'field_access': user.fieldAccess.map(
          (m, fields) => MapEntry(m, fields.map((f, p) => MapEntry(f, p.toJson()))),
        ),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> deleteUser(String email) async {
    final cleanEmail = email.toLowerCase().trim();
    final box = _getBox();
    if (box != null) {
      await box.delete(cleanEmail);
    }
    try {
      await Supabase.instance.client
          .from('app_users')
          .delete()
          .eq('email', cleanEmail);
    } catch (_) {}
  }

  // --- Authorization & Permission Check Helpers ---

  /// Live Database & Local Storage Whitelist Authorization Check
  static Future<bool> isAuthorizedUserAsync(String email) async {
    final cleanEmail = email.toLowerCase().trim();
    if (cleanEmail.isEmpty) return false;

    // Permanent pure admins are always authorized
    if (AppUser.isPermanentAdmin(cleanEmail)) return true;

    // 1. Live Remote Cloud Check from Supabase app_users table
    try {
      final res = await Supabase.instance.client
          .from('app_users')
          .select('is_active')
          .eq('email', cleanEmail)
          .maybeSingle();

      if (res != null) {
        final isActive = res['is_active'] == true;
        return isActive;
      }
    } catch (_) {}

    // 2. Fallback check from local Hive storage
    final allUsers = getAllUsers();
    for (var u in allUsers) {
      if (u.email.toLowerCase().trim() == cleanEmail) {
        return u.isActive;
      }
    }
    return false;
  }

  static bool isAuthorizedUser(String email) {
    final cleanEmail = email.toLowerCase().trim();
    if (cleanEmail.isEmpty) return false;

    // Permanent pure admins are always authorized
    if (AppUser.isPermanentAdmin(cleanEmail)) return true;

    // Check if email exists in database/Hive and is active
    final allUsers = getAllUsers();
    for (var u in allUsers) {
      if (u.email.toLowerCase().trim() == cleanEmail) {
        return u.isActive;
      }
    }
    return false;
  }

  static bool isAdmin() {
    return getCurrentUser().isAdmin;
  }

  static bool canAccessPage(String moduleKey) {
    final user = getCurrentUser();
    if (user.isAdmin) return true;
    if (!user.isActive) return false;
    return user.pageAccess[moduleKey] ?? false;
  }

  /// Checks module-specific action permission.
  /// Example: [canPerformModuleAction]('inward', 'canDelete') or fallback to global [canPerform].
  static bool canPerformModuleAction(String moduleKey, String actionKey) {
    final user = getCurrentUser();
    if (user.isAdmin) return true;
    if (!user.isActive) return false;
    if (!canAccessPage(moduleKey)) return false;

    final moduleActions = user.pageActionAccess[moduleKey];
    if (moduleActions != null && moduleActions.containsKey(actionKey)) {
      return moduleActions[actionKey] ?? false;
    }

    // Fallback to legacy global actionAccess map if available
    return user.actionAccess[actionKey] ?? false;
  }

  /// Legacy single-parameter action check helper for global operations
  static bool canPerform(String actionKey) {
    final user = getCurrentUser();
    if (user.isAdmin) return true;
    if (!user.isActive) return false;
    return user.actionAccess[actionKey] ?? false;
  }

  /// Column / Field Visibility check
  static bool isFieldVisible(String moduleKey, String fieldKey) {
    final user = getCurrentUser();
    if (user.isAdmin) return true;
    if (!user.isActive) return false;
    if (!canAccessPage(moduleKey)) return false;

    final fieldPerm = user.fieldAccess[moduleKey]?[fieldKey];
    return fieldPerm?.visible ?? true;
  }

  /// Column / Field Entry Creation check (when creating new records)
  static bool isFieldCreatable(String moduleKey, String fieldKey) {
    final user = getCurrentUser();
    if (user.isAdmin) return true;
    if (!user.isActive) return false;
    if (!canAccessPage(moduleKey)) return false;

    final fieldPerm = user.fieldAccess[moduleKey]?[fieldKey];
    return fieldPerm?.creatable ?? true;
  }

  /// Column / Field Editability check (when editing existing records)
  static bool isFieldEditable(String moduleKey, String fieldKey) {
    final user = getCurrentUser();
    if (user.isAdmin) return true;
    if (!user.isActive) return false;
    if (!canAccessPage(moduleKey)) return false;

    final fieldPerm = user.fieldAccess[moduleKey]?[fieldKey];
    return fieldPerm?.editable ?? true;
  }
}
