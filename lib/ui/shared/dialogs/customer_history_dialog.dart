import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/models/customer_profile.dart';
import '../../../data/models/inward_repair.dart';
import '../../../data/models/sale.dart';
import '../../../data/models/call_model.dart';
import '../../../data/models/replacement.dart';
import '../../../data/models/request_order.dart';
import '../../../data/repositories/shop_repository.dart';
import '../../../data/services/customer_directory_service.dart';
import '../../../data/services/user_permission_service.dart';
import '../../../data/services/whatsapp_service.dart';
import '../../core/app_theme.dart';
import '../../core/motion/motion.dart';
import '../../features/calls/views/calls_view.dart';
import '../../features/inward_repairs/views/inward_repairs_view.dart';
import '../../features/replacements/views/replacements_view.dart';
import '../../features/requests/views/requests_view.dart';
import '../../features/sales/views/sales_view.dart';
import '../components/app_status_chip.dart';

class CustomerHistoryDialog extends StatefulWidget {
  final CustomerProfile? initialProfile;
  final String? phone;

  const CustomerHistoryDialog({
    super.key,
    this.initialProfile,
    this.phone,
  });

  static Future<void> show(
    BuildContext context, {
    CustomerProfile? profile,
    String? phone,
    String? moduleKey,
  }) {
    if (moduleKey != null && !UserPermissionService.canViewCustomerHistory(moduleKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to view customer history in this module.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return Future.value();
    }
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Customer History',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) =>
          CustomerHistoryDialog(
        initialProfile: profile,
        phone: phone,
      ),
    );
  }

  static void openEventDetails(BuildContext context, CustomerTimelineEvent event) {
    final raw = event.rawObject;

    switch (event.type) {
      case CustomerEventType.inwardRepair:
        if (raw is InwardRepair) {
          InwardRepairsView.showDetailDialog(context, raw);
        }
        break;
      case CustomerEventType.sale:
        if (raw is Sale) {
          SalesView.showInvoiceDetailsSheet(context, raw);
        }
        break;
      case CustomerEventType.call:
        if (raw is CallModel) {
          CallsView.showDetailPopup(context, raw);
        }
        break;
      case CustomerEventType.replacement:
        if (raw is Replacement) {
          ReplacementsView.showDetailDialog(context, raw);
        }
        break;
      case CustomerEventType.request:
        if (raw is RequestOrder) {
          RequestsView.showDetailDialog(context, raw);
        }
        break;
    }
  }

  static Color getCategoryColor(CustomerEventType type) => switch (type) {
    CustomerEventType.inwardRepair => const Color(0xFF3B82F6),
    CustomerEventType.sale => const Color(0xFF10B981),
    CustomerEventType.call => const Color(0xFFA855F7),
    CustomerEventType.replacement => const Color(0xFFF97316),
    CustomerEventType.request => const Color(0xFFF59E0B),
  };

  static IconData getCategoryIcon(CustomerEventType type) => switch (type) {
    CustomerEventType.inwardRepair => Icons.build_circle_rounded,
    CustomerEventType.sale => Icons.shopping_bag_rounded,
    CustomerEventType.call => Icons.phone_in_talk_rounded,
    CustomerEventType.replacement => Icons.change_circle_rounded,
    CustomerEventType.request => Icons.bookmark_added_rounded,
  };

  static String getCategoryLabel(CustomerEventType type) => switch (type) {
    CustomerEventType.inwardRepair => 'Inward Repair',
    CustomerEventType.sale => 'Sale Invoice',
    CustomerEventType.call => 'Customer Call',
    CustomerEventType.replacement => 'Replacement',
    CustomerEventType.request => 'Request Order',
  };

  static String getModuleForType(CustomerEventType type) => switch (type) {
    CustomerEventType.inwardRepair => 'inward',
    CustomerEventType.sale => 'sales',
    CustomerEventType.call => 'calls',
    CustomerEventType.replacement => 'replacements',
    CustomerEventType.request => 'requests',
  };

