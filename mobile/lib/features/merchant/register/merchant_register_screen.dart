import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/common.dart';
import '../../customer/customer_providers.dart';
import '../merchant_providers.dart';
import '../../../core/i18n/i18n.dart';

/// Turns the logged-in account into a merchant account. The router then switches to the merchant app.
class MerchantRegisterScreen extends ConsumerStatefulWidget {
  const MerchantRegisterScreen({super.key});

  @override
  ConsumerState<MerchantRegisterScreen> createState() => _MerchantRegisterScreenState();
}

class _MerchantRegisterScreenState extends ConsumerState<MerchantRegisterScreen> {
  final _owner = TextEditingController();
  int? _category;

  Future<void> _submit() async {
    if (_owner.text.trim().isEmpty || _category == null) {
      showMessage(context, tr('नाम और दुकान का प्रकार चुनें'));
      return;
    }
    final ok = await runAction(context, () => ref.read(apiProvider).post('/merchants/register/', {
          'owner_name': _owner.text.trim(),
          'business_category': _category,
        }));
    if (ok) {
      ref.read(openOnboardingProvider.notifier).set(true);
      await ref.read(sessionProvider.notifier).reloadUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('अपनी दुकान जोड़ें'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('अपनी बची हुई / जल्दी खराब होने वाली चीज़ें छूट पर बेचें और पास के ग्राहकों तक पहुंचें।')),
        const SizedBox(height: 8),
        Text(tr('ध्यान दें: यह नंबर दुकानदार अकाउंट बन जाएगा।'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        TextField(controller: _owner, decoration: InputDecoration(labelText: tr('मालिक का नाम'))),
        const SizedBox(height: 12),
        AsyncView(
          value: categories,
          data: (list) => DropdownButtonFormField<int>(
            initialValue: _category,
            decoration: InputDecoration(labelText: tr('दुकान का प्रकार')),
            items: [for (final c in list) DropdownMenuItem(value: c.id, child: Text('${c.icon} ${c.label}'.trim()))],
            onChanged: (v) => setState(() => _category = v),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _submit, child: Text(tr('दुकानदार बनें'))),
      ]),
    );
  }
}
