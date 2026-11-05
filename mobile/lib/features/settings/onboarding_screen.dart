import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../shared/widgets/brand.dart';

/// Three welcome slides shown once, after picking the language.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Photos: Wikimedia Commons (see the photo credits page).
  List<(String, String, String)> get _slides => [
        ('assets/images/welcome_1.jpg', tr('पास की दुकानों की ताज़ा डील'), tr('फल, सब्ज़ी, दूध और किराने पर रोज़ नई छूट — आपके आस-पास।')),
        ('assets/images/welcome_2.jpg', tr('रिज़र्व करें, दुकान से उठाएं'), tr('एक टैप में सामान अपने लिए रखवाएं और अपने समय पर ले जाएं।')),
        ('assets/images/welcome_3.jpg', tr('हर खरीद पर बचत'), tr('ऑफ़र, कूपन और दोस्तों को बुलाने पर इनाम।')),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(children: [
              const BrandLockup(size: 34),
              const Spacer(),
              TextButton(onPressed: _finish, child: Text(tr('छोड़ें'))),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: slides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final (photo, title, body) = slides[i];
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
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: Image.asset(photo, fit: BoxFit.cover, width: double.infinity),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(title,
                          style: TextStyle(fontSize: 32, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -1.1, color: AppTheme.ink)),
                      const SizedBox(height: 10),
                      Text(body, style: TextStyle(fontSize: 16, color: AppTheme.muted, height: 1.45)),
                      const SizedBox(height: 8),
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
