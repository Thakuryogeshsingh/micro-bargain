import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../../shared/widgets/common.dart';
import '../customer_providers.dart';
import '../../../core/i18n/i18n.dart';

/// "मेरी बुकिंग": reservations (pay at shop) and orders in two tabs.
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('मेरी बुकिंग')),
          bottom: TabBar(tabs: [Tab(text: tr('रिज़र्वेशन')), Tab(text: tr('ऑर्डर'))]),
        ),
        body: TabBarView(children: [
          RefreshIndicator(
            onRefresh: () => ref.refresh(myReservationsProvider.future),
            child: AsyncView(
              value: ref.watch(myReservationsProvider),
              onRetry: () => ref.invalidate(myReservationsProvider),
              data: (items) => items.isEmpty
                  ? ListView(children: [const SizedBox(height: 120), EmptyView(icon: Icons.bookmark_border, message: tr('अभी कोई रिज़र्वेशन नहीं'))])
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final r = items[i];
                        return Card(
                          child: ListTile(
                            title: Text('${r.productName} · ${qty(r.quantity)} ${unitLabel(r.unit)}'),
                            subtitle: Text('${r.shopName}\n${r.number} · ${dateTime(r.createdAt)}'),
                            isThreeLine: true,
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(rupees(r.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                              StatusChip(r.status),
                            ]),
                            onTap: () => context.push('/reservation/${r.id}'),
                          ),
                        );
                      },
                    ),
            ),
          ),
          RefreshIndicator(
            onRefresh: () => ref.refresh(myOrdersProvider.future),
            child: AsyncView(
              value: ref.watch(myOrdersProvider),
              onRetry: () => ref.invalidate(myOrdersProvider),
              data: (items) => items.isEmpty
                  ? ListView(children: [const SizedBox(height: 120), EmptyView(icon: Icons.receipt_long, message: tr('अभी कोई ऑर्डर नहीं'))])
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final o = items[i];
                        return Card(
                          child: ListTile(
                            title: Text(tr('{0} · {1} सामान', [o.shopName, o.items.length])),
                            subtitle: Text('${o.number} · ${o.isDelivery ? tr('डिलीवरी') : tr('पिकअप')}\n${dateTime(o.createdAt)}'),
                            isThreeLine: true,
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(rupees(o.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                              StatusChip(o.status),
                            ]),
                            onTap: () => context.push('/order/${o.id}'),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
