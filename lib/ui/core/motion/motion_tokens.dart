import 'package:flutter/material.dart';

/// Apple-Grade Motion Curves, Timings, and Physics Constants
class AppleMotion {
  // ── Physics Curves ──────────────────────────────────────────────────────────
  /// Natural fluid spring for interactive press and bounce states
  static const Curve spring = Cubic(0.175, 0.885, 0.32, 1.15);

  /// Snappy deceleration curve for reveals, modals, and drawers
  static const Curve snappy = Cubic(0.25, 1.0, 0.5, 1.0);

  /// Smooth ease-out cubic for entrances and fades
  static const Curve easeOut = Curves.easeOutCubic;

  /// Swift snappy curve for modal exits and form closes
  static const Curve modalExitCurve = Curves.easeInCubic;

  /// Smooth ease-in-out for looping shimmers
  static const Curve easeInOut = Curves.easeInOut;

  // ── Duration Hierarchy ──────────────────────────────────────────────────────
  /// 120ms — Micro tap reactions & immediate feedback
  static const Duration instant = Duration(milliseconds: 120);

  /// 160ms — Fast snappy modal dismissals / form closes (zero lag)
  static const Duration modalDismiss = Duration(milliseconds: 160);

  /// 200ms — Button releases, hover states, quick pills, modal entries
  static const Duration quick = Duration(milliseconds: 200);

  /// 300ms — Staggered list reveals, tab switches, cards
  static const Duration medium = Duration(milliseconds: 300);

  /// 450ms — Large dashboards, full page transitions, charts
  static const Duration stately = Duration(milliseconds: 450);

  // ── Scale Values ────────────────────────────────────────────────────────────
  /// 0.97x — Standard tactile depression for cards & buttons on tap
  static const double pressScale = 0.97;

  /// 0.94x — Initial modal scale-in starting point
  static const double modalEntryScale = 0.94;
}
