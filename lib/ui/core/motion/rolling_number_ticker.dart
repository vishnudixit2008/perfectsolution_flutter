import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'motion_tokens.dart';

/// Smooth animated rolling ticker for numeric metrics, revenue, and counters.
///
/// Performance Optimizations:
/// - Pre-caches [NumberFormat] instance during initialization to achieve zero object allocations in paint/frame loops.
/// - Encloses rendering in a [RepaintBoundary] to isolate text layer repainting from parent containers.
class RollingNumberTicker extends StatefulWidget {
  final num value;
  final String prefix;
  final String suffix;
  final int decimalDigits;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  const RollingNumberTicker({
    super.key,
    required this.value,
    this.prefix = '',
    this.suffix = '',
    this.decimalDigits = 0,
    this.style,
    this.duration = AppleMotion.stately,
    this.curve = AppleMotion.easeOut,
  });

  @override
  State<RollingNumberTicker> createState() => _RollingNumberTickerState();
}

class _RollingNumberTickerState extends State<RollingNumberTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  late double _oldValue;
  late NumberFormat _formatter;

  @override
  void initState() {
    super.initState();
    _oldValue = 0.0;
    _formatter = NumberFormat.currency(
      symbol: '',
      decimalDigits: widget.decimalDigits,
    );

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _animation = Tween<double>(
      begin: _oldValue,
      end: widget.value.toDouble(),
    ).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant RollingNumberTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decimalDigits != widget.decimalDigits) {
      _formatter = NumberFormat.currency(
        symbol: '',
        decimalDigits: widget.decimalDigits,
      );
    }
    if (oldWidget.value != widget.value) {
      _oldValue = _animation.value;
      _animation = Tween<double>(
        begin: _oldValue,
        end: widget.value.toDouble(),
      ).animate(
        CurvedAnimation(parent: _controller, curve: widget.curve),
      );
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final formattedNumber = _formatter.format(_animation.value);
          return Text(
            '${widget.prefix}$formattedNumber${widget.suffix}',
            style: widget.style,
          );
        },
      ),
    );
  }
}
