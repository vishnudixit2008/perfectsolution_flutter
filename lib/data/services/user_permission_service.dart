import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import 'ui_preferences_service.dart';
import '../../ui/shared/status_management_dialog.dart';

class UserPermissionService {
  static const String _boxName = 'app_users_box';
  static const String _currentEmailKey = 'current_user_email';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      try {
        await Hive.openBox(_boxName);
      } catch (_) {
        try {
          await Hive.openBox('${_boxName}_fallback');
        } catch (_) {
          await Hive.openBox('${_boxName}_${DateTime.now().millisecondsSinceEpoch}');
        }
      }
    }
    final box = Hive.isBoxOpen(_boxName)
        ? Hive.box(_boxName)
        : (Hive.isBoxOpen('${_boxName}_fallback')
            ? Hive.box('${_boxName}_fallback')
            : await Hive.openBox(_boxName));

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
    ];

    for (var admin in pureAdmins) {
      if (!box.containsKey(admin.email.toLowerCase())) {
        await box.put(admin.email.toLowerCase(), admin.toJson());
      }
    }

    // Explicitly purge legacy dummy accounts from local storage and remote database if present
    const purgeEmails = ['vishnu2008dixit@gmail.com', 'admin@perfectsolution.com'];
    for (final remEmail in purgeEmails) {
      if (box.containsKey(remEmail)) {
        await box.delete(remEmail);
      }
      if (box.get(_currentEmailKey) == remEmail) {
        await box.put(_currentEmailKey, 'perfectsolutionnoida@gmail.com');
      }
      try {
        await Supabase.instance.client
            .from('app_users')
            .delete()
            .eq('email', remEmail);
      } catch (_) {}
    }

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

  static AppUser? _cachedCurrentUser;
  static bool _isSyncingUsers = false;

  static String getCurrentUserEmail() {
    final box = _getBox();
    if (box == null) return 'perfectsolutionnoida@gmail.com';
    return box.get(_currentEmailKey, defaultValue: 'perfectsolutionnoida@gmail.com');
  }

  static Future<void> setCurrentUser(String email) async {
    final cleanEmail = email.toLowerCase().trim();
    _cachedCurrentUser = null;
    StatusManagementService.clearCache();
    final box = _getBox();
    if (box != null) {
      await box.put(_currentEmailKey, cleanEmail);
    }
    await syncSingleUserFromCloud(cleanEmail);
    final user = getCurrentUser();
    await StatusManagementService.loadFromUser(user);
  }

  static Future<void> syncSingleUserFromCloud(String email) async {
    final cleanEmail = email.toLowerCase().trim();
    if (cleanEmail.isEmpty) return;

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
        _cachedCurrentUser = null;
        await StatusManagementService.loadFromUser(cloudUser);
      }
    } catch (_) {}
  }

  static AppUser getCurrentUser() {
    if (_cachedCurrentUser != null) {
      return _cachedCurrentUser!;
    }
    try {
      final email = getCurrentUserEmail().toLowerCase().trim();

      final box = _getBox();
      final userData = box?.get(email);
      if (userData != null && userData is Map) {
        final parsedUser = AppUser.fromJson(Map<String, dynamic>.from(userData));
        if (AppUser.isPermanentAdmin(email)) {
          final name = parsedUser.name.isNotEmpty
              ? parsedUser.name
              : (email.contains('vishnu') ? 'Vishnu Dixit (Admin)' : 'Perfect Solution Admin');
          _cachedCurrentUser = AppUser.defaultAdmin(
            email: email,
            name: name,
            password: parsedUser.password,
            customStatusLists: parsedUser.customStatusLists,
            defaultStatuses: parsedUser.defaultStatuses,
          );
        } else {
          _cachedCurrentUser = parsedUser;
        }
        return _cachedCurrentUser!;
      }

      // Permanent Pure Admins fallback
      if (AppUser.isPermanentAdmin(email)) {
        final name = email.contains('vishnu') ? 'Vishnu Dixit (Admin)' : 'Perfect Solution Admin';
        _cachedCurrentUser = AppUser.defaultAdmin(email: email, name: name);
        return _cachedCurrentUser!;
      }

      // Default fallback for unrecognized non-admin user
      _cachedCurrentUser = AppUser.defaultEmployee(email, email);
      return _cachedCurrentUser!;
    } catch (e) {
      final email = getCurrentUserEmail().toLowerCase().trim();
      _cachedCurrentUser = AppUser.defaultEmployee(email, email);
      return _cachedCurrentUser!;
    }
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
  /// Throttled to max once per 15 minutes unless [force] is true.
  static Future<void> syncUsersFromCloud({bool force = false}) async {
    if (_isSyncingUsers) return;
    _isSyncingUsers = true;

    try {
      final now = DateTime.now();
      final lastCheckMillis = (UiPreferencesService.getValue('last_users_sync_time') as num?)?.toInt() ?? 0;
      final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckMillis);

      if (!force && now.difference(lastCheck).inMinutes < 15) {
        return;
      }

      await UiPreferencesService.setValue('last_users_sync_time', now.millisecondsSinceEpoch);

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
          if (email == getCurrentUserEmail().toLowerCase().trim()) {
            await StatusManagementService.loadFromUser(user);
          }
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
      // Clear all caches so next read reflects freshly synced permissions/statuses
      _cachedCurrentUser = null;
      StatusManagementService.clearCache();
    } catch (_) {
    } finally {
      _isSyncingUsers = false;
    }
  }

  static Future<void> saveUser(AppUser user) async {
    final cleanEmail = user.email.toLowerCase().trim();
    final box = _getBox();

    // Preserve existing local password if not provided in user model
    String? finalPassword = user.password;
    if ((finalPassword == null || finalPassword.trim().isEmpty) && box != null) {
      final existingRaw = box.get(cleanEmail);
      if (existingRaw is Map) {
        final existingPass = (existingRaw['password'] ?? existingRaw['user_password'])?.toString();
        if (existingPass != null && existingPass.trim().isNotEmpty) {
          finalPassword = existingPass.trim();
        }
      }
    }

    final userToSave = user.copyWith(password: finalPassword);

    if (box != null) {
      await box.put(cleanEmail, userToSave.toJson());
    }

    final cloudPayload = <String, dynamic>{
      'email': cleanEmail,
      'name': user.name,
      'role': user.role,
      'is_active': user.isActive,
      'page_access': user.pageAccess,
      'action_access': user.actionAccess,
      'page_action_access': {
        ...user.pageActionAccess,
        '__only_assigned__': user.onlyAssignedAccess,
        '__status_lists__': user.customStatusLists,
        '__default_statuses__': user.defaultStatuses,
      },
      'field_access': user.fieldAccess.map(
        (m, fields) => MapEntry(m, fields.map((f, p) => MapEntry(f, p.toJson()))),
      ),
      'status_visibility_access': user.statusVisibilityAccess,
      'status_selectable_access': user.statusSelectableAccess,
      'updated_at': DateTime.now().toIso8601String(),
    };

    // CRITICAL: Only include user_password in cloud payload if it is non-empty
    // NEVER overwrite an existing database password with null!
    if (finalPassword != null && finalPassword.trim().isNotEmpty) {
      cloudPayload['user_password'] = finalPassword.trim();
    }

    try {
      // First attempt: include dedicated columns if they exist in Postgres
      await Supabase.instance.client.from('app_users').upsert({
        ...cloudPayload,
        'only_assigned_access': user.onlyAssignedAccess,
      }).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Fallback: upsert using base payload where nested configs are embedded in page_action_access
      try {
        await Supabase.instance.client
            .from('app_users')
            .upsert(cloudPayload)
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('Cloud save user fallback failed: $e');
      }
    }
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
          .eq('email', cleanEmail)
          .timeout(const Duration(seconds: 4));
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
    final box = _getBox();
    if (box != null) {
      final raw = box.get(cleanEmail);
      if (raw != null && raw is Map) {
        final parsed = AppUser.fromJson(Map<String, dynamic>.from(raw));
        if (AppUser.isPermanentAdmin(cleanEmail)) {
          final name = parsed.name.isNotEmpty
              ? parsed.name
              : (cleanEmail.contains('vishnu') ? 'Vishnu Dixit (Admin)' : 'Perfect Solution Admin');
          return AppUser.defaultAdmin(
            email: cleanEmail,
            name: name,
            password: parsed.password,
            customStatusLists: parsed.customStatusLists,
            defaultStatuses: parsed.defaultStatuses,
          );
        }
        return parsed;
      }
    }
    if (AppUser.isPermanentAdmin(cleanEmail)) {
      final name = cleanEmail.contains('vishnu') ? 'Vishnu Dixit (Admin)' : 'Perfect Solution Admin';
      return AppUser.defaultAdmin(email: cleanEmail, name: name);
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

  /// Formats any assignedTo value (email or name) into a user-friendly display name
  static String formatStaffName(String? rawAssigned) {
    if (rawAssigned == null || rawAssigned.trim().isEmpty || rawAssigned == 'N/A') {
      return 'Unassigned';
    }
    final clean = rawAssigned.trim();
    final lower = clean.toLowerCase();

    if (lower == 'office') {
      return 'Office';
    }

    // Check if we have a known user with matching email or name
    final allUsers = getAllUsers();
    for (final u in allUsers) {
      if (u.email.toLowerCase().trim() == lower ||
          u.name.toLowerCase().trim() == lower) {
        if (u.name.trim().isNotEmpty) {
          final n = u.name.trim();
          return n.toLowerCase() == 'office' ? 'Office' : n;
        }
      }
    }

    // If it's an email without an exact user, format username part nicely
    if (clean.contains('@')) {
      final prefix = clean.split('@').first;
      final parts = prefix.split(RegExp(r'[._]')).where((p) => p.isNotEmpty);
      if (parts.isNotEmpty) {
        return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
      }
    }
    return clean;
  }

  /// Returns list of available staff display names for dropdowns
  static List<String> getStaffDisplayNames() {
    final Map<String, String> uniqueNamesByLower = {};
    final allUsers = getAllUsers();
    for (final u in allUsers) {
      if (u.isActive) {
        final rawName = u.name.trim().isNotEmpty ? u.name.trim() : u.email.trim();
        final displayName = formatStaffName(rawName);
        if (displayName.isNotEmpty &&
            displayName.toLowerCase() != 'unassigned' &&
            !uniqueNamesByLower.containsKey(displayName.toLowerCase())) {
          uniqueNamesByLower[displayName.toLowerCase()] = displayName;
        }
      }
    }
    if (!uniqueNamesByLower.containsKey('office')) {
      uniqueNamesByLower['office'] = 'Office';
    }
    return uniqueNamesByLower.values.toList();
  }

  /// Whether the current device / user should receive popups and alerts for call assignments
  static bool shouldReceiveCallAlertPopup([AppUser? user]) {
    return true;
  }

  /// Checks if an entry is specifically and directly assigned to the user (ignoring admin wildcards)
  static bool isEntryDirectlyAssignedToUser(String? assignedTo, [AppUser? user]) {
    final currentUser = user ?? getCurrentUser();
    if (assignedTo == null || assignedTo.trim().isEmpty || assignedTo == 'N/A') {
      return false;
    }

    final assigned = assignedTo.trim().toLowerCase();
    final userEmail = currentUser.email.trim().toLowerCase();
    final userName = currentUser.name.trim().toLowerCase();
    final userEmailPrefix =
        userEmail.contains('@') ? userEmail.split('@').first : userEmail;
    final assignedPrefix =
        assigned.contains('@') ? assigned.split('@').first : assigned;

    // 1. Direct exact / prefix matches
    if (assigned == userEmail ||
        assigned == userEmailPrefix ||
        assignedPrefix == userEmailPrefix ||
        assignedPrefix == userEmail) {
      return true;
    }

    // 2. Name matches
    if (userName.isNotEmpty) {
      if (assigned == userName || assignedPrefix == userName) {
        return true;
      }
      if (assigned.contains(userName) || userName.contains(assigned)) {
        return true;
      }
      final cleanName = userName.replaceAll(RegExp(r'\s+'), '');
      final cleanAssigned = assigned.replaceAll(RegExp(r'\s+'), '');
      if (cleanName.isNotEmpty &&
          (cleanAssigned.contains(cleanName) || cleanName.contains(cleanAssigned))) {
        return true;
      }
    }

    // 3. Substring / email contains
    if (userEmail.isNotEmpty && assigned.contains(userEmail)) {
      return true;
    }
    if (userEmailPrefix.isNotEmpty &&
        (assigned.contains(userEmailPrefix) || userEmailPrefix.contains(assigned))) {
      return true;
    }

    return false;
  }

  /// Checks if an entry's assignedTo field matches the specified (or current) user
  static bool isEntryAssignedToUser(String? assignedTo, [AppUser? user]) {
    final currentUser = user ?? getCurrentUser();
    if (AppUser.isPermanentAdmin(currentUser.email)) return true;
    return isEntryDirectlyAssignedToUser(assignedTo, currentUser);
  }

  /// Returns whether the current user is restricted to only seeing entries assigned to them in [moduleKey]
  static bool isOnlyAssignedRestricted(String moduleKey, [AppUser? user]) {
    final currentUser = user ?? getCurrentUser();
    if (AppUser.isPermanentAdmin(currentUser.email)) return false;
    return currentUser.onlyAssignedAccess[moduleKey] ?? false;
  }

  /// Combined visibility checker: checks both assigned-to restriction (if enabled for this module)
  /// AND status visibility permission.
  static bool isEntryVisible({
    required String moduleKey,
    required String status,
    String? assignedTo,
  }) {
    final user = getCurrentUser();
    if (AppUser.isPermanentAdmin(user.email)) return true;
    if (!user.isActive) return false;

    // 1. Check if user is restricted to only assigned entries in this module
    final bool onlyAssigned = user.onlyAssignedAccess[moduleKey] ?? false;
    if (onlyAssigned) {
      if (!isEntryAssignedToUser(assignedTo, user)) {
        return false;
      }
    }

    // 2. Check if status is visible
    return isStatusVisible(moduleKey, status);
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

    return filtered;
  }
}