  @override
  State<CustomerHistoryDialog> createState() => _CustomerHistoryDialogState();
}

class _CustomerHistoryDialogState extends State<CustomerHistoryDialog> {
  CustomerProfile? _profile;
  String _selectedFilter = 'ALL';
  StreamSubscription<String>? _tableSub;
  final currencyFormat = NumberFormat.currency(
    symbol: '₹',
    decimalDigits: 0,
    locale: 'en_IN',
  );

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _tableSub = ShopRepository.tableDataChangedStream.listen((table) {
      if (mounted) {
        setState(() {
          _refreshProfile();
        });
      }
    });
  }

  @override
  void dispose() {
    _tableSub?.cancel();
    super.dispose();
  }

  void _loadProfile() {
    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
    } else if (widget.phone != null) {
      _profile =
          CustomerDirectoryService.instance.lookupCustomer(widget.phone);
    }
  }

  void _refreshProfile() {
    final phone = widget.phone ?? _profile?.canonicalPhone;
    if (phone != null && phone.isNotEmpty) {
      final updated = CustomerDirectoryService.instance.lookupCustomer(phone);
      if (updated != null) {
        _profile = updated;
      }
    }
  }

  Color _getCategoryColor(CustomerEventType type) => switch (type) {
    CustomerEventType.inwardRepair => const Color(0xFF3B82F6),
    CustomerEventType.sale => const Color(0xFF10B981),
    CustomerEventType.call => const Color(0xFFA855F7),
    CustomerEventType.replacement => const Color(0xFFF97316),
    CustomerEventType.request => const Color(0xFFF59E0B),
  };

  IconData _getCategoryIcon(CustomerEventType type) => switch (type) {
    CustomerEventType.inwardRepair => Icons.build_circle_rounded,
    CustomerEventType.sale => Icons.shopping_bag_rounded,
    CustomerEventType.call => Icons.phone_in_talk_rounded,
    CustomerEventType.replacement => Icons.change_circle_rounded,
    CustomerEventType.request => Icons.bookmark_added_rounded,
  };

  String _getCategoryLabel(CustomerEventType type) => switch (type) {
    CustomerEventType.inwardRepair => 'Inward Repair',
    CustomerEventType.sale => 'Sale Invoice',
    CustomerEventType.call => 'Customer Call',
    CustomerEventType.replacement => 'Replacement',
    CustomerEventType.request => 'Request Order',
  };

  List<CustomerTimelineEvent> get _filteredEvents {
    if (_profile == null) return [];
    if (_selectedFilter == 'ALL') return _profile!.events;

    return _profile!.events.where((e) {
      switch (_selectedFilter) {
        case 'INWARD':
          return e.type == CustomerEventType.inwardRepair;
        case 'SALES':
          return e.type == CustomerEventType.sale;
        case 'CALLS':
          return e.type == CustomerEventType.call;
        case 'REPLACEMENTS':
          return e.type == CustomerEventType.replacement;
        case 'REQUESTS':
          return e.type == CustomerEventType.request;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenWidth < 650;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: isCompact ? 20 : 32,
      ),
      child: Center(
        child: Container(
          width: isCompact ? double.infinity : 680,
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.90,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A), // Luxury Dark Slate
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF334155).withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.12),
                blurRadius: 48,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(isCompact),
                if (_profile != null) ...[
                  _buildMetricsBar(isCompact),
                  _buildFilterChips(),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFF1E293B),
                  ),
                  Flexible(
                    child: _buildTimeline(),
                  ),
                ] else ...[
                  _buildNotFoundState(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    final profile = _profile;
    final String rawName = profile?.displayName ?? 'Customer Profile';
    final String phoneStr = profile != null
        ? CustomerDirectoryService.formatDisplayPhone(profile.canonicalPhone)
        : (widget.phone ?? 'Unknown Phone');

    final initials = rawName
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 24,
        vertical: isCompact ? 16 : 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: isCompact ? 44 : 52,
            height: isCompact ? 44 : 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials.isNotEmpty ? initials : '👤',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: isCompact ? 16 : 19,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name and Phone
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rawName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isCompact ? 17 : 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.phone_iphone_rounded,
                      size: 13,
                      color: const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      phoneStr,
                      style: TextStyle(
                        color: const Color(0xFFCBD5E1),
                        fontSize: isCompact ? 12.5 : 13.5,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action Buttons: WhatsApp + Call
          if (profile != null) ...[
            _buildActionIcon(
              tooltip: 'Send WhatsApp Message',
              icon: Icons.chat_bubble_outline_rounded,
              color: const Color(0xFF22C55E),
              backgroundColor: const Color(0xFF22C55E).withValues(alpha: 0.12),
              onTap: () => WhatsAppService.launch(
                mobileNo: profile.canonicalPhone,
                message: 'Hello ${profile.displayName}, Greetings from our shop!',
              ),
            ),
            const SizedBox(width: 8),
            _buildActionIcon(
              tooltip: 'Call Phone',
              icon: Icons.call_outlined,
              color: const Color(0xFF38BDF8),
              backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.12),
              onTap: () async {
                final uri = Uri.parse('tel:${profile.canonicalPhone}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            const SizedBox(width: 12),
          ],

          // Close button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: const Color(0xFF94A3B8),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon({
    required String tooltip,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: BouncyPressable(
        scaleFactor: 0.92,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  Widget _buildMetricsBar(bool isCompact) {
    final profile = _profile!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 14 : 22,
        vertical: 12,
      ),
      color: const Color(0xFF111C30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricItem(
            label: 'Total Visits',
            value: '${profile.visitCount}',
            icon: Icons.history_rounded,
            accentColor: const Color(0xFF60A5FA),
          ),
          Container(
            width: 1,
            height: 28,
            color: const Color(0xFF334155).withValues(alpha: 0.6),
          ),
          _buildMetricItem(
            label: 'Total Spend',
            value: profile.totalSpent > 0
                ? currencyFormat.format(profile.totalSpent)
                : '₹0',
            icon: Icons.payments_outlined,
            accentColor: const Color(0xFF34D399),
          ),
          if (!isCompact && profile.lastVisitDate != null) ...[
            Container(
              width: 1,
              height: 28,
              color: const Color(0xFF334155).withValues(alpha: 0.6),
            ),
            _buildMetricItem(
              label: 'Last Visit',
              value: DateFormat('dd MMM yyyy').format(profile.lastVisitDate!),
              icon: Icons.calendar_today_rounded,
              accentColor: const Color(0xFFFBBF24),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: accentColor),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final profile = _profile!;
    final filters = <Map<String, dynamic>>[
      {'id': 'ALL', 'label': 'All Activity', 'count': profile.visitCount},
      if (profile.inwardCount > 0)
        {'id': 'INWARD', 'label': 'Inward', 'count': profile.inwardCount},
      if (profile.salesCount > 0)
        {'id': 'SALES', 'label': 'Sales', 'count': profile.salesCount},
      if (profile.callsCount > 0)
        {'id': 'CALLS', 'label': 'Calls', 'count': profile.callsCount},
      if (profile.replacementsCount > 0)
        {
          'id': 'REPLACEMENTS',
          'label': 'Replacements',
          'count': profile.replacementsCount
        },
      if (profile.requestsCount > 0)
        {'id': 'REQUESTS', 'label': 'Requests', 'count': profile.requestsCount},
    ];

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = filters[index];
          final isSelected = _selectedFilter == f['id'];

          return Center(
            child: BouncyPressable(
              scaleFactor: 0.94,
              onTap: () => setState(() => _selectedFilter = f['id'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryLight
                        : const Color(0xFF334155),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f['label'] as String,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFFCBD5E1),
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.22)
                            : const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${f['count']}',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF94A3B8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeline() {
    final events = _filteredEvents;

    if (events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 42,
                color: const Color(0xFF64748B),
              ),
              const SizedBox(height: 12),
              const Text(
                'No activity found in this category.',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isLast = index == events.length - 1;
        return _buildTimelineItem(event, isLast);
      },
    );
  }

  Widget _buildTimelineItem(CustomerTimelineEvent event, bool isLast) {
    final categoryColor = _getCategoryColor(event.type);
    final categoryIcon = _getCategoryIcon(event.type);
    final categoryLabel = _getCategoryLabel(event.type);

    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(event.timestamp);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Timeline Column (Node + Connecting Line)
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: categoryColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: categoryColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(categoryIcon, size: 14, color: categoryColor),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: const Color(0xFF334155),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Right Content Card (Clickable to open exact module detail)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF334155).withValues(alpha: 0.7),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openEventDetails(context, event),
                  hoverColor: categoryColor.withValues(alpha: 0.08),
                  splashColor: categoryColor.withValues(alpha: 0.12),
                  highlightColor: categoryColor.withValues(alpha: 0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Top Row: Category Pill + Date
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: categoryColor.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                categoryLabel,
                                style: TextStyle(
                                  color: categoryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Title & Amount
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                event.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (event.amount != null && event.amount! > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  currencyFormat.format(event.amount),
                                  style: const TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Subtitle / Devices / Issue
                        Text(
                          event.subtitle,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),

                        if (event.address != null &&
                            event.address!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  event.address!,
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 10),

                        // Status Badge + View details hint
                        Row(
                          children: [
                            AppStatusChip(
                              status: event.status,
                              moduleKey: _getModuleForType(event.type),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View details',
                                  style: TextStyle(
                                    color: categoryColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: categoryColor,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _openEventDetails(BuildContext context, CustomerTimelineEvent event) =>
      CustomerHistoryDialog.openEventDetails(context, event);

  String _getModuleForType(CustomerEventType type) =>
      CustomerHistoryDialog.getModuleForType(type);

  Widget _buildNotFoundState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_search_rounded,
                size: 48,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Prior Customer History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No previous visits or orders were found for ${widget.phone ?? "this phone number"}.\nThis will be registered as a new customer.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A responsive, embedded side panel widget for displaying full customer history.
/// Used in Desktop create/edit dialogs alongside the form, or in POS Billing Desk.
class CustomerHistorySidePanel extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback? onClose;
  final bool showCloseButton;
  final String title;

  const CustomerHistorySidePanel({
    super.key,
    required this.profile,
    this.onClose,
    this.showCloseButton = false,
    this.title = 'Customer History',
  });

  @override
  State<CustomerHistorySidePanel> createState() =>
      _CustomerHistorySidePanelState();
}

class _CustomerHistorySidePanelState extends State<CustomerHistorySidePanel> {
  String _selectedFilter = 'ALL';
  final currencyFormat = NumberFormat.currency(
    symbol: '₹',
    decimalDigits: 0,
    locale: 'en_IN',
  );

  List<CustomerTimelineEvent> get _filteredEvents {
    if (_selectedFilter == 'ALL') return widget.profile.events;

    return widget.profile.events.where((e) {
      switch (_selectedFilter) {
        case 'INWARD':
          return e.type == CustomerEventType.inwardRepair;
        case 'SALES':
          return e.type == CustomerEventType.sale;
        case 'CALLS':
          return e.type == CustomerEventType.call;
        case 'REPLACEMENTS':
          return e.type == CustomerEventType.replacement;
        case 'REQUESTS':
          return e.type == CustomerEventType.request;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final initials = profile.displayName
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    final filters = [
      {'id': 'ALL', 'label': 'All', 'count': profile.events.length},
      if (profile.inwardCount > 0)
        {'id': 'INWARD', 'label': 'Inward', 'count': profile.inwardCount},
      if (profile.salesCount > 0)
        {'id': 'SALES', 'label': 'Sales', 'count': profile.salesCount},
      if (profile.callsCount > 0)
        {'id': 'CALLS', 'label': 'Calls', 'count': profile.callsCount},
      if (profile.replacementsCount > 0)
        {
          'id': 'REPLACEMENTS',
          'label': 'Replacements',
          'count': profile.replacementsCount,
        },
      if (profile.requestsCount > 0)
        {'id': 'REQUESTS', 'label': 'Requests', 'count': profile.requestsCount},
    ];

    final events = _filteredEvents;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF334155).withValues(alpha: 0.8),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Side panel header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF334155), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        initials.isNotEmpty ? initials : '👤',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          CustomerDirectoryService.formatDisplayPhone(
                            profile.canonicalPhone,
                          ),
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: AppTheme.primaryLight.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 12,
                          color: AppTheme.primaryLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${profile.events.length} records',
                          style: const TextStyle(
                            color: AppTheme.primaryLight,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.showCloseButton) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: const Color(0xFF94A3B8),
                      onPressed: widget.onClose,
                      splashRadius: 16,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),

            // Metrics Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF111C30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetric(
                    'Visits',
                    '${profile.visitCount}',
                    Icons.history_rounded,
                    const Color(0xFF60A5FA),
                  ),
                  Container(width: 1, height: 20, color: const Color(0xFF334155)),
                  _buildMetric(
                    'Spent',
                    profile.totalSpent > 0
                        ? currencyFormat.format(profile.totalSpent)
                        : '₹0',
                    Icons.payments_outlined,
                    const Color(0xFF34D399),
                  ),
                  if (profile.lastVisitDate != null) ...[
                    Container(width: 1, height: 20, color: const Color(0xFF334155)),
                    _buildMetric(
                      'Last Visit',
                      DateFormat('dd MMM').format(profile.lastVisitDate!),
                      Icons.calendar_today_rounded,
                      const Color(0xFFFBBF24),
                    ),
                  ],
                ],
              ),
            ),

            // Filter chips
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final f = filters[index];
                  final isSelected = _selectedFilter == f['id'];
                  return Center(
                    child: InkWell(
                      onTap: () => setState(() => _selectedFilter = f['id'] as String),
                      borderRadius: BorderRadius.circular(100),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primary
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryLight
                                : const Color(0xFF334155),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              f['label'] as String,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFFCBD5E1),
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${f['count']}',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF94A3B8),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1, thickness: 1, color: Color(0xFF1E293B)),

            // Timeline
            Expanded(
              child: events.isEmpty
                  ? const Center(
                      child: Text(
                        'No history in this category.',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index];
                        final isLast = index == events.length - 1;
                        return _buildTimelineItem(context, event, isLast);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    CustomerTimelineEvent event,
    bool isLast,
  ) {
    final catColor = CustomerHistoryDialog.getCategoryColor(event.type);
    final catIcon = CustomerHistoryDialog.getCategoryIcon(event.type);
    final catLabel = CustomerHistoryDialog.getCategoryLabel(event.type);
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(event.timestamp);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Node
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: catColor, width: 1.5),
                  ),
                  child: Center(
                    child: Icon(catIcon, size: 11, color: catColor),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFF334155),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF334155).withValues(alpha: 0.7),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => CustomerHistoryDialog.openEventDetails(context, event),
                  hoverColor: catColor.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                catLabel,
                                style: TextStyle(
                                  color: catColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                event.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (event.amount != null && event.amount! > 0)
                              Text(
                                currencyFormat.format(event.amount),
                                style: const TextStyle(
                                  color: Color(0xFF34D399),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          event.subtitle,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 11.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            AppStatusChip(
                              status: event.status,
                              moduleKey: CustomerHistoryDialog.getModuleForType(event.type),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View',
                                  style: TextStyle(
                                    color: catColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: catColor,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

