import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_theme.dart';
import '../shared/photo_attachment_widget.dart';

/// Immersive, mobile-optimized photo viewer dialog with pinch-to-zoom, pan,
/// double-tap zoom, swipe pagination, and desktop keyboard shortcuts.
class AppPhotoViewerDialog extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const AppPhotoViewerDialog({
    super.key,
    required this.photoUrls,
    this.initialIndex = 0,
  });

  /// Displays the photo viewer dialog modally.
  static void show(
    BuildContext context, {
    required List<String> photoUrls,
    int initialIndex = 0,
  }) {
    if (photoUrls.isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Photo Viewer',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim1, anim2) {
        return AppPhotoViewerDialog(
          photoUrls: photoUrls,
          initialIndex: initialIndex,
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<AppPhotoViewerDialog> createState() => _AppPhotoViewerDialogState();
}

class _AppPhotoViewerDialogState extends State<AppPhotoViewerDialog> {
  late int _currentIndex;
  late PageController _pageController;
  final Map<int, TransformationController> _transformControllers = {};
  bool _isCurrentZoomed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.photoUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  TransformationController _getControllerForIndex(int index) {
    return _transformControllers.putIfAbsent(
      index,
      () => TransformationController()
        ..addListener(() {
          if (index == _currentIndex) {
            final scale =
                _transformControllers[index]?.value.getMaxScaleOnAxis() ?? 1.0;
            final isZoomed = (scale - 1.0).abs() > 0.05;
            if (isZoomed != _isCurrentZoomed && mounted) {
              setState(() => _isCurrentZoomed = isZoomed);
            }
          }
        }),
    );
  }

  void _resetCurrentZoom() {
    final controller = _transformControllers[_currentIndex];
    if (controller != null) {
      controller.value = Matrix4.identity();
      if (mounted) {
        setState(() => _isCurrentZoomed = false);
      }
    }
  }

  void _handleDoubleTap(TapDownDetails details) {
    final controller = _getControllerForIndex(_currentIndex);
    final currentScale = controller.value.getMaxScaleOnAxis();

    if (currentScale > 1.2) {
      // Zoom out to normal
      _resetCurrentZoom();
    } else {
      // Zoom in to 2.5x centered at tap location
      final position = details.localPosition;
      final x = -position.dx * 1.5;
      final y = -position.dy * 1.5;
      final zoomed = Matrix4.identity()
        ..translate(x, y)
        ..scale(2.5);
      controller.value = zoomed;
      if (mounted) {
        setState(() => _isCurrentZoomed = true);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 650;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              _currentIndex > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
              _currentIndex < widget.photoUrls.length - 1) {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: isMobile ? _buildMobileView() : _buildDesktopView(),
      ),
    );
  }

  /// Full-screen edge-to-edge mobile viewer with pinch-to-zoom & gestures
  Widget _buildMobileView() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha: 0.96),
      child: SafeArea(
        child: Stack(
          children: [
            // Interactive Photo Page View
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                physics: _isCurrentZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: widget.photoUrls.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    final scale = _transformControllers[index]
                            ?.value
                            .getMaxScaleOnAxis() ??
                        1.0;
                    _isCurrentZoomed = (scale - 1.0).abs() > 0.05;
                  });
                },
                itemBuilder: (context, index) {
                  final url = widget.photoUrls[index];
                  final controller = _getControllerForIndex(index);

                  return GestureDetector(
                    onDoubleTapDown: _handleDoubleTap,
                    onDoubleTap: () {},
                    child: Center(
                      child: InteractiveViewer(
                        transformationController: controller,
                        minScale: 0.8,
                        maxScale: 5.0,
                        clipBehavior: Clip.none,
                        panAxis: PanAxis.free,
                        child: PhotoAttachmentWidget.buildAppImage(
                          url,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Top Header Bar Overlay
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close Button
                  _buildCircleButton(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),

                  // Photo Counter Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Text(
                      'Photo ${_currentIndex + 1} of ${widget.photoUrls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  // Reset Zoom Button (visible when zoomed)
                  if (_isCurrentZoomed)
                    _buildCircleButton(
                      icon: Icons.zoom_out_map_rounded,
                      tooltip: 'Reset Zoom',
                      onPressed: _resetCurrentZoom,
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
            ),

            // Bottom Navigation Arrows for Quick Flipping
            if (widget.photoUrls.length > 1) ...[
              if (_currentIndex > 0)
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildNavArrowButton(
                      icon: Icons.chevron_left_rounded,
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      },
                    ),
                  ),
                ),
              if (_currentIndex < widget.photoUrls.length - 1)
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildNavArrowButton(
                      icon: Icons.chevron_right_rounded,
                      onPressed: () {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      },
                    ),
                  ),
                ),
            ],

            // Bottom Hints Pill
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Pinch or double-tap to zoom',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Modern Desktop Modal with Zoom & Pan
  Widget _buildDesktopView() {
    return Center(
      child: Container(
        width: 960,
        height: 720,
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1524),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              spreadRadius: 8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Column(
                children: [
                  // Desktop Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFF131A2E),
                      border: Border(
                        bottom: BorderSide(color: Colors.white10),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.photo_size_select_actual_outlined,
                              color: AppTheme.primaryLight,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Photo ${_currentIndex + 1} of ${widget.photoUrls.length}',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Pinch / Scroll to zoom',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (_isCurrentZoomed)
                              IconButton(
                                icon: Icon(
                                  Icons.zoom_out_map_rounded,
                                  color: AppTheme.primaryLight,
                                  size: 20,
                                ),
                                tooltip: 'Reset Zoom',
                                onPressed: _resetCurrentZoom,
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              tooltip: 'Close (Esc)',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Desktop Image Viewport
                  Expanded(
                    child: Container(
                      color: const Color(0xFF090D16),
                      child: PageView.builder(
                        controller: _pageController,
                        physics: _isCurrentZoomed
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        itemCount: widget.photoUrls.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentIndex = index;
                            final scale = _transformControllers[index]
                                    ?.value
                                    .getMaxScaleOnAxis() ??
                                1.0;
                            _isCurrentZoomed = (scale - 1.0).abs() > 0.05;
                          });
                        },
                        itemBuilder: (context, index) {
                          final url = widget.photoUrls[index];
                          final controller = _getControllerForIndex(index);

                          return GestureDetector(
                            onDoubleTapDown: _handleDoubleTap,
                            onDoubleTap: () {},
                            child: Center(
                              child: InteractiveViewer(
                                transformationController: controller,
                                minScale: 0.8,
                                maxScale: 5.0,
                                clipBehavior: Clip.none,
                                panAxis: PanAxis.free,
                                child: PhotoAttachmentWidget.buildAppImage(
                                  url,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),

              // Side Navigation Buttons for Desktop
              if (widget.photoUrls.length > 1) ...[
                if (_currentIndex > 0)
                  Positioned(
                    left: 16,
                    top: 60,
                    bottom: 0,
                    child: Center(
                      child: _buildNavArrowButton(
                        icon: Icons.chevron_left_rounded,
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        },
                      ),
                    ),
                  ),
                if (_currentIndex < widget.photoUrls.length - 1)
                  Positioned(
                    right: 16,
                    top: 60,
                    bottom: 0,
                    child: Center(
                      child: _buildNavArrowButton(
                        icon: Icons.chevron_right_rounded,
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildNavArrowButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
