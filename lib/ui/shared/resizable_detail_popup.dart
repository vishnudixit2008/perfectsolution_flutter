import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/repositories/shop_repository.dart';
import '../../data/services/map_directions_service.dart';
import '../core/app_theme.dart';
import '../core/motion/motion.dart';

/// A shared resizable detail popup dialog that persists its size across sessions.
/// All pages should use this widget for showing entry details.
///
/// The dialog can be resized by dragging the edges or corners.
/// Content scales proportionally with the dialog size.
/// Size is persisted in Hive via [ShopRepository].
class ResizableDetailPopup extends StatefulWidget {
  /// The title shown at the top of the popup.
  final String title;

  /// Subtitle text (e.g. date, ID).
  final String? subtitle;

  /// Builder for the main content area. Receives a [scaleFactor] that
  /// indicates how much content should scale relative to the base size.
  final Widget Function(BuildContext context, double scaleFactor)
  contentBuilder;

  /// Builder for the action buttons area. Receives the same [scaleFactor].
  final Widget Function(BuildContext context, double scaleFactor)?
  actionsBuilder;

  /// The repository instance for persisting size.
  final ShopRepository repository;

  const ResizableDetailPopup({
    super.key,
    required this.title,
    this.subtitle,
    required this.contentBuilder,
    this.actionsBuilder,
    required this.repository,
  });

  @override
  State<ResizableDetailPopup> createState() => _ResizableDetailPopupState();

  /// Shows a resizable detail popup as an Apple-grade spring scale-in dialog.
  static Future<void> show({
    required BuildContext context,
    required String title,
    String? subtitle,
    required Widget Function(BuildContext context, double scaleFactor)
    contentBuilder,
    Widget Function(BuildContext context, double scaleFactor)? actionsBuilder,
    required ShopRepository repository,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Dialog',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: AppleMotion.quick,
      pageBuilder: (ctx, anim1, anim2) => ResizableDetailPopup(
        title: title,
        subtitle: subtitle,
        contentBuilder: contentBuilder,
        actionsBuilder: actionsBuilder,
        repository: repository,
      ),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: AppleMotion.spring,
          reverseCurve: AppleMotion.modalExitCurve,
        );
        final scale = Tween<double>(
          begin: AppleMotion.modalEntryScale,
          end: 1.0,
        ).animate(curved);
        final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: anim,
            curve: Curves.easeOut,
            reverseCurve: AppleMotion.modalExitCurve,
          ),
        );
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: child,
          ),
        );
      },
    );
  }
}

class _ResizableDetailPopupState extends State<ResizableDetailPopup> {
  // Base dimensions for scale factor calculation
  static const double _baseWidth = 520.0;
  static const double _baseHeight = 560.0;
  static const double _minWidth = 360.0;
  static const double _minHeight = 320.0;
  static const double _maxWidth = 1000.0;
  static const double _maxHeight = 900.0;

  late double _width;
  late double _height;

  @override
  void initState() {
    super.initState();
    // Load persisted size or use defaults
    _width = widget.repository.getDetailPopupWidth() ?? _baseWidth;
    _height = widget.repository.getDetailPopupHeight() ?? _baseHeight;
  }

  double get _scaleFactor {
    // Scale based on the average of width and height ratios
    final wRatio = _width / _baseWidth;
    final hRatio = _height / _baseHeight;
    return ((wRatio + hRatio) / 2).clamp(0.7, 1.6);
  }

  void _onResize(DragUpdateDetails details) {
    setState(() {
      _width = (_width + details.delta.dx).clamp(_minWidth, _maxWidth);
      _height = (_height + details.delta.dy).clamp(_minHeight, _maxHeight);
    });
  }

  void _persistSize() {
    widget.repository.saveDetailPopupSize(_width, _height);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scaleFactor;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Main dialog container
            Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                color: const Color(0xFF131A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.all(16 * scale),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                  fontSize: 17 * scale,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.subtitle != null) ...[
                                SizedBox(height: 2 * scale),
                                Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11.5 * scale,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: AppTheme.textPrimary,
                            size: 20 * scale,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable content area
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(16 * scale),
                      child: widget.contentBuilder(context, scale),
                    ),
                  ),

