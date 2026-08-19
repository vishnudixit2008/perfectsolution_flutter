import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/motion/motion_tokens.dart';
import '../../core/motion/bouncy_pressable.dart';

/// An ultra-sleek, Apple-inspired translucent search bar with clean hairline borders,
/// subtle focus transitions, and minimal visual noise.
class AppAnimatedSearchBar extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String hintText;
  final FocusNode? focusNode;
  final double? height;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Widget? trailing;

  const AppAnimatedSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.onClear,
    this.hintText = 'Search...',
    this.focusNode,
    this.height,
    this.maxWidth,
    this.padding,
    this.margin,
    this.trailing,
  });

  @override
  State<AppAnimatedSearchBar> createState() => _AppAnimatedSearchBarState();
}

class _AppAnimatedSearchBarState extends State<AppAnimatedSearchBar> {
  late final TextEditingController _internalController;
  late final FocusNode _internalFocusNode;
  bool _isFocused = false;
  bool _hasText = false;

  TextEditingController get _effectiveController =>
      widget.controller ?? _internalController;
  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController();
    }
    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode();
    }

    _effectiveFocusNode.addListener(_handleFocusChange);
    _effectiveController.addListener(_handleTextChange);
    _hasText = _effectiveController.text.isNotEmpty;
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _effectiveFocusNode.hasFocus;
      });
    }
  }

  void _handleTextChange() {
    final hasText = _effectiveController.text.isNotEmpty;
    if (hasText != _hasText && mounted) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _effectiveController.removeListener(_handleTextChange);
    if (widget.controller == null) {
      _internalController.dispose();
    }
    if (widget.focusNode == null) {
      _internalFocusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bar = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: AppleMotion.easeOut,
      padding: widget.padding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      height: widget.height ?? 38,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
              controller: _effectiveController,
              focusNode: _effectiveFocusNode,
              onChanged: widget.onChanged,
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
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _hasText ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeInOut,
            child: AnimatedScale(
              scale: _hasText ? 1.0 : 0.6,
              duration: const Duration(milliseconds: 160),
              curve: AppleMotion.spring,
              child: _hasText
                  ? BouncyPressable(
                      scaleFactor: 0.88,
                      onTap: () {
                        _effectiveController.clear();
                        widget.onChanged?.call('');
                        widget.onClear?.call();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.cancel_rounded,
                          size: 15,
                          color: AppTheme.textMuted.withValues(alpha: 0.8),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 6),
            widget.trailing!,
          ],
        ],
      ),
    );

    if (widget.maxWidth != null) {
      bar = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth!),
        child: bar,
      );
    }

    if (widget.margin != null) {
      bar = Padding(
        padding: widget.margin!,
        child: bar,
      );
    }

    return bar;
  }
}
