import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/widgets/common.dart';

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

  Future<void> _submit() async {
    final ok = await runAction(context, () => widget.api.post('/reviews/create/', {
          if (widget.reservationId != null) 'reservation': widget.reservationId,
          if (widget.orderId != null) 'order': widget.orderId,
          'rating': _rating,
          'comment': _comment.text.trim(),
        }), success: 'धन्यवाद! आपकी रेटिंग सेव हो गई');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${widget.shopName} कैसी लगी?', style: Theme.of(context).textTheme.titleLarge),
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
          decoration: const InputDecoration(hintText: 'सामान की ताज़गी, दुकानदार का व्यवहार… (ज़रूरी नहीं)'),
        ),
        FilledButton(onPressed: _submit, child: const Text('भेजें')),
      ]),
    );
  }
}
