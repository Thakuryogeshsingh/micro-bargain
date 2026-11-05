import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'core/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushService.init();
  runApp(const ProviderScope(retry: _retry, child: MicroBargainApp()));
}

/// Retry failed loads only for network trouble (3 times). Server answers such as 403/404 will not
/// change by asking again, so the screen shows the error with its own retry button instead.
Duration? _retry(int retryCount, Object error) {
  if (error is ApiException && error.code == 'network' && retryCount < 3) {
    return Duration(seconds: 2 << retryCount);
  }
  return null;
}
