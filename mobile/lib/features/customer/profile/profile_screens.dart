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
import '../../../shared/widgets/location_picker.dart';
import '../../settings/language_screen.dart';
import '../../settings/theme_screen.dart';
import '../customer_providers.dart';
import '../plus/plus_screens.dart';
import '../../../core/i18n/i18n.dart';

Future<void> editName(BuildContext context, WidgetRef ref) async {
  final name = await askText(context, tr('आपका नाम'));
  if (name == null || name.isEmpty || !context.mounted) return;
  if (await runAction(context, () => ref.read(apiProvider).patch('/auth/profile/update/', {'name': name}))) {
    await ref.read(sessionProvider.notifier).reloadUser();
  }
}

/// Play Store requires apps with login to let users delete their account from inside the app.
Future<void> deleteAccount(BuildContext context, WidgetRef ref) async {
  final sure = await confirm(context, tr('अकाउंट हमेशा के लिए डिलीट करें?'),
      message: tr('आपका नाम, नंबर, पते और पसंदीदा हट जाएंगे। पुराने ऑर्डर का हिसाब (बिना आपकी पहचान के) रखा जाएगा।'),
      ok: tr('डिलीट करें'), icon: Icons.delete_forever_rounded, danger: true);
  if (!sure || !context.mounted) return;
  if (await runAction(context, () => ref.read(apiProvider).post('/auth/delete-account/', {}))) {
    await ref.read(sessionProvider.notifier).signOutLocally();
  }
}

/// Privacy policy, terms and refund policy links (opened in the browser).
List<Widget> legalTiles() => [
      for (final page in {'privacy': tr('प्राइवेसी पॉलिसी'), 'terms': tr('नियम और शर्तें'), 'refunds': tr('रिफंड पॉलिसी'), 'photo-credits': tr('फोटो क्रेडिट')}.entries)
        ListTile(
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: Text(page.value),
          onTap: () => launchUrl(Uri.parse('${AppConfig.siteUrl}/legal/${page.key}/'), mode: LaunchMode.externalApplication),
        ),
    ];

