import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/models/pricelist_item.dart';
import '../../core/app_theme.dart';

class AppKeyboardAutocomplete extends StatefulWidget {
  final List<PricelistItem> catalogItems;
  final ValueChanged<PricelistItem> onSelected;
  final TextEditingController? controller;
  final String hintText;
  final double width;
  final bool isMobile;
  final bool Function(PricelistItem)? customFilter;
  final bool allowNewItem;
  final bool clearOnSelect;
  final bool autoFocusAfterSelect;

  const AppKeyboardAutocomplete({
    super.key,
    required this.catalogItems,
    required this.onSelected,
    this.controller,
    this.hintText = 'Search products by name or category...',
    this.width = 450,
    this.isMobile = false,
    this.customFilter,
    this.allowNewItem = false,
    this.clearOnSelect = false,
    this.autoFocusAfterSelect = false,
  });

  @override
  State<AppKeyboardAutocomplete> createState() => _AppKeyboardAutocompleteState();
}

class _AppKeyboardAutocompleteState extends State<AppKeyboardAutocomplete> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int _highlightedIndex = 0;
  List<PricelistItem> _currentOptions = [];
  bool _isProcessingSelection = false;

  static const double _itemHeight = 52.0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToHighlighted() {
    if (!_scrollController.hasClients) return;
    const double visibleHeight = 280.0;
    final double targetOffset = (_highlightedIndex * _itemHeight) - (visibleHeight - (2 * _itemHeight));
    
    final double minScroll = 0.0;
    final double maxScroll = _scrollController.position.maxScrollExtent;
    final double clampedOffset = targetOffset.clamp(minScroll, maxScroll);

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _handleSelection(PricelistItem selection) {
    if (_isProcessingSelection) return;
    _isProcessingSelection = true;

    widget.onSelected(selection);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.clearOnSelect) {
        _controller.clear();
      } else {
        _controller.text = selection.itemName;
        _controller.selection = TextSelection.collapsed(offset: selection.itemName.length);
      }

      if (widget.autoFocusAfterSelect) {
        _focusNode.requestFocus();
      } else {
        _focusNode.unfocus();
      }

      setState(() {
        _highlightedIndex = 0;
        _currentOptions = [];
        _isProcessingSelection = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<PricelistItem>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim();
        if (query.isEmpty) {
          _currentOptions = [];
          return const Iterable<PricelistItem>.empty();
        }

        final tokens = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        if (tokens.isEmpty) {
          _currentOptions = [];
          return const Iterable<PricelistItem>.empty();
        }

        final List<MapEntry<PricelistItem, int>> matches = [];
        bool exactMatchFound = false;

        for (final item in widget.catalogItems) {
          if (widget.customFilter != null && !widget.customFilter!(item)) {
            continue;
          }

          final nameLower = item.itemName.toLowerCase();
          final catLower = (item.category ?? '').toLowerCase();
          final descLower = (item.itemDescription ?? '').toLowerCase();
          final combined = '$nameLower $catLower $descLower ${item.id}';

          if (nameLower == query.toLowerCase()) {
            exactMatchFound = true;
          }

          bool allMatched = true;
          for (final token in tokens) {
            if (!combined.contains(token)) {
              allMatched = false;
              break;
            }
          }

          if (allMatched) {
            int score = 0;
            if (nameLower == query.toLowerCase()) {
              score += 1000;
            } else if (nameLower.startsWith(query.toLowerCase())) {
              score += 500;
            }
            for (final token in tokens) {
              if (nameLower.contains(token)) score += 100;
              if (catLower.contains(token)) score += 20;
              if (descLower.contains(token)) score += 10;
            }
            matches.add(MapEntry(item, score));
          }
        }

        matches.sort((a, b) => b.value.compareTo(a.value));
        final result = matches.map((e) => e.key).toList();

        if (widget.allowNewItem && !exactMatchFound && query.isNotEmpty) {
          result.add(
            PricelistItem(
              id: -1,
              itemName: query,
              price: 0,
              stockQty: 0,
              openingStock: 0,
              category: 'New Item',
            ),
          );
        }

        _currentOptions = result;
        if (_highlightedIndex >= _currentOptions.length) {
          _highlightedIndex = 0;
        }
        return _currentOptions;
      },
      displayStringForOption: (PricelistItem option) => option.itemName,
      onSelected: (PricelistItem selection) {
        _handleSelection(selection);
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        return Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;

            if (_currentOptions.isEmpty) return KeyEventResult.ignored;

            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              setState(() {
                _highlightedIndex = (_highlightedIndex + 1) % _currentOptions.length;
              });
              _scrollToHighlighted();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              setState(() {
                _highlightedIndex = (_highlightedIndex - 1 + _currentOptions.length) % _currentOptions.length;
              });
              _scrollToHighlighted();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              if (_highlightedIndex >= 0 && _highlightedIndex < _currentOptions.length) {
                final selected = _currentOptions[_highlightedIndex];
                _handleSelection(selected);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: TextField(
              controller: textEditingController,
              focusNode: focusNode,
              style: TextStyle(
                fontSize: widget.isMobile ? 12 : 13,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontSize: widget.isMobile ? 12 : 13,
                  color: AppTheme.textMuted,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppTheme.primaryLight,
                  size: widget.isMobile ? 18 : 20,
                ),
                suffixIcon: textEditingController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: widget.isMobile ? 16 : 18),
                        onPressed: () {
                          textEditingController.clear();
                          setState(() {
                            _highlightedIndex = 0;
                            _currentOptions = [];
                          });
                        },
                      )
                    : null,
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  vertical: widget.isMobile ? 8 : 12,
                  horizontal: 10,
                ),
              ),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final screenWidth = MediaQuery.of(context).size.width;
        final listOptions = options.toList();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: const Color(0xFF131A2E),
            elevation: 8.0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Container(
              width: widget.isMobile ? screenWidth - 32 : widget.width,
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: listOptions.length,
                separatorBuilder: (context, index) =>
                    const Divider(color: Colors.white10, height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final PricelistItem option = listOptions[index];
                  final bool isHighlighted = index == _highlightedIndex;
                  final bool isNewItem = option.id == -1;
                  final bool isLowStock = !isNewItem && option.stockQty <= option.openingStock;

                  if (isNewItem) {
                    return Container(
                      height: _itemHeight,
                      color: isHighlighted
                          ? AppTheme.primary.withValues(alpha: 0.35)
                          : AppTheme.primary.withValues(alpha: 0.08),
                      child: ListTile(
                        dense: widget.isMobile,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 0,
                        ),
                        leading: const Icon(
                          Icons.add_circle_rounded,
                          color: AppTheme.primaryLight,
                          size: 20,
                        ),
                        title: Text(
                          '+ Add "${option.itemName}" as new product',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryLight,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Create and stock-in new product',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                        ),
                        onTap: () {
                          onSelected(option);
                        },
                      ),
                    );
                  }

                  return Container(
                    height: _itemHeight,
                    color: isHighlighted
                        ? AppTheme.primary.withValues(alpha: 0.25)
                        : Colors.transparent,
                    child: ListTile(
                      dense: widget.isMobile,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 0,
                      ),
                      title: Text(
                        option.itemName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isHighlighted
                              ? AppTheme.primaryLight
                              : AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${option.category ?? "General"} • Stock: ${option.stockQty} left',
                        style: TextStyle(
                          fontSize: 11,
                          color: isLowStock ? AppTheme.danger : AppTheme.textMuted,
                        ),
                      ),
                      trailing: Text(
                        '₹${option.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryLight,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () {
                        onSelected(option);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
