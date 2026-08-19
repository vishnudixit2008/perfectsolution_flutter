import 'package:flutter/material.dart';

class AppTheme {
  // Theme Palette Colors
  static const Color darkBackground = Color(
    0xFF0B0F19,
  ); // Super deep slate/blue-black
  static const Color cardBg = Color(
    0xFF131B2E,
  ); // Deep slate 850 for clean dark cards
  static const Color cardBorder = Color(
    0x1AFFFFFF,
  ); // Subtle semi-transparent border (10% white)

  // Accents
  static const Color primary = Color(0xFF6366F1); // Indigo neon
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color secondary = Color(0xFF14B8A6); // Teal accent
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color danger = Color(0xFFEF4444); // Crimson

  // Text Colors
  static const Color textPrimary = Color(0xFFF8FAFC); // White-slate
  static const Color textSecondary = Color(
    0xFFCBD5E1,
  ); // Slate 300 - High legibility
  static const Color textMuted = Color(
    0xFF94A3B8,
  ); // Slate 400 - Calm subtle labels

  // Inventory Threshold Fallback
  static const int kDefaultLowStockThreshold = 5;

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF818CF8), secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [danger, Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [success, Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // App decoration decorators
  static BoxDecoration glassCardDecoration({
    Color color = const Color(0x1AFFFFFF),
    double borderRadius = 12.0,
    double borderWidth = 1.0,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: Colors.white.withOpacity(0.08),
        width: borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  // Get full dark Theme Data
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: primary,

      // Color Scheme
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: cardBg,
        error: danger,
      ),

      // Fonts
      fontFamily: 'Inter',

      // Explicit Icon Themes for Windows & cross-platform consistency
      iconTheme: const IconThemeData(
        color: textPrimary,
      ),
      primaryIconTheme: const IconThemeData(
        color: textPrimary,
      ),

      // Text styling with Apple SF Pro / HIG tracking & weight hierarchy
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: textPrimary,
          height: 1.2,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
          color: textPrimary,
          height: 1.25,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: textPrimary,
          height: 1.3,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: textPrimary,
          height: 1.35,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: textPrimary,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: textPrimary,
          height: 1.4,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: textPrimary,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.15,
          color: textPrimary,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.05,
          color: textSecondary,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.1,
          color: textMuted,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: textPrimary,
        ),
        labelMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: textSecondary,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: textMuted,
        ),
      ),


      // Card Theme
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger),
        ),
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: Colors.white.withOpacity(0.12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // Bottom Navigation Bar Theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF0F1322),
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF131A2E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
    );
  }
}

/// Standardized Apple SF Pro / HIG Typography Tokens
class AppTypography {
  /// 30px Bold (-0.7px tracking) — Page Large Titles
  static const TextStyle largeTitle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.7,
    color: AppTheme.textPrimary,
    height: 1.2,
  );

  /// 22px Bold (-0.5px tracking) — Section Headers
  static const TextStyle title1 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppTheme.textPrimary,
    height: 1.25,
  );

  /// 18px SemiBold (-0.3px tracking) — Card Titles & Dialog Headers
  static const TextStyle title2 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppTheme.textPrimary,
    height: 1.3,
  );

  /// 16px SemiBold (-0.2px tracking) — Standard Item Titles
  static const TextStyle title3 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppTheme.textPrimary,
    height: 1.35,
  );

  /// 15px SemiBold (-0.2px tracking) — Sub-headers & Metric Labels
  static const TextStyle headline = TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppTheme.textPrimary,
    height: 1.35,
  );

  /// 14px Regular (-0.1px tracking) — Primary Body Text
  static const TextStyle body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    color: AppTheme.textPrimary,
    height: 1.45,
  );

  /// 13px Medium (-0.05px tracking) — Secondary Details & List Items
  static const TextStyle callout = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.05,
    color: AppTheme.textSecondary,
    height: 1.4,
  );

  /// 12px Medium (0.0px tracking) — Hints & Metadata
  static const TextStyle subhead = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    color: AppTheme.textSecondary,
  );

  /// 11px Regular (+0.1px tracking) — Timestamps & Footnotes
  static const TextStyle footnote = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    color: AppTheme.textMuted,
  );

  /// 10px Bold (+0.6px tracking, Uppercase) — Status Badges & Category Tags
  static const TextStyle badge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: AppTheme.textPrimary,
  );

  /// 14px SemiBold (-0.2px tracking) — Currency Pricing
  static const TextStyle currency = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppTheme.primaryLight,
  );

  /// 20px Bold (-0.5px tracking) — Prominent Financial Grand Totals
  static const TextStyle currencyLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppTheme.primaryLight,
  );
}
