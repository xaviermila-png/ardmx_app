import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bluetooth_connection_state.dart';
import '../../core/bluetooth/bluetooth_error_messages.dart';
import '../../core/bluetooth/bluetooth_permissions.dart';
import '../../core/constants/app_version.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/connection_badge.dart';

/// Bluetooth connect/disconnect here is fully explicit — no auto-connect on
/// launch, no automatic reconnect on drop. This is deliberate (carried over
/// from diagnosing a real HC-05 connectivity issue on the sibling Classic
/// app): auto-retry logic made failures harder to reproduce (it was found to
/// hammer the module with rapid reconnect attempts). The user scans and taps
/// Connect/Disconnect themselves.
///
/// BLE-only — this app never bonds/pairs devices via Android settings, it
/// scans fresh every time (see [BluetoothConnectionService.bleScanResults]).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _checkingPermission = true;
  bool _permissionDenied = false;
  String? _errorMessage;

  bool _bleScanning = false;
  List<DiscoveredDevice> _bleDevices = const [];
  StreamSubscription<List<DiscoveredDevice>>? _bleScanSubscription;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _bleScanSubscription?.cancel();
    super.dispose();
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
        });
        return;
      }
      setState(() => _checkingPermission = false);
    } catch (error) {
      // Never leave the UI stuck on the loading spinner — surface the
      // failure with a way to retry instead. Observed in practice: the
      // permission_handler platform channel can throw if a request races
      // with another one during startup.
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _checkingPermission = false;
      });
    }
  }

  Future<void> _connect(DiscoveredDevice device) async {
    await ref.read(bluetoothConnectionServiceProvider.notifier).connect(device);
  }

  Future<void> _disconnect() async {
    await ref.read(bluetoothConnectionServiceProvider.notifier).disconnect();
  }

  Future<void> _startBleScan() async {
    final service = ref.read(bluetoothConnectionServiceProvider.notifier);
    setState(() {
      _bleScanning = true;
      _bleDevices = const [];
    });
    _bleScanSubscription?.cancel();
    _bleScanSubscription = service.bleScanResults.listen((devices) {
      if (!mounted) return;
      setState(() => _bleDevices = devices);
    });
    try {
      await service.startBleScan();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Error escanejant BLE: $error');
    }
    // startBleScan()'s own timeout stops the underlying scan, but the app
    // still needs to flip the UI back out of "scanning" state itself.
    if (!mounted) return;
    setState(() => _bleScanning = false);
  }

  Future<void> _exit() async {
    final status = ref.read(bluetoothConnectionServiceProvider).status;
    if (status == BluetoothConnectionStatus.connected) {
      await ref.read(bluetoothConnectionServiceProvider.notifier).disconnect();
    }
    SystemNavigator.pop();
  }

  void _goToArdmxOne() =>
      Navigator.of(context).pushReplacementNamed(AppRoutes.ardmxOne);

  void _goToArdmx4Evo() =>
      Navigator.of(context).pushReplacementNamed(AppRoutes.ardmx4EvoMainMenu);

  /// Where the "Menú" button / auto-redirect on connect should go — asks
  /// [DeviceIdentificationService] which product this is (V64 handshake,
  /// cached per-MAC after the first time — see that class) rather than
  /// looking at the Bluetooth name directly. This app is BLE-only, so an
  /// ARDMX4 (Mega, Bluetooth Classic) can never actually be the connected
  /// device here — [DeviceType.ardmx4] is kept in the shared enum but is
  /// unreachable in practice, treated the same as [DeviceType.unknown]:
  /// nothing to navigate to, so the user just stays on Splash (both for the
  /// auto-redirect and for a manual "Menú" tap — [isManualTap] no longer
  /// changes the outcome, but is kept for symmetry with the auto-redirect
  /// call site).
  Future<void> _goToDeviceHome({required bool isManualTap}) async {
    final type = await ref
        .read(deviceIdentificationServiceProvider.notifier)
        .identify();
    if (!mounted) return;
    switch (type) {
      case DeviceType.ardmxOne:
        _goToArdmxOne();
      case DeviceType.ardmx4Evo:
        _goToArdmx4Evo();
      case DeviceType.ardmx4:
      case DeviceType.unknown:
        break;
    }
  }

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

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
  );

  Widget _buildBleSection({
    required bool connected,
    required bool connecting,
  }) {
    final canScan = !connected && !connecting && !_bleScanning;
    return Column(
      children: [
        _sectionTitle('BLE (ARDMX One / EVO)'),
        const SizedBox(height: 6),
        SizedBox(
          width: 260,
          child: ElevatedButton.icon(
            onPressed: canScan ? _startBleScan : null,
            icon: _bleScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching),
            label: Text(_bleScanning ? 'Escanejant…' : 'Escanejar'),
          ),
        ),
        const SizedBox(height: 10),
        if (_bleDevices.isEmpty)
          Text(
            _bleScanning
                ? 'Cercant dispositius…'
                : 'Cap dispositiu trobat. Prem "Escanejar".',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          )
        else
          Container(
            width: 260,
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.deepPurple.shade200, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (final device in _bleDevices)
                  ListTile(
                    dense: true,
                    title: Text(
                      device.name ?? device.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: (connected || connecting)
                        ? null
                        : () => _connect(device),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(bluetoothConnectionServiceProvider);
    final connected = connection.status == BluetoothConnectionStatus.connected;
    final connecting =
        connection.status == BluetoothConnectionStatus.connecting;

    // Skip the manual "Menú" tap and go straight in once connected — see
    // _goToDeviceHome for how ARDMX4 vs ARDMX One/EVO is told apart.
    //
    // Splash stays mounted (this listener keeps firing) even while another
    // route — e.g. the Debug screen, reached via long-press on the logo —
    // is pushed on top of it, since Flutter only disposes a screen on pop,
    // not while merely covered. Without the isCurrent guard, connecting
    // from the Debug screen (its own "Connectar..." button) would still
    // trigger this auto-redirect and yank the user away from Debug into
    // ArdmxOneScreen/MainMenu, which defeats the point of being in Debug.
    ref.listen(bluetoothConnectionServiceProvider, (previous, next) {
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final wasConnected =
          previous?.status == BluetoothConnectionStatus.connected;
      final isConnected = next.status == BluetoothConnectionStatus.connected;
      if (!wasConnected && isConnected) {
        // Deferred a frame rather than called synchronously here: this
        // listener callback can fire mid-frame, and calling
        // pushReplacementNamed synchronously in that window was observed
        // (on the sibling ARDMX Classic app, same pattern) to occasionally
        // throw a transient "GlobalKey used multiple times ([...] ink
        // renderer)" error — Splash's and the destination screen's
        // Scaffolds both being Material momentarily overlapping
        // mid-transition. Harmless (the frame after self-heals and
        // navigation completes regardless), but avoidable by not starting
        // the route replacement until the current frame is done, same
        // reasoning as ScreenMirrorObserver's own addPostFrameCallback use.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _goToDeviceHome(isManualTap: false),
        );
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
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
                            'assets/imatges/ARDMX_Logo.png',
                            width: 140,
                            height: 140,
                          ),
                        ),
                        const SizedBox(height: 20),
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
                            "Hi ha hagut un error:\n$_errorMessage",
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
                          _buildBleSection(
                            connected: connected,
                            connecting: connecting,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: 260,
                            child: OutlinedButton.icon(
                              onPressed: connected ? _disconnect : null,
                              style: OutlinedButton.styleFrom(
                                // Always a concrete BorderSide (never null) —
                                // toggling it between null and non-null was
                                // observed (on the sibling ARDMX Classic app,
                                // same pattern) to trip a Flutter/Material3
                                // framework bug ("Failed to interpolate
                                // TextStyles with different inherit values"),
                                // showing a transient red error screen.
                                // Transparent stands in for "no border".
                                side: BorderSide(
                                  color: connected
                                      ? Colors.deepPurple
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              icon: const Icon(Icons.bluetooth_disabled),
                              label: const Text(
                                'Desconnectar',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
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
                        const SizedBox(height: 32),
                        SizedBox(
                          width: 105,
                          height: 105,
                          child: ElevatedButton(
                            onPressed: connected
                                ? () => _goToDeviceHome(isManualTap: true)
                                : null,
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
                            ),
                            // fontSize/fontWeight applied directly to the
                            // Text rather than via ButtonStyle.textStyle: a
                            // custom raw TextStyle there, combined with
                            // onPressed toggling null/non-null, was
                            // observed (on the sibling ARDMX Classic app,
                            // same pattern) to trip a Flutter/Material3
                            // framework bug ("Failed to interpolate
                            // TextStyles with different inherit values")
                            // right as `connected` flips true, showing a
                            // transient red error screen.
                            child: const Text(
                              'Menú',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
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
