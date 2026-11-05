import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import 'cart.dart';

/// "3 items · ₹240 — View cart" strip shown at the bottom of customer screens whenever the cart has something.
class CartBar extends ConsumerWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartProvider);
    final total = lines.fold<double>(0, (s, l) => s + l.total);
    final savings = lines.fold<double>(0, (s, l) => s + l.savings);
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: lines.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/cart'),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: AppTheme.heroGradient,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AppTheme.softShadow(0.25),
                    ),
                    child: Row(children: [
                      Badge(
                        label: Text('${lines.length}'),
                        backgroundColor: Colors.white,
                        textColor: AppTheme.primaryDark,
                        child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            tr('{0} आइटम · {1}', [lines.length, rupees(total)]),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          Text(
                            savings > 0
                                ? tr('{0} से · {1} की बचत', [lines.first.deal.shop.name, rupees(savings)])
                                : lines.first.deal.shop.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                          ),
                        ]),
                      ),
                      Text(tr('कार्ट देखें'),
                          style: TextStyle(color: AppTheme.minimal ? AppTheme.accent : Colors.white, fontWeight: FontWeight.w900)),
                      Icon(Icons.chevron_right_rounded, color: AppTheme.minimal ? AppTheme.accent : Colors.white),
                    ]),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Cart icon with a count, for app bars and headers.
class CartIconButton extends ConsumerWidget {
  const CartIconButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartProvider).length;
    return IconButton(
      tooltip: tr('कार्ट'),
      onPressed: () => context.push('/cart'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: Icon(Icons.shopping_bag_outlined, color: color),
      ),
    );
  }
}

/// "+" button on a deal card; once the deal is in the cart it becomes "− 2 +" to change the quantity there.
class AddStepper extends ConsumerWidget {
  const AddStepper({super.key, required this.deal, required this.onAdd});

  final Deal deal;

  /// Adds one step (also handles "another shop's items are in the cart").
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = ref.watch(cartProvider).where((l) => l.deal.id == deal.id).firstOrNull;
    final step = (deal.unit == 'kg' || deal.unit == 'litre') ? 0.5 : 1.0;
    final fill = AppTheme.minimal ? AppTheme.accent : AppTheme.primaryDark;
    final on = AppTheme.minimal ? Colors.black : Colors.white;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
      child: line == null
          ? Material(
              key: const ValueKey('add'),
              color: fill,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAdd,
                child: SizedBox(width: 36, height: 36, child: Icon(Icons.add_rounded, color: on)),
              ),
            )
          : Material(
              key: const ValueKey('stepper'),
              color: fill,
              borderRadius: BorderRadius.circular(18),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  color: on,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    final cart = ref.read(cartProvider.notifier);
                    line.quantity - step <= 0 ? cart.remove(deal.id) : cart.add(deal, line.quantity - step);
                  },
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 22),
                  child: Text(qty(line.quantity),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: on, fontWeight: FontWeight.w900, fontSize: 15)),
                ),
                _StepButton(icon: Icons.add_rounded, color: on, onTap: onAdd),
              ]),
            ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 32, height: 36, child: Icon(icon, color: color, size: 20)),
      );
}
