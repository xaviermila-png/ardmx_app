import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bluetooth_permissions.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';

/// Temporary screen used only to validate the Bluetooth + protocol stack
/// against the real Arduino Mega before any of the 7 production screens are
/// built. Shows raw incoming frames and offers manual write/request
/// buttons. Not part of the final navigation flow.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  final List<String> _log = [];
  final _nameSuffixController = TextEditingController();
  final _rawIndexController = TextEditingController();
  final _rawValueController = TextEditingController();
  StreamSubscription<BluetoothDevice>? _scanSubscription;
  Timer? _scanTimeout;

  void _appendLog(String line) {
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(protocolProvider, (previous, protocol) {
      protocol.updates.listen((VirtuinoUpdate update) {
        _appendLog(update.toString());
      });
    }, fireImmediately: true);
    ref.listenManual(bluetoothConnectionServiceProvider, (previous, next) {
      _appendLog(
        'connection: ${next.status.name}'
        '${next.lastError != null ? ' — ${next.lastError}' : ''}',
      );
    });
  }

  @override
  void dispose() {
    _nameSuffixController.dispose();
    _rawIndexController.dispose();
    _rawValueController.dispose();
    _scanSubscription?.cancel();
    _scanTimeout?.cancel();
    super.dispose();
  }

  int? get _rawIndex => int.tryParse(_rawIndexController.text.trim());

  void _rawWriteNumber() {
    final index = _rawIndex;
    final value = double.tryParse(_rawValueController.text.trim());
    if (index == null || value == null) {
      _appendLog('Índex o valor numèric invàlid');
      return;
    }
    ref.read(protocolProvider).writeV(index, value);
    _appendLog('Enviat V$index=$value');
  }

  void _rawWriteText() {
    final index = _rawIndex;
    if (index == null) {
      _appendLog('Índex invàlid');
      return;
    }
    final text = _rawValueController.text;
    ref.read(protocolProvider).writeText(index, text);
    _appendLog('Enviat V$index=$text (text)');
  }

  void _rawRequest() {
    final index = _rawIndex;
    if (index == null) {
      _appendLog('Índex invàlid');
      return;
    }
    ref.read(protocolProvider).requestT(index);
    _appendLog('Demanat V$index=?');
  }

  /// Nudges Android into re-reading the currently/last-connected device's
  /// advertised name via an active discovery scan — see
  /// [BluetoothConnectionService.startScan] for why this is a narrow,
  /// opt-in exception to the app's normal "only bonded devices, never
  /// scan" rule, and why it isn't guaranteed to work on every phone.
  void _refreshDeviceName() {
    final address = ref.read(bluetoothConnectionServiceProvider).deviceAddress;
    if (address == null) {
      _appendLog(
        'Cap dispositiu conegut per refrescar (connecta-t\'hi primer)',
      );
      return;
    }
    final service = ref.read(bluetoothConnectionServiceProvider.notifier);
    _appendLog('Escanejant per refrescar el nom de $address...');

    _scanSubscription?.cancel();
    _scanSubscription = service.scanResults.listen((device) {
      if (device.address == address) {
        _appendLog('Trobat: ${device.name ?? '(sense nom)'} ($address)');
      }
    });

    service.startScan();
    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 8), () {
      service.stopScan();
      _scanSubscription?.cancel();
      _appendLog('Escaneig aturat.');
    });
  }

  /// ARDMX One only: the device always keeps its `ARDMXOne_` prefix — this
  /// only ever sends the numeric suffix (V63), never the full name, so a bug
  /// here can't produce a name the firmware wouldn't recognize as its own.
  void _renameArdmxOne() {
    final digits = _nameSuffixController.text.trim();
    if (digits.isEmpty) return;
    ref.read(protocolProvider).writeText(63, digits);
    _appendLog('Enviat nou nom: ARDMXOne_$digits (l\'ESP32 es reiniciarà)');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nom enviat'),
        content: Text(
          "L'ESP32 desarà el nom nou (ARDMXOne_$digits) i es reiniciarà. "
          'Un cop reiniciat, oblida aquest dispositiu i torna\'l a '
          "aparellar des dels ajustos de Bluetooth d'Android per veure'l "
          "amb el nom nou. L'app es tancarà ara.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              SystemNavigator.pop();
            },
            child: const Text('D\'acord'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndConnect() async {
    final granted = await BluetoothPermissions.ensureGranted();
    if (!granted) {
      _appendLog('Permís BLUETOOTH_CONNECT denegat');
      return;
    }
    final devices = await ref
        .read(bluetoothConnectionServiceProvider.notifier)
        .pairedDevices();
    if (!mounted) return;
    if (devices.isEmpty) {
      _appendLog('Cap dispositiu emparellat trobat');
      return;
    }
    final selected = await showDialog<DiscoveredDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tria un dispositiu emparellat'),
        children: [
          for (final device in devices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(device),
              child: Text(device.name ?? '(sense nom)'),
            ),
        ],
      ),
    );
    if (selected == null) return;
    await ref
        .read(bluetoothConnectionServiceProvider.notifier)
        .connect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(bluetoothConnectionServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Depuració Bluetooth / Protocol')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estat: ${connectionState.status.name}'),
                  if (connectionState.deviceName != null)
                    Text(
                      'Dispositiu: ${connectionState.deviceName} (${connectionState.deviceAddress})',
                    ),
                  if (connectionState.lastError != null)
                    Text('Últim error: ${connectionState.lastError}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _pickAndConnect,
                        child: const Text('Connectar...'),
                      ),
                      ElevatedButton(
                        onPressed: () => ref
                            .read(bluetoothConnectionServiceProvider.notifier)
                            .disconnect(),
                        child: const Text('Desconnectar'),
                      ),
                      ElevatedButton(
                        onPressed: _refreshDeviceName,
                        child: const Text('Refrescar nom (escaneig)'),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            ref.read(protocolProvider).writeV(16, 20),
                        child: const Text('Enviar V16=20'),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            ref.read(protocolProvider).requestV(14),
                        child: const Text('Demanar V14'),
                      ),
                      ElevatedButton(
                        // No cal connexió: escriure/demanar sense connexió ja
                        // no fa res (VirtuinoProtocol.output no-op silenciós),
                        // així que navegar és segur per ensenyar les pantalles.
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.mainMenu),
                        child: const Text('ARDMX4 (mode demo)'),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.ardmxOne),
                        child: const Text('ARDMX One (mode demo)'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pushNamed(AppRoutes.ardmx4EvoMainMenu),
                        child: const Text('ARDMX4 EVO (mode demo)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Comanda V lliure (per provar índexs sense pantalla pròpia)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: _rawIndexController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Índex',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: _rawValueController,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Valor / text',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _rawWriteNumber,
                        child: const Text('Escriu V (num)'),
                      ),
                      ElevatedButton(
                        onPressed: _rawWriteText,
                        child: const Text('Escriu T (text)'),
                      ),
                      ElevatedButton(
                        onPressed: _rawRequest,
                        child: const Text('Demana'),
                      ),
                    ],
                  ),
                  if ((connectionState.deviceName ?? '').startsWith(
                    'ARDMXOne',
                  )) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Canviar nom Bluetooth (ARDMX One) — '
                      'només el número, màxim 3 xifres',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        const Text('ARDMXOne_'),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: _nameSuffixController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _renameArdmxOne,
                          child: const Text('Canviar nom'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _log.length,
                itemBuilder: (context, index) => Text(
                  _log[index],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
