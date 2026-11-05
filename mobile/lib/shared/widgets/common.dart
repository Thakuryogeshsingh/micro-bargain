import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import 'motion.dart';

/// Loading / error-with-retry / data for an AsyncValue.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const ListSkeleton(),
      error: (error, _) => ErrorView(message: error.toString(), onRetry: onRetry),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _StateView(
      icon: Icons.wifi_off_rounded,
      tint: const Color(0xFFE5484D),
      title: tr('कुछ गड़बड़ हुई'),
      message: message,
      action: onRetry == null
          ? null
          : FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(tr('फिर से कोशिश करें')),
            ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _StateView(icon: icon, title: message, action: action);
}

/// Big icon in a soft circle, a bold line, an optional softer line and an optional button.
class _StateView extends StatelessWidget {
  const _StateView({required this.icon, required this.title, this.message, this.action, this.tint});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? (AppTheme.minimal ? AppTheme.ink : AppTheme.primary);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.7, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(color: AppTheme.chip, shape: BoxShape.circle),
                child: Icon(icon, size: 50, color: color),
              ),
              if (tint == null)
                Positioned(
                  right: 4,
                  top: 6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppTheme.minimal ? AppTheme.accent : AppTheme.accent.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.background, width: 3),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, height: 1.4, color: AppTheme.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

/// Shimmering placeholder rows while a list loads.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Shimmer(
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                const SkeletonBox(width: 56, height: 56, radius: 16),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SkeletonBox(width: i.isEven ? 180 : 140, height: 14),
                    const SizedBox(height: 8),
                    const SkeletonBox(width: 100, height: 12),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      'completed' || 'active' || 'confirmed' || 'ready' || 'out_for_delivery' || 'approved' => Colors.green.shade700,
      'pending' || 'pending_payment' || 'paused' || 'draft' => Colors.orange.shade800,
      _ => scheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(statusLabel(status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Re-renders every second, e.g. for a deal countdown.
class Ticker extends StatefulWidget {
  const Ticker({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  late final Timer _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Floating message pill at the bottom: a check for normal news, a warning for errors.
void showMessage(BuildContext context, String message, {bool error = false}) {
  final color = error ? const Color(0xFFFF5A5F) : AppTheme.accent;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      elevation: 0,
      backgroundColor: const Color(0xFF111111),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      duration: Duration(milliseconds: error ? 4000 : 2600),
      content: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Icon(error ? Icons.priority_high_rounded : Icons.check_rounded, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.3)),
        ),
      ]),
    ));
}

/// Runs an API action, shows the server's message on failure, and returns whether it worked.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.friendly, error: true);
    return false;
  }
}

/// Popup buttons keep their natural width (the theme makes page buttons full-width, which stacked them).
final dialogButtonStyle = FilledButton.styleFrom(minimumSize: const Size(96, 46));

/// The app's popup: icon on top, bold title, soft message, optional [body], and two equal buttons.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.body,
    this.icon = Icons.help_outline_rounded,
    this.danger = false,
    required this.okLabel,
    this.cancelLabel,
    required this.onOk,
    this.onCancel,
  });

  final String title;
  final String? message;
  final Widget? body;
  final IconData icon;
  final bool danger;
  final String okLabel;
  final String? cancelLabel;
  final VoidCallback onOk;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? const Color(0xFFE5484D) : AppTheme.primary;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: tint),
            ),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w900, letterSpacing: -0.3, color: AppTheme.ink)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, height: 1.45, color: AppTheme.muted)),
          ],
          if (body != null) ...[const SizedBox(height: 16), body!],
          const SizedBox(height: 22),
          Row(children: [
            if (cancelLabel != null) ...[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                    side: BorderSide(color: AppTheme.ink.withValues(alpha: 0.15)),
                    foregroundColor: AppTheme.ink,
                  ),
                  onPressed: onCancel ?? () => Navigator.pop(context),
                  child: Text(cancelLabel!, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: danger ? tint : null),
                onPressed: onOk,
                child: Text(okLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String title,
    {String? message, String? ok, IconData icon = Icons.help_outline_rounded, bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => AppDialog(
      title: title,
      message: message,
      icon: icon,
      danger: danger,
      okLabel: ok ?? tr('हाँ'),
      cancelLabel: tr('नहीं'),
      onOk: () => Navigator.pop(dialog, true),
      onCancel: () => Navigator.pop(dialog, false),
    ),
  );
  return result == true;
}

/// Asks for one line of text (e.g. a reason or the 4-digit pickup code).
Future<String?> askText(BuildContext context, String title,
    {String hint = '', TextInputType keyboard = TextInputType.text, int? maxLength, IconData icon = Icons.edit_note_rounded}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialog) => AppDialog(
      title: title,
      icon: icon,
      body: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboard,
        maxLength: maxLength,
        textAlign: keyboard == TextInputType.number ? TextAlign.center : TextAlign.start,
        decoration: InputDecoration(hintText: hint, filled: true, fillColor: AppTheme.chip),
      ),
      okLabel: tr('ठीक है'),
      cancelLabel: tr('रद्द'),
      onOk: () => Navigator.pop(dialog, controller.text.trim()),
    ),
  );
  return result;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );
}

/// Dashboard figure: coloured icon bubble, label and a number that counts up when it appears.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.format,
    this.icon,
    this.color = const Color(0xFF16A34A),
    this.onTap,
  });

  final String label;
  final double value;
  final String Function(double)? format;
  final IconData? icon;
  final Color color;

  /// Opens the related screen; tiles with an action show a small arrow.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minimal = AppTheme.minimal;
    final tile = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: minimal
            ? AppTheme.softShadow()
            : [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          if (icon != null)
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: minimal ? AppTheme.chip : color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 18, color: minimal ? AppTheme.ink : color),
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.muted),
        ]),
        CountUp(
          value: value,
          format: format ?? (v) => '${v.round()}',
          style: theme.textTheme.titleLarge?.copyWith(
              fontSize: minimal ? 24 : null, fontWeight: FontWeight.w900, letterSpacing: -0.6, color: AppTheme.ink),
        ),
      ]),
    );
    return onTap == null ? tile : Pressable(onTap: onTap, child: tile);
  }
}
