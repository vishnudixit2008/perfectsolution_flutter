import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Industry-Grade Apple & Telegram-Inspired Physics Curves, Timings, and Profiling Constants
class AppleMotion {
  // ── Physics Curves ──────────────────────────────────────────────────────────
  /// Natural fluid spring for interactive press and bounce states (Telegram / iOS style)
  static const Curve spring = Cubic(0.175, 0.885, 0.32, 1.15);

  /// Snappy deceleration curve for reveals, modals, and drawers
  static const Curve snappy = Cubic(0.25, 1.0, 0.5, 1.0);

  /// Smooth ease-out cubic for entrances and list reveals
  static const Curve easeOut = Curves.easeOutCubic;

  /// Swift snappy curve for modal exits and form closes
  static const Curve modalExitCurve = Curves.easeInCubic;

  /// Apple iOS 18 Fluid Liquid Glass morphing curve
  static const Curve liquidGlass = Cubic(0.19, 1.0, 0.22, 1.0);

  /// High-inertia deceleration for morphing tab navigation pills
  static const Curve morphingPillCurve = Cubic(0.19, 1.0, 0.22, 1.0);

  /// Smooth ease-in-out for looping shimmers
  static const Curve easeInOut = Curves.easeInOut;

  // ── Duration Hierarchy (Tuned for Human Perception & Visual Polish) ─────────
  /// 140ms — Ultra-responsive micro tap depression
  static const Duration instant = Duration(milliseconds: 140);

  /// 200ms — Fast snappy modal dismissals / form closes (zero lag)
  static const Duration modalDismiss = Duration(milliseconds: 200);

  /// 300ms — Button releases, hover states, quick pills, modal entries
  static const Duration quick = Duration(milliseconds: 300);

  /// 420ms — Staggered list reveals, tab switches, cards (clearly visible & fluid)
  static const Duration medium = Duration(milliseconds: 420);

  /// 550ms — Large dashboards, full page transitions, charts
  static const Duration stately = Duration(milliseconds: 550);

  // ── Scale Values ────────────────────────────────────────────────────────────
  /// 0.97x — Standard tactile depression for cards & buttons on tap
  static const double pressScale = 0.97;

  /// 0.94x — Initial modal scale-in starting point
  static const double modalEntryScale = 0.94;

  /// Triggers a lightweight haptic feedback tick without blocking main thread
  static void triggerHapticFeedback({bool light = true}) {
    if (kIsWeb) return;
    try {
      if (light) {
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }
}
