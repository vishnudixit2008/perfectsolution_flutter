import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Industry-Grade Apple & Telegram-Inspired Physics Curves, Timings, and Profiling Constants
/// Platform-aware: desktop (Windows/macOS) gets lean, snappy timings;
/// mobile (Android) keeps the expressive, liquid spring profile.
class AppleMotion {
  // ── Platform Detection ───────────────────────────────────────────────────────
  /// true on Windows and macOS (mouse input primary, high-DPI monitors).
  static bool get isDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

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

  // ── Platform-Adaptive Durations ─────────────────────────────────────────────
  /// Page transition: lean 220ms on desktop, expressive 380ms on mobile
  static Duration get pageTransitionDuration =>
      isDesktop ? const Duration(milliseconds: 220) : const Duration(milliseconds: 380);

  /// Modal dialog: crisp 200ms on desktop, liquid 420ms on mobile
  static Duration get modalDuration =>
      isDesktop ? const Duration(milliseconds: 200) : const Duration(milliseconds: 420);

  /// Sidebar/nav item highlight transition
  static Duration get navItemDuration =>
      isDesktop ? const Duration(milliseconds: 160) : const Duration(milliseconds: 280);

  /// Staggered list item entrance delay per item index
  static Duration get staggerDelay =>
      isDesktop ? const Duration(milliseconds: 8) : const Duration(milliseconds: 20);

  /// Max items that play entrance animation (beyond = instant render)
  static int get staggerMaxIndex => isDesktop ? 4 : 8;

  /// Base duration for staggered entrance items
  static Duration get staggerBaseDuration =>
      isDesktop ? const Duration(milliseconds: 160) : const Duration(milliseconds: 420);

  // ── Scale Values ────────────────────────────────────────────────────────────
  /// 0.97x — Standard tactile depression for cards & buttons on tap (mobile)
  static const double pressScale = 0.97;

  /// Desktop: no scale transform — hover highlight replaces scale animation
  static const double pressScaleDesktop = 1.0;

  /// 0.94x — Initial modal scale-in starting point (mobile)
  static const double modalEntryScale = 0.94;

  /// Desktop modal entry scale: less dramatic, crisper professional feel
  static const double modalEntryScaleDesktop = 0.97;

  // ── Hover Colors (Desktop) ───────────────────────────────────────────────────
  /// Subtle hover overlay for desktop list rows & cards
  static const Color hoverOverlay = Color(0x0AFFFFFF); // white ~4%

  /// Active press overlay for desktop
  static const Color pressOverlay = Color(0x12FFFFFF); // white ~7%

  /// Triggers a lightweight haptic feedback tick (no-op on desktop)
  static void triggerHapticFeedback({bool light = true}) {
    if (kIsWeb || isDesktop) return;
    try {
      if (light) {
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }
}

