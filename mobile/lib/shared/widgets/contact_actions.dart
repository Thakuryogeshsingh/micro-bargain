import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import 'motion.dart';

/// Call, WhatsApp and directions buttons for a shop.
class ContactActions extends StatelessWidget {
  const ContactActions({super.key, required this.phone, required this.latitude, required this.longitude, this.message = ''});

  final String phone;
  final double latitude;
  final double longitude;

  /// Pre-filled WhatsApp text, e.g. the order number.
  final String message;

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone.trim().length >= 10;
    return Row(children: [
      _Action(
        icon: Icons.call_rounded,
        label: tr('कॉल करें'),
        color: const Color(0xFF2563EB),
        onTap: hasPhone ? () => launchUrl(Uri.parse('tel:$phone')) : null,
      ),
      const SizedBox(width: 10),
      _Action(
        icon: Icons.chat_rounded,
        label: 'WhatsApp',
        color: const Color(0xFF16A34A),
        onTap: hasPhone
            ? () => launchUrl(
                  Uri.parse('https://wa.me/91$phone${message.isEmpty ? '' : '?text=${Uri.encodeComponent(message)}'}'),
                  mode: LaunchMode.externalApplication,
                )
            : null,
      ),
      const SizedBox(width: 10),
      _Action(
        icon: Icons.directions_rounded,
        label: tr('रास्ता'),
        color: AppTheme.accent,
        onTap: () => launchUrl(
          Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude'),
          mode: LaunchMode.externalApplication,
        ),
      ),
    ]);
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}