                  // Actions area (optional)
                  if (widget.actionsBuilder != null)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16 * scale,
                        vertical: 12 * scale,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      child: widget.actionsBuilder!(context, scale),
                    ),
                ],
              ),
            ),

            // Bottom-right resize handle
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  onPanUpdate: _onResize,
                  onPanEnd: (_) => _persistSize(),
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ),

            // Right edge resize handle
            Positioned(
              right: 0,
              top: 40,
              bottom: 20,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRight,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _width = (_width + details.delta.dx).clamp(
                        _minWidth,
                        _maxWidth,
                      );
                    });
                  },
                  onHorizontalDragEnd: (_) => _persistSize(),
                  child: Container(width: 6, color: Colors.transparent),
                ),
              ),
            ),

            // Bottom edge resize handle
            Positioned(
              bottom: 0,
              left: 20,
              right: 20,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDown,
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      _height = (_height + details.delta.dy).clamp(
                        _minHeight,
                        _maxHeight,
                      );
                    });
                  },
                  onVerticalDragEnd: (_) => _persistSize(),
                  child: Container(height: 6, color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper widget for building scaled info rows inside the resizable popup.
class ScaledInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? valueWidget;
  final Widget? trailing;
  final double scaleFactor;
  final double labelWidth;
  final CrossAxisAlignment crossAxisAlignment;

  const ScaledInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
    this.trailing,
    required this.scaleFactor,
    this.labelWidth = 160,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0 * scaleFactor),
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          SizedBox(
            width: labelWidth * scaleFactor,
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12.5 * scaleFactor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: valueWidget ??
                      Text(
                        value,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12.5 * scaleFactor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                ),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact, beautiful inline call button for mobile devices/users.
class InlineCallButton extends StatelessWidget {
  final String phone;
  final double scaleFactor;

  const InlineCallButton({
    super.key,
    required this.phone,
    this.scaleFactor = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final bool isMobileDevice = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!isMobileDevice && AppleMotion.isDesktop) {
      return const SizedBox.shrink();
    }

    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(left: 8 * scaleFactor),
      child: BouncyPressable(
        scaleFactor: 0.90,
        onTap: () async {
          final uri = Uri.parse('tel:$cleaned');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 7 * scaleFactor,
            vertical: 2 * scaleFactor,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
              width: 0.8 * scaleFactor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.call_rounded,
                size: 11 * scaleFactor,
                color: const Color(0xFF34D399),
              ),
              SizedBox(width: 3.5 * scaleFactor),
              Text(
                'Call',
                style: TextStyle(
                  fontSize: 10.5 * scaleFactor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: const Color(0xFF34D399),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact, interactive inline button to open Google Maps directions for a given address.
class InlineDirectionsButton extends StatelessWidget {
  final String address;
  final double scaleFactor;

  const InlineDirectionsButton({
    super.key,
    required this.address,
    this.scaleFactor = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cleaned = MapDirectionsService.normalizeAddress(address);
    if (cleaned.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(left: 8 * scaleFactor),
      child: Tooltip(
        message: 'Get directions in Google Maps',
        child: BouncyPressable(
          scaleFactor: 0.90,
          onTap: () => MapDirectionsService.openDirections(address),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 7 * scaleFactor,
              vertical: 2 * scaleFactor,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                width: 0.8 * scaleFactor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.directions_rounded,
                  size: 11 * scaleFactor,
                  color: const Color(0xFF38BDF8),
                ),
                SizedBox(width: 3.5 * scaleFactor),
                Text(
                  'Directions',
                  style: TextStyle(
                    fontSize: 10.5 * scaleFactor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: const Color(0xFF38BDF8),
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper widget for building scaled action buttons inside the resizable popup.
class ScaledActionButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;
  final double scaleFactor;
  final Color? color;

  const ScaledActionButton({
    super.key,
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onTap,
    required this.scaleFactor,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? AppTheme.primaryLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 90 * scaleFactor,
        padding: EdgeInsets.symmetric(vertical: 6 * scaleFactor),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18 * scaleFactor,
              backgroundColor: buttonColor.withValues(alpha: 0.1),
              child:
                  iconWidget ??
                  Icon(icon, color: buttonColor, size: 18 * scaleFactor),
            ),
            SizedBox(height: 4 * scaleFactor),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11 * scaleFactor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
