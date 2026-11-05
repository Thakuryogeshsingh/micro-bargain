import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/common.dart';
import '../../../core/i18n/i18n.dart';

Future<void> showReviewSheet(BuildContext context, WidgetRef ref, {int? reservationId, int? orderId, required String shopName}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReviewSheet(api: ref.read(apiProvider), reservationId: reservationId, orderId: orderId, shopName: shopName),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.api, this.reservationId, this.orderId, required this.shopName});

  final ApiClient api;
  final int? reservationId;
  final int? orderId;
  final String shopName;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;
  final _comment = TextEditingController();
  XFile? _photo;

  Future<void> _pickPhoto(ImageSource source) async {
    final photo = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1400);
    if (photo != null) setState(() => _photo = photo);
  }

  Future<void> _submit() async {
    final ok = await runAction(context, () async => widget.api.post('/reviews/create/', FormData.fromMap({
          if (widget.reservationId != null) 'reservation': widget.reservationId,
          if (widget.orderId != null) 'order': widget.orderId,
          'rating': _rating,
          'comment': _comment.text.trim(),
          if (_photo != null) 'photo': await MultipartFile.fromFile(_photo!.path, filename: _photo!.name),
        })), success: tr('धन्यवाद! आपकी रेटिंग सेव हो गई'));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tr('{0} कैसी लगी?', [widget.shopName]), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 36,
              onPressed: () => setState(() => _rating = i),
              icon: Icon(i <= _rating ? Icons.star : Icons.star_border, color: Colors.amber.shade700),
            ),
        ]),
        TextField(
          controller: _comment,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(hintText: tr('सामान की ताज़गी, दुकानदार का व्यवहार… (ज़रूरी नहीं)')),
        ),
        if (_photo == null)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton.icon(
              onPressed: () => _pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_rounded),
              label: Text(tr('फोटो खींचें')),
            ),
            TextButton.icon(
              onPressed: () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded),
              label: Text(tr('गैलरी')),
            ),
          ])
        else
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(File(_photo!.path), height: 120, width: 160, fit: BoxFit.cover),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.black54,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => setState(() => _photo = null),
                ),
              ),
            ),
          ]),
        const SizedBox(height: 8),
        FilledButton(onPressed: _submit, child: Text(tr('भेजें'))),
      ]),
    );
  }
}
