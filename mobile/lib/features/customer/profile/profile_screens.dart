import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/app_config.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/push/push_service.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../customer_providers.dart';

Future<void> editName(BuildContext context, WidgetRef ref) async {
  final name = await askText(context, 'आपका नाम');
  if (name == null || name.isEmpty || !context.mounted) return;
  if (await runAction(context, () => ref.read(apiProvider).patch('/auth/profile/update/', {'name': name}))) {
    await ref.read(sessionProvider.notifier).reloadUser();
  }
}

/// Play Store requires apps with login to let users delete their account from inside the app.
Future<void> deleteAccount(BuildContext context, WidgetRef ref) async {
  final sure = await confirm(context, 'अकाउंट हमेशा के लिए डिलीट करें?',
      message: 'आपका नाम, नंबर, पते और पसंदीदा हट जाएंगे। पुराने ऑर्डर का हिसाब (बिना आपकी पहचान के) रखा जाएगा।',
      ok: 'डिलीट करें');
  if (!sure || !context.mounted) return;
  if (await runAction(context, () => ref.read(apiProvider).post('/auth/delete-account/', {}))) {
    await ref.read(sessionProvider.notifier).signOutLocally();
  }
}

/// Privacy policy, terms and refund policy links (opened in the browser).
List<Widget> legalTiles() => [
      for (final page in const {'privacy': 'प्राइवेसी पॉलिसी', 'terms': 'नियम और शर्तें', 'refunds': 'रिफंड पॉलिसी'}.entries)
        ListTile(
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: Text(page.value),
          onTap: () => launchUrl(Uri.parse('${AppConfig.siteUrl}/legal/${page.key}/'), mode: LaunchMode.externalApplication),
        ),
    ];

