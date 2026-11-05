import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';

/// Three welcome slides shown once, after picking the language.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  List<(String, String, String, Color)> get _slides => [
        ('🥬🍎🥛', tr('पास की दुकानों की ताज़ा डील'), tr('फल, सब्ज़ी, दूध और किराने पर रोज़ नई छूट — आपके आस-पास।'), const Color(0xFFE3F5DF)),
        ('⏱️🛍️', tr('रिज़र्व करें, दुकान से उठाएं'), tr('एक टैप में सामान अपने लिए रखवाएं और अपने समय पर ले जाएं।'), const Color(0xFFFFF1D6)),
        ('🎁💰', tr('हर खरीद पर बचत'), tr('ऑफ़र, कूपन और दोस्तों को बुलाने पर इनाम।'), const Color(0xFFFFE4E1)),
      ];

  Future<void> _finish() async {
    await ref.read(onboardedProvider.notifier).finish();
    if (mounted) context.go('/splash');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    final last = _page == slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _finish, child: Text(tr('छोड़ें'))),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: slides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final (art, title, body, color) = slides[i];
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final offset = _controller.hasClients && _controller.position.haveDimensions ? (_controller.page ?? 0) - i : 0.0;
                    return Opacity(
                      opacity: (1 - offset.abs()).clamp(0.0, 1.0),
                      child: Transform.translate(offset: Offset(offset * -60, 0), child: child),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          color: AppTheme.dark ? Color.lerp(color, Colors.black, 0.75) : color,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(art, style: const TextStyle(fontSize: 72)),
                      ),
                      const SizedBox(height: 40),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.ink, height: 1.2)),
                      const SizedBox(height: 12),
                      Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: AppTheme.muted, height: 1.4)),
                    ]),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Row(children: [
              for (var i = 0; i < slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _page ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page ? AppTheme.primaryDark : AppTheme.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: last ? 160 : 60,
                height: 60,
                child: FilledButton(
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 60)),
                  onPressed: last
                      ? _finish
                      : () => _controller.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic),
                  child: last ? Text(tr('शुरू करें')) : const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
