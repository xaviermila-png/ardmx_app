import 'package:flutter/material.dart';
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
    final selected = await showDialog<BluetoothDevice>(
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
      body: Column(
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
                      onPressed: () =>
                          ref.read(protocolProvider).writeV(16, 20),
                      child: const Text('Enviar V16=20'),
                    ),
                    ElevatedButton(
                      onPressed: () => ref.read(protocolProvider).requestV(14),
                      child: const Text('Demanar V14'),
                    ),
                    ElevatedButton(
                      // No cal connexió: escriure/demanar sense connexió ja
                      // no fa res (VirtuinoProtocol.output no-op silenciós),
                      // així que navegar és segur per ensenyar les pantalles.
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.mainMenu),
                      child: const Text('Menú (mode demo)'),
                    ),
                  ],
                ),
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
    );
  }
}
