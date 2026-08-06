import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../../ui/shared/status_management_dialog.dart';

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

    // Sync cloud user database asynchronously
    syncUsersFromCloud();
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
    final cleanEmail = email.toLowerCase().trim();
    final box = _getBox();
    if (box != null) {
      await box.put(_currentEmailKey, cleanEmail);
    }
    await syncSingleUserFromCloud(cleanEmail);
  }

  static Future<void> syncSingleUserFromCloud(String email) async {
    final cleanEmail = email.toLowerCase().trim();
    if (cleanEmail.isEmpty) return;
    if (AppUser.isPermanentAdmin(cleanEmail)) return;

    try {
      final res = await Supabase.instance.client
          .from('app_users')
          .select()
          .eq('email', cleanEmail)
          .maybeSingle();

      if (res != null) {
        final cloudUser = AppUser.fromJson(Map<String, dynamic>.from(res));
        final box = _getBox();
        if (box != null) {
          await box.put(cleanEmail, cloudUser.toJson());
        }
      }
    } catch (_) {}
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

    // Fallback for non-permanent admins: default employee role (restricted), NEVER default admin!
    final currentEmail = getCurrentUserEmail();
    return AppUser.defaultEmployee(currentEmail, 'User');
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

  /// Sync all users from Supabase app_users table to local Hive storage
  /// Purges local Hive user entries that were deleted on Supabase Cloud.
  static Future<void> syncUsersFromCloud() async {
    try {
      final response = await Supabase.instance.client
          .from('app_users')
          .select()
          .timeout(const Duration(seconds: 10));

      final box = _getBox();
      if (box == null) return;

      final Set<String> cloudEmails = {};
      for (final row in response) {
        final map = Map<String, dynamic>.from(row);
        final email = (map['email'] ?? '').toString().toLowerCase().trim();
        if (email.isNotEmpty) {
          cloudEmails.add(email);
          final user = AppUser.fromJson(map);
          await box.put(email, user.toJson());
        }
      }

      // Purge local users that no longer exist in Supabase Cloud
      final localKeys = box.keys.map((e) => e.toString().toLowerCase().trim()).toList();
      for (final key in localKeys) {
        if (key == _currentEmailKey) continue;
        if (AppUser.isPermanentAdmin(key)) continue;
        if (!cloudEmails.contains(key)) {
          await box.delete(key);
        }
      }
    } catch (_) {}
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
        'user_password': user.password,
        'page_access': user.pageAccess,
        'action_access': user.actionAccess,
        'page_action_access': user.pageActionAccess,
        'field_access': user.fieldAccess.map(
          (m, fields) => MapEntry(m, fields.map((f, p) => MapEntry(f, p.toJson()))),
        ),
        'status_visibility_access': user.statusVisibilityAccess,
        'status_selectable_access': user.statusSelectableAccess,
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
          .select()
          .eq('email', cleanEmail)
          .maybeSingle();

      if (res != null) {
        final map = Map<String, dynamic>.from(res);
        final fetchedUser = AppUser.fromJson(map);
        final box = _getBox();
        if (box != null) {
          await box.put(cleanEmail, fetchedUser.toJson());
        }
        return fetchedUser.isActive;
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

  static AppUser? getUser(String email) {
    final cleanEmail = email.toLowerCase().trim();
    if (cleanEmail.isEmpty) return null;
    if (AppUser.isPermanentAdmin(cleanEmail)) {
      final name = cleanEmail.contains('vishnu') ? 'Vishnu Dixit (Admin)' : 'Perfect Solution Admin';
      return AppUser.defaultAdmin(email: cleanEmail, name: name);
    }
    final box = _getBox();
    if (box != null) {
      final raw = box.get(cleanEmail);
      if (raw != null && raw is Map) {
        return AppUser.fromJson(Map<String, dynamic>.from(raw));
      }
    }
    return null;
  }

  /// Verifies password against user credentials — always does live cloud fetch first
  static Future<bool> verifyUserPassword(String email, String password) async {
    final cleanEmail = email.toLowerCase().trim();
    final cleanPass = password.trim();
    if (cleanEmail.isEmpty || cleanPass.isEmpty) return false;

    // 1. Always do a LIVE cloud fetch first to get the latest password set by admin
    try {
      final res = await Supabase.instance.client
          .from('app_users')
          .select()
          .eq('email', cleanEmail)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (res != null) {
        final map = Map<String, dynamic>.from(res);
        final cloudUser = AppUser.fromJson(map);

        // Save latest user to local cache
        final box = _getBox();
        if (box != null) {
          await box.put(cleanEmail, cloudUser.toJson());
        }

        if (!cloudUser.isActive) return false;

        if (cloudUser.password != null && cloudUser.password!.trim().isNotEmpty) {
          return cloudUser.password!.trim() == cleanPass;
        }
        // User exists but has no password set → deny
        return false;
      }
    } catch (_) {
      // Cloud fetch failed — fall back to local Hive cache below
    }

    // 2. Fallback: check local Hive cache
    final user = getUser(cleanEmail);
    if (user == null || !user.isActive) return false;

    if (user.password != null && user.password!.isNotEmpty) {
      return user.password!.trim() == cleanPass;
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
    return AppUser.isPermanentAdmin(getCurrentUser().email);
  }

  static bool canAccessPage(String moduleKey) {
    final user = getCurrentUser();
    if (AppUser.isPermanentAdmin(user.email)) return true;
    if (!user.isActive) return false;
    if (moduleKey == 'settings') return true;
    return user.pageAccess[moduleKey] ?? false;
  }

  /// Checks module-specific action permission.
  /// Example: [canPerformModuleAction]('inward', 'canDelete') or fallback to global [canPerform].
  static bool canPerformModuleAction(String moduleKey, String actionKey) {
    final user = getCurrentUser();
    if (AppUser.isPermanentAdmin(user.email)) return true;
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
    if (AppUser.isPermanentAdmin(user.email)) return true;
    if (!user.isActive) return false;
    return user.actionAccess[actionKey] ?? false;
  }

  /// Column / Field Visibility check
  static bool isFieldVisible(String moduleKey, String fieldKey) {
    final user = getCurrentUser();
    if (AppUser.isPermanentAdmin(user.email)) return true;
    if (!user.isActive) return false;
    if (!canAccessPage(moduleKey)) return false;

    final fieldPerm = user.fieldAccess[moduleKey]?[fieldKey];
    return fieldPerm?.visible ?? true;
  }

  /// Column / Field Entry Creation check (when creating new records)
  static bool isFieldCreatable(String moduleKey, String fieldKey) {
    final user = getCurrentUser();
    if (AppUser.isPermanentAdmin(user.email)) return true;
    if (!user.isActive) return false;
    if (!canAccessPage(moduleKey)) return false;

    final fieldPerm = user.fieldAccess[moduleKey]?[fieldKey];
    return fieldPerm?.creatable ?? true;
  }

  /// Column / Field Editability check (when editing existing records)
  static bool isFieldEditable(String moduleKey, String fieldKey) {
    final user = getCurrentUser();
    if (AppUser.isPermanentAdmin(user.email)) return true;
    if (!user.isActive) return false;
    if (!canAccessPage(moduleKey)) return false;

    final fieldPerm = user.fieldAccess[moduleKey]?[fieldKey];
    return fieldPerm?.editable ?? true;
  }

  /// Helper to check if a field can be modified depending on edit mode (isEdit: true -> editable, false -> creatable)
  static bool canModifyField(String moduleKey, String fieldKey, {required bool isEdit}) {
    return isEdit ? isFieldEditable(moduleKey, fieldKey) : isFieldCreatable(moduleKey, fieldKey);
  }

  /// Checks if the current user is permitted to see an entry with the specified status in [moduleKey]
  static bool isStatusVisible(String moduleKey, String status) {
    final user = getCurrentUser();
    if (AppUser.isPermanentAdmin(user.email)) return true;
    if (!user.isActive) return false;

    final allowed = user.statusVisibilityAccess[moduleKey];
    if (allowed == null || allowed.isEmpty || allowed.contains('*')) {
      return true;
    }
    final cleanStatus = status.trim().toLowerCase();
    return allowed.any((a) => a.trim().toLowerCase() == cleanStatus);
  }

  /// Returns the list of statuses the current user can select when editing/creating in [moduleKey]
  static List<String> getAllowedSelectableStatuses(
    String moduleKey, {
    List<String>? allAvailableStatuses,
  }) {
    final configured = allAvailableStatuses ??
        StatusManagementService.getStatuses(moduleKey);
    final user = getCurrentUser();
    if (AppUser.isPermanentAdmin(user.email)) return configured;

    final allowed = user.statusSelectableAccess[moduleKey];
    if (allowed == null || allowed.isEmpty || allowed.contains('*')) {
      return configured;
    }

    final filtered = configured
        .where((s) => allowed.any((a) => a.trim().toLowerCase() == s.trim().toLowerCase()))
        .toList();

    return filtered.isEmpty ? configured : filtered;
  }
}
