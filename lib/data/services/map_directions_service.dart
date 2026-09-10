import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class MapDirectionsService {
  /// Cleans and intelligently normalizes address strings for accurate Google Maps directions.
  static String normalizeAddress(String rawAddress) {
    if (rawAddress.trim().isEmpty) return '';

    String cleaned = rawAddress.trim();

    // 1. If it's already a direct Google Maps / web URL, return as-is
    if (cleaned.startsWith('http://') ||
        cleaned.startsWith('https://') ||
        cleaned.startsWith('maps.app.goo.gl') ||
        cleaned.startsWith('goo.gl/maps')) {
      return cleaned;
    }

    // 2. Remove common unnecessary address prefixes
    cleaned = cleaned.replaceAll(
      RegExp(
        r'^(address|addr|location|loc|near|site|destination)\s*[:\-]\s*',
        caseSensitive: false,
      ),
      '',
    );

    // 3. Replace multiple newlines and carriage returns with a comma separator
    cleaned = cleaned.replaceAll(RegExp(r'[\r\n]+'), ', ');

    // 4. Collapse multiple spaces and trailing/leading commas
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r',\s*,'), ',');
    cleaned = cleaned.trim();
    cleaned = cleaned.replaceAll(RegExp(r'^[,\s\.\-]+|[,\s\.\-]+$'), '');

    return cleaned;
  }

  /// Intelligently launches Google Maps with turn-by-turn navigation or directions to the target address.
  static Future<bool> openDirections(String address) async {
    final normalized = normalizeAddress(address);
    if (normalized.isEmpty) return false;

    // 1. If address is already a web URL
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      final uri = Uri.parse(normalized);
      try {
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }

    final encodedDest = Uri.encodeComponent(normalized);

    // Standard Google Maps Universal Directions URL (Works everywhere: Web, Android, iOS, Desktop)
    final googleMapsWebUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$encodedDest',
    );

    // Platform-specific direct intents
    if (!kIsWeb && Platform.isAndroid) {
      // 1. Android Native Turn-by-Turn Navigation Intent
      final androidNavUri = Uri.parse('google.navigation:q=$encodedDest');
      try {
        if (await canLaunchUrl(androidNavUri)) {
          return await launchUrl(
            androidNavUri,
            mode: LaunchMode.externalApplication,
          );
        }
      } catch (_) {}

      // 2. Android Geo Intent
      final androidGeoUri = Uri.parse('geo:0,0?q=$encodedDest');
      try {
        if (await canLaunchUrl(androidGeoUri)) {
          return await launchUrl(
            androidGeoUri,
            mode: LaunchMode.externalApplication,
          );
        }
      } catch (_) {}
    } else if (!kIsWeb && Platform.isIOS) {
      // 1. iOS Google Maps App Intent
      final iosGoogleMapsUri = Uri.parse(
        'comgooglemaps://?daddr=$encodedDest&directionsmode=driving',
      );
      try {
        if (await canLaunchUrl(iosGoogleMapsUri)) {
          return await launchUrl(
            iosGoogleMapsUri,
            mode: LaunchMode.externalApplication,
          );
        }
      } catch (_) {}

      // 2. iOS Apple Maps Directions Intent
      final appleMapsUri = Uri.parse(
        'https://maps.apple.com/?daddr=$encodedDest&dirflg=d',
      );
      try {
        if (await canLaunchUrl(appleMapsUri)) {
          return await launchUrl(
            appleMapsUri,
            mode: LaunchMode.externalApplication,
          );
        }
      } catch (_) {}
    }

    // 3. Fallback: Launch Google Maps Universal Directions in external application or browser
    try {
      if (await canLaunchUrl(googleMapsWebUri)) {
        return await launchUrl(
          googleMapsWebUri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {}

    // Final fallback attempt
    try {
      return await launchUrl(
        googleMapsWebUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
