import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';

/// Shown on first launch, and from Profile / More to change the language later.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('भाषा चुनें / Choose language'), automaticallyImplyLeading: current != null),
      body: ListView(children: [
        for (final language in languages)
          ListTile(
            title: Text(language.nativeName, style: const TextStyle(fontSize: 18)),
            subtitle: Text(language.englishName),
            trailing: language.code == current ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
            onTap: () async {
              await ref.read(languageProvider.notifier).choose(language.code);
              if (!context.mounted) return;
              context.canPop() ? context.pop() : context.go('/splash');
            },
          ),
      ]),
    );
  }
}

/// List tile for settings screens.
class LanguageTile extends ConsumerWidget {
  const LanguageTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(languageProvider);
    final name = languages.firstWhere((l) => l.code == code, orElse: () => languages.first).nativeName;
    return ListTile(
      leading: const Icon(Icons.translate),
      title: const Text('भाषा / Language'),
      subtitle: Text(name),
      onTap: () => context.push('/language'),
    );
  }
}
