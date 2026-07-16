import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bluetooth_connection_state.dart';
import '../../core/bluetooth/bluetooth_error_messages.dart';
import '../../core/bluetooth/bluetooth_permissions.dart';
import '../../core/constants/app_version.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/connection_badge.dart';

/// Bluetooth connect/disconnect here is fully explicit — no auto-connect on
/// launch, no automatic reconnect on drop. This is deliberate while
/// diagnosing a real HC-05 connectivity issue: auto-retry logic made
/// failures harder to reproduce (it was found to hammer the module with
/// rapid reconnect attempts). The user picks a paired device and taps
/// Connect/Disconnect themselves.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _checkingPermission = true;
  bool _permissionDenied = false;
  bool _loadingDevices = true;
  String? _errorMessage;
  List<BluetoothDevice> _pairedDevices = const [];
  BluetoothDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _checkingPermission = true;
      _errorMessage = null;
    });
    try {
      final granted = await BluetoothPermissions.ensureGranted();
      if (!mounted) return;
      if (!granted) {
        setState(() {
          _permissionDenied = true;
          _checkingPermission = false;
          _loadingDevices = false;
        });
        return;
      }
      setState(() => _checkingPermission = false);

      final service = ref.read(bluetoothConnectionServiceProvider.notifier);
      final devices = await service.pairedDevices();
      final lastAddress = await service.lastKnownDeviceAddress();
      if (!mounted) return;

      BluetoothDevice? preselected;
      for (final device in devices) {
        if (device.address == lastAddress) {
          preselected = device;
          break;
        }
      }
      setState(() {
        _pairedDevices = devices;
        _selectedDevice =
            preselected ?? (devices.isNotEmpty ? devices.first : null);
        _loadingDevices = false;
      });
    } catch (error) {
      // Never leave the UI stuck on the loading spinner — surface the
      // failure with a way to retry instead. Observed in practice: the
      // permission_handler platform channel can throw if a request races
      // with another one during startup.
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _checkingPermission = false;
        _loadingDevices = false;
      });
    }
  }

  Future<void> _connect() async {
    final device = _selectedDevice;
    if (device == null) return;
    await ref.read(bluetoothConnectionServiceProvider.notifier).connect(device);
  }

  Future<void> _disconnect() async {
    await ref.read(bluetoothConnectionServiceProvider.notifier).disconnect();
  }

  Future<void> _exit() async {
    final status = ref.read(bluetoothConnectionServiceProvider).status;
    if (status == BluetoothConnectionStatus.connected) {
      await ref.read(bluetoothConnectionServiceProvider.notifier).disconnect();
    }
    SystemNavigator.pop();
  }

  void _goToMenu() =>
      Navigator.of(context).pushReplacementNamed(AppRoutes.mainMenu);

  void _goToCredits() => Navigator.of(context).pushNamed(AppRoutes.credits);

  Widget _buildCredits() {
    final serverVersion = ref.watch(appStateProvider.select((s) => s.t62));
    const style = TextStyle(fontSize: 9, color: Colors.grey);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('CC BY-NC-SA Xavier Mila 2026', style: style),
        const Text('Versió app: $kAppVersion', style: style),
        Text('Versió server: ${serverVersion ?? '—'}', style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(bluetoothConnectionServiceProvider);
    final connected = connection.status == BluetoothConnectionStatus.connected;
    final connecting =
        connection.status == BluetoothConnectionStatus.connecting;

    // Devices named "ARDMX4..." skip the manual "Menú" tap and go straight
    // in once connected — see feature request for the reasoning (more
    // screens to come that depend on this).
    ref.listen(bluetoothConnectionServiceProvider, (previous, next) {
      final wasConnected =
          previous?.status == BluetoothConnectionStatus.connected;
      final isConnected = next.status == BluetoothConnectionStatus.connected;
      if (!wasConnected &&
          isConnected &&
          (next.deviceName ?? '').startsWith('ARDMX4')) {
        _goToMenu();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // The Android back button bypasses the "Sortir" button entirely —
        // without this, exiting via back button never disconnected.
        if (!didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: null,
          automaticallyImplyLeading: false,
          actions: const [ConnectionBadge(), SizedBox(width: 8)],
        ),
        // The bottom Positioned row (Crèdits/CC info/Sortir) sits directly
        // in the body, not in Scaffold's floatingActionButton slot — so it
        // needs SafeArea explicitly or it renders underneath the system
        // navigation bar on devices where that bar overlays content
        // (confirmed cut off on a second test phone).
        body: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ARDMX',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Control d'Il·luminació de pessebres",
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          // Temporary (phase 2) entry point to DebugScreen for
                          // validating Bluetooth/protocol against real hardware —
                          // remove once all 7 production screens are built.
                          onLongPress: () =>
                              Navigator.of(context).pushNamed(AppRoutes.debug),
                          child: Image.asset(
                            'assets/imatges/ARDMX4_Logo.png',
                            width: 160,
                            height: 160,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_checkingPermission)
                          const CircularProgressIndicator(),
                        if (_permissionDenied) ...[
                          const Text(
                            'Cal el permís de Bluetooth per continuar.',
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: BluetoothPermissions.openSettings,
                            child: const Text('Obrir ajustos'),
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          Text(
                            "Hi ha hagut un error inicialitzant el Bluetooth:\n$_errorMessage",
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _initialize,
                            child: const Text('Reintentar'),
                          ),
                        ],
                        if (!_checkingPermission &&
                            !_permissionDenied &&
                            _errorMessage == null) ...[
                          if (_loadingDevices)
                            const CircularProgressIndicator()
                          else if (_pairedDevices.isEmpty)
                            const Text(
                              "Cap dispositiu Bluetooth emparellat.\nEmparella l'HC-05/06 des dels ajustos d'Android.",
                              textAlign: TextAlign.center,
                            )
                          else ...[
                            const Text('Selecciona Dispositiu:'),
                            const SizedBox(height: 8),
                            DropdownButton<BluetoothDevice>(
                              value: _selectedDevice,
                              items: [
                                for (final device in _pairedDevices)
                                  DropdownMenuItem(
                                    value: device,
                                    child: Text(device.name ?? '(sense nom)'),
                                  ),
                              ],
                              onChanged: (connected || connecting)
                                  ? null
                                  : (device) => setState(
                                      () => _selectedDevice = device,
                                    ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed:
                                      (!connected &&
                                          !connecting &&
                                          _selectedDevice != null)
                                      ? _connect
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(150, 48),
                                    textStyle: const TextStyle(fontSize: 16),
                                  ),
                                  icon: connecting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.bluetooth_connected),
                                  label: const Text('Connectar'),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  onPressed: connected ? _disconnect : null,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(150, 48),
                                    textStyle: const TextStyle(fontSize: 16),
                                  ),
                                  icon: const Icon(Icons.bluetooth_disabled),
                                  label: const Text('Desconnectar'),
                                ),
                              ],
                            ),
                            if (connection.status ==
                                BluetoothConnectionStatus.failed) ...[
                              const SizedBox(height: 8),
                              Tooltip(
                                message: connection.lastError ?? '',
                                child: Text(
                                  friendlyBluetoothError(connection.lastError),
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ],
                        const SizedBox(height: 32),
                        SizedBox(
                          width: 105,
                          height: 105,
                          child: ElevatedButton(
                            onPressed: connected ? _goToMenu : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(4),
                              backgroundColor: connected
                                  ? Colors.deepPurple.shade200
                                  : null,
                              foregroundColor: connected
                                  ? Colors.deepPurple.shade900
                                  : null,
                              elevation: connected ? 6 : 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            child: const Text(
                              'Menú',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FloatingActionButton(
                      heroTag: 'splashCredits',
                      onPressed: _goToCredits,
                      tooltip: 'Crèdits',
                      child: const Icon(Icons.info_outline),
                    ),
                    Expanded(child: Center(child: _buildCredits())),
                    FloatingActionButton.extended(
                      heroTag: 'splashExit',
                      onPressed: _exit,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sortir'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
