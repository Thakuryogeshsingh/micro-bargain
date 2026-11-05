import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/deal_card.dart';
import '../../customer/customer_providers.dart';
import '../merchant_providers.dart';
import '../../../core/i18n/i18n.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('मेरे प्रोडक्ट'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/merchant/product-form');
          ref.invalidate(merchantProductsProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(tr('नया प्रोडक्ट')),
      ),
      body: AsyncView(
        value: ref.watch(merchantProductsProvider),
        onRetry: () => ref.invalidate(merchantProductsProvider),
        data: (products) => products.isEmpty
            ? EmptyView(icon: Icons.inventory_2_outlined, message: tr('पहले अपने प्रोडक्ट जोड़ें (जैसे "टमाटर", "दूध 500ml")। फिर उन पर डील बनाएं।'))
            : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final p in products)
                  ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: DealImage(p.images.isEmpty ? null : p.images.first, size: 48, name: p.name),
                    ),
                    title: Text(p.name + (p.isActive ? '' : tr(' (बंद)'))),
                    subtitle: Text('${rupees(p.standardPrice)}/${unitLabel(p.unit)}'),
                    trailing: const Icon(Icons.edit),
                    onTap: () async {
                      await context.push('/merchant/product-form', extra: p);
                      ref.invalidate(merchantProductsProvider);
                    },
                  ),
              ]),
      ),
    );
  }
}

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product});

  final Product? product;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _price = TextEditingController(text: widget.product == null ? '' : qty(widget.product!.standardPrice));
  late final _description = TextEditingController(text: widget.product?.description);
  late String _unit = widget.product?.unit ?? 'kg';
  late int? _category = widget.product?.categoryId;
  late bool _active = widget.product?.isActive ?? true;
  XFile? _photo;
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _category == null) return;
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    final ok = await runAction(context, () async {
      final shop = await ref.read(myShopProvider.future);
      if (shop == null) throw ApiException(tr('पहले दुकान जोड़ें'));
      final body = {
        'shop': shop['id'],
        'category': _category,
        'name': _name.text.trim(),
        'unit': _unit,
        'standard_price': _price.text.trim(),
        'description': _description.text.trim(),
        'is_active': _active,
      };
      final saved = widget.product == null
          ? await api.post('/products/create/', body)
          : await api.patch('/products/update/${widget.product!.id}/', body);
      if (_photo != null) {
        await api.post('/products/upload-image/', FormData.fromMap({
          'product': saved['id'],
          'image': await MultipartFile.fromFile(_photo!.path, filename: _photo!.name),
        }));
      }
    }, success: tr('प्रोडक्ट सेव हो गया'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  Future<void> _delete() async {
    if (!await confirm(context, tr('प्रोडक्ट हटाएं?'), message: tr('अगर इस पर डील बनी है तो इसे सिर्फ बंद किया जाएगा।'))) return;
    if (!mounted) return;
    if (await runAction(context, () => ref.read(apiProvider).delete('/products/delete/${widget.product!.id}/'))) {
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? tr('नया प्रोडक्ट') : tr('प्रोडक्ट बदलें')),
        actions: [if (widget.product != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: tr('प्रोडक्ट का नाम'), hintText: tr('जैसे: टमाटर (देसी)')),
            validator: (v) => (v ?? '').trim().isEmpty ? tr('ज़रूरी है') : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _category,
            decoration: InputDecoration(labelText: tr('कैटेगरी')),
            items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.label))],
            onChanged: (v) => setState(() => _category = v),
            validator: (v) => v == null ? tr('चुनें') : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('सामान्य दाम (₹)'), prefixText: '₹ '),
                validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0 ? null : tr('सही दाम'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: InputDecoration(labelText: tr('प्रति')),
                items: [for (final e in unitLabels.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
                onChanged: (v) => setState(() => _unit = v!),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: _description, maxLines: 2, decoration: InputDecoration(labelText: tr('विवरण'))),
          SwitchListTile(title: Text(tr('प्रोडक्ट चालू है')), value: _active, onChanged: (v) => setState(() => _active = v)),
          OutlinedButton.icon(
            onPressed: () async {
              final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1200);
              if (photo != null) setState(() => _photo = photo);
            },
            icon: Icon(_photo == null ? Icons.photo_camera : Icons.check_circle),
            label: Text(_photo == null ? tr('फोटो खींचें') : tr('फोटो तैयार है')),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: Text(tr('सेव करें'))),
        ]),
      ),
    );
  }
}