Future<void> logout(BuildContext context, WidgetRef ref) async {
  if (await confirm(context, 'लॉग आउट करें?')) {
    await ref.read(sessionProvider.notifier).signOut(deviceToken: PushService.token);
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    final profile = ref.watch(customerProfileProvider);

    Future<void> setPref(String key, Object value) async {
      if (await runAction(context, () => ref.read(apiProvider).patch('/customers/profile/', {key: value}))) {
        ref.invalidate(customerProfileProvider);
        if (key == 'search_radius_m') {
          ref.read(dealFiltersProvider.notifier).update((f) => f.copyWith(radius: value as int));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('प्रोफाइल')),
      body: ListView(children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user?.displayName ?? ''),
          subtitle: Text('+91 ${user?.phone ?? ''}'),
          trailing: const Icon(Icons.edit),
          onTap: () => editName(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: const Text('मेरे पते'),
          onTap: () => context.push('/addresses'),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: const Text('पसंदीदा दुकानें'),
          onTap: () => context.push('/favorites'),
        ),
        const SectionTitle('डील सेटिंग्स'),
        AsyncView(
          value: profile,
          data: (p) => Column(children: [
            ListTile(
              title: const Text('डील कितनी दूर तक दिखाएं'),
              subtitle: Wrap(spacing: 6, children: [
                for (final r in AppConfig.searchRadiiMeters)
                  ChoiceChip(label: Text(distance(r)), selected: p['search_radius_m'] == r, onSelected: (_) => setPref('search_radius_m', r)),
              ]),
            ),
            SwitchListTile(
              title: const Text('पास की नई डील की सूचना'),
              value: p['notify_nearby_deals'] == true,
              onChanged: (v) => setPref('notify_nearby_deals', v),
            ),
            SwitchListTile(
              title: const Text('पसंदीदा दुकान की नई डील'),
              value: p['notify_favorite_shops'] == true,
              onChanged: (v) => setPref('notify_favorite_shops', v),
            ),
            SwitchListTile(
              title: const Text('ऑर्डर / रिज़र्वेशन अपडेट'),
              value: p['notify_order_updates'] == true,
              onChanged: (v) => setPref('notify_order_updates', v),
            ),
          ]),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: const Text('मदद और शिकायत'),
          onTap: () => context.push('/support'),
        ),
        ListTile(
          leading: const Icon(Icons.storefront),
          title: const Text('अपनी दुकान जोड़ें'),
          subtitle: const Text('दुकानदार हैं? अपनी डील यहां बेचें'),
          onTap: () => context.push('/become-merchant'),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('लॉग आउट'),
          onTap: () => logout(context, ref),
        ),
        ...legalTiles(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
          title: const Text('अकाउंट डिलीट करें', style: TextStyle(color: Colors.red)),
          onTap: () => deleteAccount(context, ref),
        ),
      ]),
    );
  }
}

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('मेरे पते')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/addresses/new');
          ref.invalidate(addressesProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('नया पता'),
      ),
      body: AsyncView(
        value: ref.watch(addressesProvider),
        onRetry: () => ref.invalidate(addressesProvider),
        data: (list) => list.isEmpty
            ? const EmptyView(icon: Icons.location_off, message: 'अभी कोई पता नहीं')
            : ListView(children: [
                for (final a in list)
                  ListTile(
                    leading: Icon(a.isDefault ? Icons.home : Icons.location_on_outlined),
                    title: Text(a.label + (a.isDefault ? ' (डिफ़ॉल्ट)' : '')),
                    subtitle: Text('${a.line}, ${a.city} ${a.pincode}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (!await confirm(context, 'यह पता हटाएं?')) return;
                        if (context.mounted && await runAction(context, () => ref.read(apiProvider).delete('/customers/addresses/${a.id}/'))) {
                          ref.invalidate(addressesProvider);
                        }
                      },
                    ),
                  ),
              ]),
      ),
    );
  }
}

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key});

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'घर');
  final _line = TextEditingController();
  final _landmark = TextEditingController();
  final _city = TextEditingController(text: 'Bharatpur');
  final _pincode = TextEditingController();
  bool _default = true;
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final here = await currentLocation();
    if (!mounted) return;
    if (here.isFallback &&
        !await confirm(context, 'लोकेशन नहीं मिली', message: 'डिलीवरी के लिए सही लोकेशन ज़रूरी है। फिर भी शहर के केंद्र से सेव करें?')) {
      setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    final ok = await runAction(context, () => ref.read(apiProvider).post('/customers/addresses/', {
          'label': _label.text.trim(),
          'address_line': _line.text.trim(),
          'landmark': _landmark.text.trim(),
          'city': _city.text.trim(),
          'state': 'Rajasthan',
          'pincode': _pincode.text.trim(),
          'latitude': here.latitude.toStringAsFixed(6),
          'longitude': here.longitude.toStringAsFixed(6),
          'is_default': _default,
        }), success: 'पता सेव हो गया');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? 'ज़रूरी है' : null;
    return Scaffold(
      appBar: AppBar(title: const Text('नया पता')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('📍 पता सेव करते समय आपकी अभी की लोकेशन ली जाएगी — घर पर रहकर सेव करें।'),
          const SizedBox(height: 16),
          TextFormField(controller: _label, decoration: const InputDecoration(labelText: 'नाम (घर / ऑफिस)'), validator: required),
          const SizedBox(height: 12),
          TextFormField(controller: _line, decoration: const InputDecoration(labelText: 'मकान नं., गली, मोहल्ला'), validator: required),
          const SizedBox(height: 12),
          TextFormField(controller: _landmark, decoration: const InputDecoration(labelText: 'पास में (लैंडमार्क)')),
          const SizedBox(height: 12),
          TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'शहर'), validator: required),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pincode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'पिनकोड'),
            validator: (v) => (v ?? '').length == 6 ? null : '6 अंकों का पिनकोड',
          ),
          SwitchListTile(title: const Text('डिफ़ॉल्ट पता'), value: _default, onChanged: (v) => setState(() => _default = v)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('सेव करें')),
        ]),
      ),
    );
  }
}
