import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
    _focusNode = FocusNode();
    _isExpanded = widget.searchQuery.isNotEmpty || widget.activeFilterCount > 0;
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
    if (!_isExpanded) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: _expandAndFocus,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF131A2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.searchQuery.isNotEmpty
                        ? 'Search: "${widget.searchQuery}"'
                        : widget.hintText,
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.searchQuery.isNotEmpty
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                      fontWeight: widget.searchQuery.isNotEmpty
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.activeFilterCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.activeFilterCount}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: AppTheme.primaryLight,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _expandAndFocus,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.search_rounded,
                color: AppTheme.primaryLight,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: widget.onSearchChanged,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppTheme.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _controller.clear();
                    widget.onSearchChanged('');
                  },
                ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _isExpanded = false),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          if (widget.filterOptions != null) ...[
            const Divider(color: Colors.white10, height: 16),
            widget.filterOptions!,
          ],
        ],
      ),
    );
  }
}
