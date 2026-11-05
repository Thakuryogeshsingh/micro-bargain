import 'dart:async';

import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../network/api_client.dart';
import '../../core/i18n/i18n.dart';

/// Pays for an order, plan or promotion: asks the server for a Razorpay order, opens Razorpay Checkout,
/// then sends the result back for server-side signature verification. Returns true when paid.
///
/// With the server's development payment backend (no Razorpay key), a "test payment" dialog stands in for Checkout.
Future<bool> payOnline(BuildContext context, ApiClient api, {required String purpose, required int id}) async {
  final checkout = Map<String, dynamic>.from(await api.post('/payments/create/', {'purpose': purpose, 'id': id}));
  if ((checkout['key_id'] as String? ?? '').isEmpty) {
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('टेस्ट पेमेंट')),
        content: Text(tr('सर्वर टेस्ट मोड में है। ₹{0} का नकली पेमेंट करें?', [(checkout['amount'] as int) / 100])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('रद्द'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('पेमेंट करें'))),
        ],
      ),
    );
    if (ok != true) return false;
    await api.post('/payments/dev-complete/', {'razorpay_order_id': checkout['razorpay_order_id']});
    return true;
  }

  final result = Completer<PaymentSuccessResponse?>();
  final razorpay = Razorpay()
    ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) => result.complete(r))
    ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) => result.complete(null))
    ..on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) => result.complete(null));
  razorpay.open({
    'key': checkout['key_id'],
    'amount': checkout['amount'],
    'currency': checkout['currency'],
    'order_id': checkout['razorpay_order_id'],
    'name': checkout['name'],
    'description': checkout['description'],
    'prefill': {'contact': checkout['prefill_contact']},
  });
  final success = await result.future;
  razorpay.clear();
  if (success == null) return false;
  await api.post('/payments/verify/', {
    'razorpay_order_id': success.orderId,
    'razorpay_payment_id': success.paymentId,
    'razorpay_signature': success.signature,
  });
  return true;
}
