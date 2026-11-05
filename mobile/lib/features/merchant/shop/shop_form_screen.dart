import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/location/location_service.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/common.dart';
import '../../customer/customer_providers.dart';
import '../merchant_providers.dart';
import '../../../core/i18n/i18n.dart';

// i18n:off (translated where used)
const _docTypes = {
  'shop_photo': 'दुकान की फोटो',
  'id_proof': 'मालिक का ID (आधार/PAN)',
  'fssai': 'FSSAI लाइसेंस',
  'gst': 'GST सर्टिफिकेट',
};
// i18n:on

/// Create the shop, or edit it once it exists. Location comes from the phone's GPS (stand inside the shop).
class ShopFormScreen extends ConsumerWidget {
  const ShopFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('मेरी दुकान'))),
      body: AsyncView(
        value: ref.watch(myShopProvider),
        onRetry: () => ref.invalidate(myShopProvider),
        data: (shop) => _ShopForm(shop: shop),
      ),
    );
  }
}

class _ShopForm extends ConsumerStatefulWidget {
  const _ShopForm({required this.shop});

  final Map<String, dynamic>? shop;

  @override
  ConsumerState<_ShopForm> createState() => _ShopFormState();
}

class _ShopFormState extends ConsumerState<_ShopForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _text = {
    for (final key in ['name', 'phone', 'address_line', 'landmark', 'city', 'pincode', 'description'])
      key: TextEditingController(text: widget.shop?[key]?.toString() ?? (key == 'city' ? 'Bharatpur' : '')),
  };
  late int? _category = widget.shop?['category'];
  late bool _delivery = widget.shop?['offers_delivery'] ?? false;
  late bool _closed = widget.shop?['is_temporarily_closed'] ?? false;
  LatLng? _location;
  bool _busy = false;

  bool get _isNew => widget.shop == null;

  Future<void> _locate() async {
    final here = await currentLocation();
    if (!mounted) return;
    if (here.isFallback) {
      showMessage(context, tr('लोकेशन नहीं मिली। फ़ोन की लोकेशन (GPS) चालू करें।'));
      return;
    }
    setState(() => _location = here);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _category == null) return;
    if (_isNew && _location == null) {
      showMessage(context, tr('पहले "दुकान की लोकेशन लें" दबाएं'));
      return;
    }
    setState(() => _busy = true);
    final body = {
      for (final e in _text.entries) e.key: e.value.text.trim(),
      'category': _category,
      'state': 'Rajasthan',
      'offers_delivery': _delivery,
      'is_temporarily_closed': _closed,
      if (_location != null) 'latitude': _location!.latitude.toStringAsFixed(6),
      if (_location != null) 'longitude': _location!.longitude.toStringAsFixed(6),
    };
    final api = ref.read(apiProvider);
    final ok = await runAction(
      context,
      () => _isNew ? api.post('/merchants/shop/create/', body) : api.patch('/merchants/shop/update/${widget.shop!['id']}/', body),
      success: _isNew ? tr('दुकान जुड़ गई! अब वेरिफिकेशन के लिए दस्तावेज़ अपलोड करें।') : tr('सेव हो गया'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(myShopProvider);
      ref.invalidate(dashboardProvider);
      if (!_isNew) context.pop();
    }
  }

  Future<void> _uploadDocument() async {
    final type = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(title: Text(tr('कौन सा दस्तावेज़?')), children: [
        for (final e in _docTypes.entries) SimpleDialogOption(onPressed: () => Navigator.pop(context, e.key), child: Text(tr(e.value))),
      ]),
    );
    if (type == null) return;
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    if (photo == null || !mounted) return;
    await runAction(context, () async {
      await ref.read(apiProvider).post('/merchants/shop/${widget.shop!['id']}/documents/', FormData.fromMap({
        'doc_type': type,
        'file': await MultipartFile.fromFile(photo.path, filename: photo.name),
      }));
    }, success: tr('{0} अपलोड हो गया', [tr(_docTypes[type]!)]));
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? tr('ज़रूरी है') : null;
    final categories = ref.watch(categoriesProvider).value ?? [];
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (!_isNew && widget.shop!['status'] != 'approved')
          Card(
            color: Colors.orange.shade50,
            child: ListTile(
              title: Text(widget.shop!['status'] == 'rejected' ? tr('अप्रूव नहीं हुई: {0}', [widget.shop!['rejection_reason']]) : tr('वेरिफिकेशन बाकी')),
              subtitle: Text(tr('दुकान की फोटो और ID अपलोड करें')),
              trailing: FilledButton.tonal(onPressed: _uploadDocument, child: Text(tr('अपलोड'))),
            ),
          ),
        TextFormField(controller: _text['name'], decoration: InputDecoration(labelText: tr('दुकान का नाम')), validator: required),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _category,
          decoration: InputDecoration(labelText: tr('दुकान का प्रकार')),
          items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.label))],
          onChanged: (v) => setState(() => _category = v),
          validator: (v) => v == null ? tr('चुनें') : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _text['phone'],
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: tr('दुकान का फ़ोन (ग्राहक कॉल कर सकें)')),
        ),
        TextFormField(controller: _text['address_line'], decoration: InputDecoration(labelText: tr('पता')), validator: required),
        const SizedBox(height: 12),
        TextFormField(controller: _text['landmark'], decoration: InputDecoration(labelText: tr('लैंडमार्क'))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(controller: _text['city'], decoration: InputDecoration(labelText: tr('शहर')), validator: required)),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _text['pincode'],
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: tr('पिनकोड')),
              validator: (v) => (v ?? '').length == 6 ? null : tr('6 अंक'),
            ),
          ),
        ]),
        TextFormField(controller: _text['description'], maxLines: 2, decoration: InputDecoration(labelText: tr('दुकान के बारे में'))),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _locate,
          icon: Icon(_location == null ? Icons.my_location : Icons.check_circle, color: _location == null ? null : Colors.green),
          label: Text(_location == null
              ? (_isNew ? tr('दुकान की लोकेशन लें (दुकान में खड़े होकर)') : tr('लोकेशन बदलें'))
              : tr('लोकेशन मिल गई ({0}, {1})', [_location!.latitude.toStringAsFixed(4), _location!.longitude.toStringAsFixed(4)])),
        ),
        SwitchListTile(title: Text(tr('होम डिलीवरी करते हैं')), value: _delivery, onChanged: (v) => setState(() => _delivery = v)),
        if (!_isNew)
          SwitchListTile(
            title: Text(tr('दुकान अभी बंद है')),
            subtitle: Text(tr('चालू करने पर आपकी डील ग्राहकों को नहीं दिखेंगी')),
            value: _closed,
            onChanged: (v) => setState(() => _closed = v),
          ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_isNew ? tr('दुकान जोड़ें') : tr('सेव करें'))),
      ]),
    );
  }
}