Future<void> logout(BuildContext context, WidgetRef ref) async {
  if (await confirm(context, tr('लॉग आउट करें?'), icon: Icons.logout_rounded)) {
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
      appBar: AppBar(title: Text(tr('प्रोफाइल'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 110), children: [
        const ImpactCard(),
        const PlusBanner(),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user?.displayName ?? ''),
          subtitle: Text('+91 ${user?.phone ?? ''}'),
          trailing: const Icon(Icons.edit),
          onTap: () => editName(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text(tr('मेरे पते')),
          onTap: () => context.push('/addresses'),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: Text(tr('पसंदीदा दुकानें')),
          onTap: () => context.push('/favorites'),
        ),
        SectionTitle(tr('डील सेटिंग्स')),
        AsyncView(
          value: profile,
          data: (p) => Column(children: [
            ListTile(
              title: Text(tr('डील कितनी दूर तक दिखाएं')),
              subtitle: Wrap(spacing: 6, children: [
                for (final r in AppConfig.searchRadiiMeters)
                  ChoiceChip(label: Text(distance(r)), selected: p['search_radius_m'] == r, onSelected: (_) => setPref('search_radius_m', r)),
              ]),
            ),
            SwitchListTile(
              title: Text(tr('पास की नई डील की सूचना')),
              value: p['notify_nearby_deals'] == true,
              onChanged: (v) => setPref('notify_nearby_deals', v),
            ),
            SwitchListTile(
              title: Text(tr('पसंदीदा दुकान की नई डील')),
              value: p['notify_favorite_shops'] == true,
              onChanged: (v) => setPref('notify_favorite_shops', v),
            ),
            SwitchListTile(
              title: Text(tr('ऑर्डर / रिज़र्वेशन अपडेट')),
              value: p['notify_order_updates'] == true,
              onChanged: (v) => setPref('notify_order_updates', v),
            ),
          ]),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF15803D)),
          title: Text(tr('मेरा वॉलेट')),
          subtitle: Text(tr('हर खरीद पर कैशबैक')),
          onTap: () => context.push('/wallet'),
        ),
        ListTile(
          leading: const Icon(Icons.card_giftcard_rounded, color: Color(0xFF7C3AED)),
          title: Text(tr('दोस्तों को बुलाएं')),
          subtitle: Text(tr('दोस्त को बुलाएं, दोनों पाएं ₹{0}', [50])),
          onTap: () => context.push('/referral'),
        ),
        const LanguageTile(),
        const ThemeTile(),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: Text(tr('मदद और शिकायत')),
          onTap: () => context.push('/support'),
        ),
        ListTile(
          leading: const Icon(Icons.currency_exchange_rounded, color: Color(0xFFDB2777)),
          title: Text(tr('रिफंड और शिकायतें')),
          subtitle: Text(tr('रिफंड का हाल, क्वालिटी शिकायतें और पॉलिसी')),
          onTap: () => context.push('/refunds'),
        ),
        ListTile(
          leading: const Icon(Icons.event_repeat_rounded, color: Color(0xFF0EA5E9)),
          title: Text(tr('रोज़ाना डिलीवरी')),
          subtitle: Text(tr('दूध, ब्रेड — हर सुबह अपने आप')),
          onTap: () => context.push('/daily'),
        ),
        ListTile(
          leading: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF97316)),
          title: Text(tr('पॉइंट और स्ट्रीक')),
          subtitle: Text(tr('हर खरीद पर पॉइंट, वॉलेट में बदलें')),
          onTap: () => context.push('/loyalty'),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined, color: Color(0xFF0EA5E9)),
          title: Text(tr('दाम अलर्ट')),
          onTap: () => context.push('/alerts'),
        ),
        ListTile(
          leading: const Icon(Icons.checklist_rounded, color: Color(0xFF15803D)),
          title: Text(tr('शॉपिंग लिस्ट')),
          onTap: () => context.push('/shopping-list'),
        ),
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF7C3AED)),
          title: Text(tr('मैसेज')),
          onTap: () => context.push('/chats'),
        ),
        ListTile(
          leading: const Icon(Icons.storefront),
          title: Text(tr('अपनी दुकान जोड़ें')),
          subtitle: Text(tr('दुकानदार हैं? अपनी डील यहां बेचें')),
          onTap: () => context.push('/become-merchant'),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(tr('लॉग आउट')),
          onTap: () => logout(context, ref),
        ),
        ...legalTiles(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
          title: Text(tr('अकाउंट डिलीट करें'), style: const TextStyle(color: Colors.red)),
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
      appBar: AppBar(title: Text(tr('मेरे पते'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/addresses/new');
          ref.invalidate(addressesProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(tr('नया पता')),
      ),
      body: AsyncView(
        value: ref.watch(addressesProvider),
        onRetry: () => ref.invalidate(addressesProvider),
        data: (list) => list.isEmpty
            ? EmptyView(icon: Icons.location_off, message: tr('अभी कोई पता नहीं'))
            : ListView(children: [
                for (final a in list)
                  ListTile(
                    leading: Icon(a.isDefault ? Icons.home : Icons.location_on_outlined),
                    title: Text(a.label + (a.isDefault ? tr(' (डिफ़ॉल्ट)') : '')),
                    subtitle: Text('${a.line}, ${a.city} ${a.pincode}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (!await confirm(context, tr('यह पता हटाएं?'), icon: Icons.wrong_location_outlined, danger: true)) return;
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
  final _label = TextEditingController(text: tr('घर'));
  final _line = TextEditingController();
  final _landmark = TextEditingController();
  final _city = TextEditingController(text: 'Bharatpur');
  final _pincode = TextEditingController();
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  bool _default = true;
  bool _busy = false;
  bool _forSomeoneElse = false;
  PickedPlace? _place;
  String _state = 'Rajasthan';

  Future<void> _pickOnMap() async {
    final here = ref.read(locationProvider).value;
    final place = await pickLocationOnMap(context,
        latitude: _place?.latitude ?? here?.latitude, longitude: _place?.longitude ?? here?.longitude, title: tr('पता मैप पर चुनें'));
    if (place == null || !mounted) return;
    setState(() {
      _place = place;
      if (place.city.isNotEmpty) _city.text = place.city;
      if (place.state.isNotEmpty) _state = place.state;
      if (place.pincode.length == 6) _pincode.text = place.pincode;
      if (_line.text.trim().isEmpty && place.line.isNotEmpty) _line.text = place.line;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final here = _place == null ? await currentLocation() : LatLng(_place!.latitude, _place!.longitude);
    if (!mounted) return;
    if (here.isFallback &&
        !await confirm(context, tr('लोकेशन नहीं मिली'), message: tr('डिलीवरी के लिए सही लोकेशन ज़रूरी है। फिर भी शहर के केंद्र से सेव करें?'), icon: Icons.location_off_outlined)) {
      setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    final ok = await runAction(context, () => ref.read(apiProvider).post('/customers/addresses/', {
          'label': _label.text.trim(),
          'address_line': _line.text.trim(),
          'landmark': _landmark.text.trim(),
          'city': _city.text.trim(),
          'state': _state,
          'pincode': _pincode.text.trim(),
          if (_forSomeoneElse) 'contact_name': _contactName.text.trim(),
          if (_forSomeoneElse) 'contact_phone': _contactPhone.text.trim(),
          'latitude': here.latitude.toStringAsFixed(6),
          'longitude': here.longitude.toStringAsFixed(6),
          'is_default': _default,
        }), success: tr('पता सेव हो गया'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? tr('ज़रूरी है') : null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('नया पता'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              leading: Icon(_place == null ? Icons.map_outlined : Icons.check_circle_rounded,
                  color: _place == null ? null : const Color(0xFF15803D)),
              title: Text(_place == null ? tr('📍 मैप पर लोकेशन चुनें') : tr('लोकेशन चुनी गई: {0}', [_place!.city])),
              subtitle: Text(_place == null
                  ? tr('किसी भी शहर का पता — नहीं चुना तो आपकी अभी की लोकेशन ली जाएगी')
                  : tr('बदलने के लिए दबाएं')),
              onTap: _pickOnMap,
            ),
          ),
          SwitchListTile(
            title: Text(tr('यह पता किसी और का है')),
            subtitle: Text(tr('परिवार या दोस्त के लिए ऑर्डर — सामान उन्हें मिलेगा')),
            value: _forSomeoneElse,
            onChanged: (v) => setState(() {
              _forSomeoneElse = v;
              if (v && _label.text == tr('घर')) _label.text = '';
            }),
          ),
          if (_forSomeoneElse) ...[
            TextFormField(controller: _contactName, decoration: InputDecoration(labelText: tr('पाने वाले का नाम')), validator: required),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contactPhone,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: tr('पाने वाले का मोबाइल'), prefixText: '+91 '),
              validator: (v) => RegExp(r'^[6-9]\d{9}$').hasMatch(v ?? '') ? null : tr('10 अंकों का मोबाइल नंबर'),
            ),
          ],
          const SizedBox(height: 8),
          TextFormField(
            controller: _label,
            decoration: InputDecoration(labelText: _forSomeoneElse ? tr('नाम (जैसे: मम्मी का घर)') : tr('नाम (घर / ऑफिस)')),
            validator: required,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _line, decoration: InputDecoration(labelText: tr('मकान नं., गली, मोहल्ला')), validator: required),
          const SizedBox(height: 12),
          TextFormField(controller: _landmark, decoration: InputDecoration(labelText: tr('पास में (लैंडमार्क)'))),
          const SizedBox(height: 12),
          TextFormField(controller: _city, decoration: InputDecoration(labelText: tr('शहर')), validator: required),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pincode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: tr('पिनकोड')),
            validator: (v) => (v ?? '').length == 6 ? null : tr('6 अंकों का पिनकोड'),
          ),
          SwitchListTile(title: Text(tr('डिफ़ॉल्ट पता')), value: _default, onChanged: (v) => setState(() => _default = v)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: Text(tr('सेव करें'))),
        ]),
      ),
    );
  }
}
