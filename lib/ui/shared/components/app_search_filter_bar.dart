import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/motion/motion_tokens.dart';
import '../../core/motion/bouncy_pressable.dart';

class AppSearchFilterBar extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String hintText;
  final int activeFilterCount;
  final Widget? filterOptions;

  const AppSearchFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    this.hintText = 'Search...',
    this.activeFilterCount = 0,
    this.filterOptions,
  });

  @override
  State<AppSearchFilterBar> createState() => _AppSearchFilterBarState();
}

class _AppSearchFilterBarState extends State<AppSearchFilterBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isExpanded = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
    _focusNode = FocusNode();
    _isExpanded = widget.searchQuery.isNotEmpty || widget.activeFilterCount > 0;

    _focusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isFocused = _focusNode.hasFocus;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant AppSearchFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        _controller.text != widget.searchQuery) {
      _controller.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _expandAndFocus() {
    setState(() {
      _isExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double verticalMargin = isMobile ? 6.0 : 8.0;
    final double collapsedPaddingV = isMobile ? 8.0 : 9.0;
    final double expandedPadding = isMobile ? 8.0 : 10.0;

    if (!_isExpanded) {
      return Container(
        margin: EdgeInsets.only(bottom: verticalMargin),
        child: BouncyPressable(
          scaleFactor: 0.98,
          onTap: _expandAndFocus,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: collapsedPaddingV),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: AppTheme.textMuted.withValues(alpha: 0.7),
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.searchQuery.isNotEmpty
                        ? 'Search: "${widget.searchQuery}"'
                        : widget.hintText,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: widget.searchQuery.isNotEmpty
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted.withValues(alpha: 0.5),
                      fontWeight: widget.searchQuery.isNotEmpty
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.activeFilterCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${widget.activeFilterCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.tune_rounded,
                  color: AppTheme.textMuted.withValues(alpha: 0.8),
                  size: 15,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: verticalMargin),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: AppleMotion.easeOut,
        padding: EdgeInsets.all(expandedPadding),
        decoration: BoxDecoration(
          color: _isFocused
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: _isFocused
                ? AppTheme.primaryLight.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.18),
                    blurRadius: 12,
                    spreadRadius: 0.5,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedScale(
                  scale: _isFocused ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: AppleMotion.spring,
                  child: Icon(
                    Icons.search_rounded,
                    color: _isFocused
                        ? AppTheme.primaryLight
                        : AppTheme.textMuted.withValues(alpha: 0.7),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: widget.onSearchChanged,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.1,
                    ),
                    cursorColor: AppTheme.primaryLight,
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.5),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  BouncyPressable(
                    scaleFactor: 0.88,
                    onTap: () {
                      _controller.clear();
                      widget.onSearchChanged('');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(3.0),
                      child: Icon(
                        Icons.cancel_rounded,
                        size: 15,
                        color: AppTheme.textMuted.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                BouncyPressable(
                  scaleFactor: 0.90,
                  onTap: () => setState(() => _isExpanded = false),
                  child: Padding(
                    padding: const EdgeInsets.all(3.0),
                    child: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: AppTheme.textMuted.withValues(alpha: 0.8),
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.filterOptions != null) ...[
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 12),
              widget.filterOptions!,
            ],
          ],
        ),
      ),
    );
  }
}
