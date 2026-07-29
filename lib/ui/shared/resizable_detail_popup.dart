import 'package:flutter/material.dart';
import '../../data/repositories/shop_repository.dart';
import '../core/app_theme.dart';

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

  /// Shows a resizable detail popup as a dialog.
  static Future<void> show({
    required BuildContext context,
    required String title,
    String? subtitle,
    required Widget Function(BuildContext context, double scaleFactor)
    contentBuilder,
    Widget Function(BuildContext context, double scaleFactor)? actionsBuilder,
    required ShopRepository repository,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => ResizableDetailPopup(
        title: title,
        subtitle: subtitle,
        contentBuilder: contentBuilder,
        actionsBuilder: actionsBuilder,
        repository: repository,
      ),
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
                                  fontSize: 16 * scale,
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
                                    fontSize: 11 * scale,
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
  final double scaleFactor;
  final double labelWidth;

  const ScaledInfoRow({
    super.key,
    required this.label,
    required this.value,
    required this.scaleFactor,
    this.labelWidth = 140,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3 * scaleFactor),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth * scaleFactor,
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12 * scaleFactor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12 * scaleFactor,
              ),
            ),
          ),
        ],
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
