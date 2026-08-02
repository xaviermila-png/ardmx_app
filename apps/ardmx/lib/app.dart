import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bluetooth/bluetooth_connection_state.dart';
import 'routing/app_router.dart';
import 'state/providers.dart';
import 'theme/ardmx_theme.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  late final ScreenMirrorObserver _observer;
  ProviderSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _observer = ScreenMirrorObserver(ref);
    // Re-assert the current screen's V50 after every (re)connection, so the
    // Arduino learns the true current screen even if navigation happened
    // while offline.
    _connectionSubscription = ref.listenManual(
      bluetoothConnectionServiceProvider,
      (previous, next) {
        final wasConnected =
            previous?.status == BluetoothConnectionStatus.connected;
        final isConnected = next.status == BluetoothConnectionStatus.connected;
        if (!wasConnected && isConnected) {
          _observer.resyncCurrent();
        }
      },
    );
  }

  @override
  void dispose() {
    _connectionSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ARDMX',
      theme: ArdmxTheme.light,
      darkTheme: ArdmxTheme.dark,
      themeMode: ThemeMode.system,
      navigatorObservers: [_observer],
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}
