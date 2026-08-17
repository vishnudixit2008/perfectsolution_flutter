class FieldPermission {
  final bool visible;
  final bool creatable;
  final bool editable;

  const FieldPermission({
    this.visible = true,
    this.creatable = true,
    this.editable = true,
  });

  factory FieldPermission.allTrue() =>
      const FieldPermission(visible: true, creatable: true, editable: true);
  factory FieldPermission.createOnly() =>
      const FieldPermission(visible: true, creatable: true, editable: false);
  factory FieldPermission.readOnly() =>
      const FieldPermission(visible: true, creatable: false, editable: false);
  factory FieldPermission.hidden() =>
      const FieldPermission(visible: false, creatable: false, editable: false);

  factory FieldPermission.fromJson(Map<String, dynamic> json) {
    return FieldPermission(
      visible: json['visible'] ?? true,
      creatable: json['creatable'] ?? true,
      editable: json['editable'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'visible': visible,
      'creatable': creatable,
      'editable': editable,
    };
  }

  FieldPermission copyWith({
    bool? visible,
    bool? creatable,
    bool? editable,
  }) {
    return FieldPermission(
      visible: visible ?? this.visible,
      creatable: creatable ?? this.creatable,
      editable: editable ?? this.editable,
    );
  }
}

class AppUser {
  final String email;
  final String name;
  final String role; // 'admin' | 'employee'
  final bool isActive;
  final String? password;
  final Map<String, bool> pageAccess;
  final Map<String, bool> actionAccess; // Legacy / fallback global action access
  final Map<String, Map<String, bool>> pageActionAccess;
  final Map<String, Map<String, FieldPermission>> fieldAccess;
  final Map<String, List<String>> statusVisibilityAccess;
  final Map<String, List<String>> statusSelectableAccess;
  final Map<String, bool> onlyAssignedAccess;
  final Map<String, List<String>> customStatusLists;
  final Map<String, String> defaultStatuses;

  AppUser({
    required this.email,
    required this.name,
    required this.role,
    this.isActive = true,
    this.password,
    required this.pageAccess,
    required this.actionAccess,
    Map<String, Map<String, bool>>? pageActionAccess,
    Map<String, Map<String, FieldPermission>>? fieldAccess,
    Map<String, List<String>>? statusVisibilityAccess,
    Map<String, List<String>>? statusSelectableAccess,
    Map<String, bool>? onlyAssignedAccess,
    Map<String, List<String>>? customStatusLists,
    Map<String, String>? defaultStatuses,
  })  : pageActionAccess = pageActionAccess ?? _defaultPageActionAccess(),
        fieldAccess = fieldAccess ?? _defaultFieldAccess(),
        statusVisibilityAccess =
            statusVisibilityAccess ?? _defaultStatusAccess(),
        statusSelectableAccess =
            statusSelectableAccess ?? _defaultStatusAccess(),
        onlyAssignedAccess = onlyAssignedAccess ?? _defaultOnlyAssignedAccess(),
        customStatusLists = customStatusLists ?? {},
        defaultStatuses = defaultStatuses ?? {};

  static const List<String> permanentAdminEmails = [
    'perfectsolutionnoida@gmail.com',
    'vishnudixit2008@gmail.com',
  ];

  static bool isPermanentAdmin(String email) =>
      permanentAdminEmails.contains(email.toLowerCase().trim());

  bool get isAdmin => isPermanentAdmin(email);

  static const List<String> modules = [
    'inward',
    'calls',
    'replacements',
    'requests',
    'purchases',
    'sales',
    'pricelist',
    'settings',
  ];

  static const Map<String, String> moduleLabels = {
    'inward': 'Inward Repairs',
    'calls': 'Calls / Enquiries',
    'replacements': 'Replacements',
    'requests': 'Requests / Pre-Orders',
    'purchases': 'Purchases & Stock-In',
    'sales': 'Sales & POS Invoicing',
    'pricelist': 'Pricelist Catalog',
    'settings': 'Settings & Backup',
  };

  static const Map<String, Map<String, String>> moduleActions = {
    'inward': {
      'canAdd': 'Can Add New Inward Jobs',
      'canEdit': 'Can Edit Repair Jobs',
      'canDelete': 'Can Delete Repair Jobs',
      'canPrint': 'Can Print / Share Receipt',
      'canSendWhatsapp': 'Can Send WhatsApp Updates',
      'canConvertToSale': 'Can Convert Job to POS Sale',
      'canManageStatus': 'Can Change Repair Status',
    },
    'calls': {
      'canAdd': 'Can Add New Calls',
      'canEdit': 'Can Edit Calls',
      'canDelete': 'Can Delete Calls',
      'canTransferInward': 'Can Convert to Inward Job',
      'canConvertToSale': 'Can Convert to POS Sale',
      'canManageStatus': 'Can Change Call Status',
    },
    'replacements': {
      'canAdd': 'Can Add Replacement Record',
      'canEdit': 'Can Edit Replacement Record',
      'canDelete': 'Can Delete Replacement Record',
      'canManageStatus': 'Can Change Replacement Status',
    },
    'pricelist': {
      'canAdd': 'Can Add Catalog Item',
      'canEdit': 'Can Edit Catalog Item',
      'canDelete': 'Can Delete Catalog Item',
      'canExport': 'Can Export Catalog to Excel',
      'canDownloadStockPdf': 'Can Download Stock List PDF',
      'canViewHistory': 'Can View Product Sales & Purchase History',
    },
    'sales': {
      'canAdd': 'Can Perform POS Checkout',
      'canEdit': 'Can Edit Sales Invoice',
      'canDelete': 'Can Void / Delete Invoice',
      'canPrint': 'Can Print A5 PDF Invoice',
      'canApplyDiscount': 'Can Apply Checkout Discount',
      'canVerifyStock': 'Can Verify & Deduct Stock',
      'canOverridePrice': 'Can Override Item Unit Price',
    },
    'requests': {
      'canAdd': 'Can Add Customer Request',
      'canEdit': 'Can Edit Request',
      'canDelete': 'Can Delete Request',
      'canConvertToSale': 'Can Convert Request to Sale',
      'canManageStatus': 'Can Change Request Status',
    },
    'purchases': {
      'canAdd': 'Can Record Stock-In Purchase',
      'canEdit': 'Can Edit Purchase Order',
      'canDelete': 'Can Delete Purchase Order',
      'canManageStatus': 'Can Confirm / Revert Purchase Status',
    },
    'settings': {
      'canView': 'Can View Settings Screen',
      'canManageUpi': 'Can Configure UPI Payment Settings',
      'canManageInvoiceLayout': 'Can Configure Invoice Layout & Format',
      'canManageUsers': 'Can Access User Management & Roles',
      'canManageSync': 'Can Trigger Cloud Sync & Local Backups',
    },
  };

  static const Map<String, Map<String, String>> moduleFields = {
    'inward': {
      'date': 'Date & Time',
      'jobNo': 'Job Number',
      'name': 'Customer Name',
      'mobileNo': 'Mobile Number',
      'devices': 'Device Specs / Brand',
      'query': 'Customer Complaint / Issue',
      'estimateItems': 'Repair Cost Estimates',
      'purchasedFrom': 'Purchased Store Info',
      'status': 'Job Status',
      'notes': 'Internal Repair Notes',
      'photo': 'Device Photos',
    },
    'calls': {
      'date': 'Call Date',
      'name': 'Customer Name',
      'mobileNo': 'Mobile Number',
      'address': 'Customer Address',
      'query': 'Enquiry Query Details',
      'assignedTo': 'Assigned Technician',
      'estimate': 'Price Estimate',
      'status': 'Call Status',
      'photo1': 'Attachment Photo 1',
      'photo2': 'Attachment Photo 2',
      'notes': 'Technician Notes',
    },
    'replacements': {
      'date': 'Record Date',
      'jobNo': 'Job Code',
      'name': 'Customer Name',
      'mobileNo': 'Mobile Number',
      'item': 'Replacement Part / Item',
      'assignedTo': 'Assigned Tech',
      'depositDate': 'Deposit Date',
      'receiveDate': 'Receive Date',
      'status': 'Warranty Claim Status',
      'photo': 'Device Photo',
    },
    'pricelist': {
      'item': 'Item / Product Name',
      'category': 'Product Category',
      'cashPrice': 'Cash / Base Price',
      'inclGstPrice': 'Inclusive GST Price',
      'itemDescription': 'Item Specifications',
    },
    'sales': {
      'date': 'Invoice Date & Time',
      'customerName': 'Customer Name',
      'customerNumber': 'Mobile Number',
      'paymentMode': 'Payment Mode (Cash/UPI/Card)',
      'advance': 'Advance Paid',
      'discount': 'Applied Discount',
      'orderStatus': 'Order Status',
    },
    'requests': {
      'date': 'Pre-Order Date',
      'customerName': 'Customer Name',
      'mobileNo': 'Mobile Number',
      'item': 'Requested Special Item',
      'advance': 'Advance Payment',
      'estimate': 'Price Estimate',
      'totalAmount': 'Total Quoted Amount',
      'dealerName': 'Dealer / Vendor Sourced',
      'status': 'Order Status',
      'photo': 'Item Image',
    },
    'purchases': {
      'date': 'Purchase Date',
      'purchasedFrom': 'Supplier / Distributor',
      'stockInItems': 'Inbound Stock Line Items',
      'totalAmount': 'Total Shipment Bill Amount',
      'status': 'Stock In Confirmation Status',
      'notes': 'Shipment Notes',
    },
    'settings': {
      'generalSettings': 'General Application Preferences',
      'userManagement': 'User & Security Management',
      'backupSync': 'Database & Cloud Backups',
    },
  };

  static Map<String, Map<String, bool>> _defaultPageActionAccess() {
    final Map<String, Map<String, bool>> access = {};
    for (var mod in modules) {
      final actions = moduleActions[mod] ?? {};
      access[mod] = {for (var act in actions.keys) act: true};
    }
    return access;
  }

  static Map<String, Map<String, FieldPermission>> _defaultFieldAccess() {
    final Map<String, Map<String, FieldPermission>> access = {};
    for (var mod in modules) {
      final fields = moduleFields[mod] ?? {};
      access[mod] = {
        for (var f in fields.keys) f: FieldPermission.allTrue(),
      };
    }
    return access;
  }

  static Map<String, List<String>> _defaultStatusAccess() {
    final Map<String, List<String>> access = {};
    for (var mod in modules) {
      access[mod] = ['*'];
    }
    return access;
  }

  static Map<String, bool> _defaultOnlyAssignedAccess() {
    final Map<String, bool> access = {};
    for (var mod in modules) {
      access[mod] = false;
    }
    return access;
  }

  factory AppUser.defaultAdmin({
    String email = 'perfectsolutionnoida@gmail.com',
    String name = 'Perfect Solution Admin',
    String? password,
    Map<String, List<String>>? customStatusLists,
    Map<String, String>? defaultStatuses,
  }) {
    return AppUser(
      email: email,
      name: name,
      role: 'admin',
      isActive: true,
      password: password,
      pageAccess: {for (var m in modules) m: true},
      actionAccess: {
        'canAdd': true,
        'canEdit': true,
        'canDelete': true,
        'canDuplicate': true,
        'canConvertToSale': true,
        'canEnterInModule': true,
        'canPrint': true,
        'canExport': true,
        'canManageStatuses': true,
        'canApplyDiscount': true,
      },
      pageActionAccess: _defaultPageActionAccess(),
      fieldAccess: _defaultFieldAccess(),
      statusVisibilityAccess: _defaultStatusAccess(),
      statusSelectableAccess: _defaultStatusAccess(),
      onlyAssignedAccess: _defaultOnlyAssignedAccess(),
      customStatusLists: customStatusLists ?? {},
      defaultStatuses: defaultStatuses ?? {},
    );
  }

  factory AppUser.defaultEmployee(String email, String name) {
    return AppUser(
      email: email,
      name: name,
      role: 'employee',
      isActive: true,
      pageAccess: {
        for (var m in modules) m: m != 'settings',
      },
      actionAccess: {
        'canAdd': true,
        'canEdit': true,
        'canDelete': false,
        'canDuplicate': true,
        'canConvertToSale': true,
        'canEnterInModule': true,
        'canPrint': true,
        'canExport': false,
        'canManageStatuses': false,
        'canApplyDiscount': false,
      },
      pageActionAccess: {
        for (var m in modules)
          m: {
            for (var act in (moduleActions[m] ?? {}).keys)
              act: act == 'canView' ||
                  (act != 'canDelete' &&
                      !act.startsWith('canManage') &&
                      act != 'canExport')
          }
      },
      fieldAccess: _defaultFieldAccess(),
      statusVisibilityAccess: _defaultStatusAccess(),
      statusSelectableAccess: _defaultStatusAccess(),
      onlyAssignedAccess: _defaultOnlyAssignedAccess(),
    );
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final String email = (json['email'] ?? '').toString().toLowerCase().trim();
    final bool isUserAdmin = isPermanentAdmin(email);

    // 1. Page Access
    final rawPageAccess = json['pageAccess'] ?? json['page_access'];
    Map<String, bool> parsedPageAccess = {};
    if (rawPageAccess is Map) {
      rawPageAccess.forEach((k, v) {
        if (v is bool) parsedPageAccess[k.toString()] = v;
      });
    }
    // Fill missing module keys safely
    for (var m in modules) {
      parsedPageAccess.putIfAbsent(m, () => true);
    }

    // 2. Page Action Access
    final rawPageActions = json['pageActionAccess'] ?? json['page_action_access'];
    Map<String, Map<String, bool>> parsedPageActions = {};
    if (rawPageActions is Map) {
      rawPageActions.forEach((modKey, actMap) {
        if (actMap is Map) {
          final Map<String, bool> aMap = {};
          actMap.forEach((k, v) {
            if (v is bool) aMap[k.toString()] = v;
          });
          parsedPageActions[modKey.toString()] = aMap;
        }
      });
    }

    Map<String, Map<String, bool>> finalPageActions = {};
    for (var m in modules) {
      final defaultActions = moduleActions[m] ?? {};
      final userActions = parsedPageActions[m] ?? {};
      final Map<String, bool> aMap = {};
      for (var actKey in defaultActions.keys) {
        if (userActions.containsKey(actKey)) {
          aMap[actKey] = userActions[actKey]!;
        } else {
          final isRestrictedAction =
              actKey == 'canDelete' || actKey.startsWith('canManage');
          aMap[actKey] = isUserAdmin || !isRestrictedAction;
        }
      }
      finalPageActions[m] = aMap;
    }

    // 3. Field Access
    final rawFieldAccess = json['fieldAccess'] ?? json['field_access'];
    Map<String, Map<String, FieldPermission>> parsedFields = {};
    if (rawFieldAccess is Map) {
      rawFieldAccess.forEach((modKey, fieldMap) {
        if (fieldMap is Map) {
          final Map<String, FieldPermission> fMap = {};
          fieldMap.forEach((fKey, fVal) {
            if (fVal is Map) {
              fMap[fKey.toString()] =
                  FieldPermission.fromJson(Map<String, dynamic>.from(fVal));
            }
          });
          parsedFields[modKey.toString()] = fMap;
        }
      });
    }

    // 4. Status Visibility Access
    final rawStatusVis = json['statusVisibilityAccess'] ?? json['status_visibility_access'];
    Map<String, List<String>> parsedStatusVis = {};
    if (rawStatusVis is Map) {
      rawStatusVis.forEach((modKey, valList) {
        if (valList is List) {
          parsedStatusVis[modKey.toString()] =
              valList.map((e) => e.toString()).toList();
        }
      });
    }

    // 5. Status Selectable Access
    final rawStatusSel = json['statusSelectableAccess'] ?? json['status_selectable_access'];
    Map<String, List<String>> parsedStatusSel = {};
    if (rawStatusSel is Map) {
      rawStatusSel.forEach((modKey, valList) {
        if (valList is List) {
          parsedStatusSel[modKey.toString()] =
              valList.map((e) => e.toString()).toList();
        }
      });
    }

    // 6. Only Assigned Access
    final rawOnlyAssigned = json['onlyAssignedAccess'] ??
        json['only_assigned_access'] ??
        parsedPageActions['__only_assigned__'] ??
        (rawPageActions is Map ? rawPageActions['__only_assigned__'] : null);
    Map<String, bool> parsedOnlyAssigned = {};
    if (rawOnlyAssigned is Map) {
      rawOnlyAssigned.forEach((k, v) {
        if (v is bool) {
          parsedOnlyAssigned[k.toString()] = v;
        } else if (v is String) {
          parsedOnlyAssigned[k.toString()] = v.toLowerCase() == 'true';
        }
      });
    }

    // 7. Custom Status Lists
    final rawCustomLists = json['customStatusLists'] ??
        json['custom_status_lists'] ??
        parsedPageActions['__status_lists__'] ??
        (rawPageActions is Map ? rawPageActions['__status_lists__'] : null);
    Map<String, List<String>> parsedCustomLists = {};
    if (rawCustomLists is Map) {
      rawCustomLists.forEach((modKey, valList) {
        if (valList is List) {
          parsedCustomLists[modKey.toString()] =
              valList.map((e) => e.toString()).toList();
        }
      });
    }

    // 8. Default Form Statuses
    final rawDefaultStatuses = json['defaultStatuses'] ??
        json['default_statuses'] ??
        parsedPageActions['__default_statuses__'] ??
        (rawPageActions is Map ? rawPageActions['__default_statuses__'] : null);
    Map<String, String> parsedDefaultStatuses = {};
    if (rawDefaultStatuses is Map) {
      rawDefaultStatuses.forEach((modKey, val) {
        parsedDefaultStatuses[modKey.toString()] = val.toString();
      });
    }

    return AppUser(
      email: email,
      name: json['name'] ?? '',
      role: json['role'] ?? 'employee',
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      password: json['password'] ?? json['user_password'],
      pageAccess: parsedPageAccess,
      actionAccess: Map<String, bool>.from(json['actionAccess'] ?? json['action_access'] ?? {}),
      pageActionAccess: finalPageActions,
      fieldAccess: parsedFields.isEmpty ? _defaultFieldAccess() : parsedFields,
      statusVisibilityAccess:
          parsedStatusVis.isEmpty ? _defaultStatusAccess() : parsedStatusVis,
      statusSelectableAccess:
          parsedStatusSel.isEmpty ? _defaultStatusAccess() : parsedStatusSel,
      onlyAssignedAccess:
          parsedOnlyAssigned.isEmpty ? _defaultOnlyAssignedAccess() : parsedOnlyAssigned,
      customStatusLists: parsedCustomLists,
      defaultStatuses: parsedDefaultStatuses,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> serializedFields = {};
    fieldAccess.forEach((modKey, fMap) {
      final Map<String, dynamic> fSerialized = {};
      fMap.forEach((fKey, fPerm) {
        fSerialized[fKey] = fPerm.toJson();
      });
      serializedFields[modKey] = fSerialized;
    });

    // Embed onlyAssignedAccess, customStatusLists, and defaultStatuses into pageActionAccess for seamless cloud sync
    final Map<String, dynamic> mergedPageActions = {};
    pageActionAccess.forEach((k, v) {
      if (k != '__only_assigned__' &&
          k != '__status_lists__' &&
          k != '__default_statuses__') {
        mergedPageActions[k] = Map<String, bool>.from(v);
      }
    });
    mergedPageActions['__only_assigned__'] = onlyAssignedAccess;
    mergedPageActions['__status_lists__'] = customStatusLists;
    mergedPageActions['__default_statuses__'] = defaultStatuses;

    return {
      'email': email,
      'name': name,
      'role': role,
      'isActive': isActive,
      'password': password,
      'pageAccess': pageAccess,
      'actionAccess': actionAccess,
      'pageActionAccess': mergedPageActions,
      'fieldAccess': serializedFields,
      'statusVisibilityAccess': statusVisibilityAccess,
      'statusSelectableAccess': statusSelectableAccess,
      'onlyAssignedAccess': onlyAssignedAccess,
      'customStatusLists': customStatusLists,
      'defaultStatuses': defaultStatuses,
    };
  }

  AppUser copyWith({
    String? email,
    String? name,
    String? role,
    bool? isActive,
    String? password,
    Map<String, bool>? pageAccess,
    Map<String, bool>? actionAccess,
    Map<String, Map<String, bool>>? pageActionAccess,
    Map<String, Map<String, FieldPermission>>? fieldAccess,
    Map<String, List<String>>? statusVisibilityAccess,
    Map<String, List<String>>? statusSelectableAccess,
    Map<String, bool>? onlyAssignedAccess,
    Map<String, List<String>>? customStatusLists,
    Map<String, String>? defaultStatuses,
  }) {
    return AppUser(
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      password: password ?? this.password,
      pageAccess: pageAccess ?? Map.from(this.pageAccess),
      actionAccess: actionAccess ?? Map.from(this.actionAccess),
      pageActionAccess: pageActionAccess ?? Map.from(this.pageActionAccess),
      fieldAccess: fieldAccess ?? Map.from(this.fieldAccess),
      statusVisibilityAccess:
          statusVisibilityAccess ?? Map.from(this.statusVisibilityAccess),
      statusSelectableAccess:
          statusSelectableAccess ?? Map.from(this.statusSelectableAccess),
      onlyAssignedAccess:
          onlyAssignedAccess ?? Map.from(this.onlyAssignedAccess),
      customStatusLists:
          customStatusLists ?? Map.from(this.customStatusLists),
      defaultStatuses:
          defaultStatuses ?? Map.from(this.defaultStatuses),
    );
  }
}

