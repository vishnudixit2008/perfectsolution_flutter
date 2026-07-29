import 'package:url_launcher/url_launcher.dart';

class WhatsAppService {
  static Future<void> launch({
    required String mobileNo,
    required String message,
  }) async {
    if (mobileNo.trim().isEmpty) return;

    final sanitized = mobileNo.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = sanitized.startsWith('91') && sanitized.length > 10
        ? sanitized
        : '91$sanitized';
    final encodedMsg = Uri.encodeComponent(message);

    // Primary URL (wa.me)
    final primaryUri = Uri.parse('https://wa.me/$phone?text=$encodedMsg');
    // Secondary URL (api.whatsapp.com)
    final secondaryUri = Uri.parse(
      'https://api.whatsapp.com/send?phone=$phone&text=$encodedMsg',
    );

    try {
      if (await canLaunchUrl(primaryUri)) {
        await launchUrl(primaryUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    try {
      if (await canLaunchUrl(secondaryUri)) {
        await launchUrl(secondaryUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    // Fallback: force launch external application
    try {
      await launchUrl(primaryUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(secondaryUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }
}
