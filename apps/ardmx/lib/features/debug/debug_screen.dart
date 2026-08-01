import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol/virtuino_update.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';

/// Temporary screen used only to validate the BLE + protocol stack against
/// real hardware (ARDMX One / ARDMX4 EVO) before the production screens were
/// built. Shows raw incoming frames and offers manual write/request buttons.
/// Not part of the final navigation flow — reached via long-press on the
/// Splash logo.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  final List<String> _log = [];
  final _rawIndexController = TextEditingController();
  final _rawValueController = TextEditingController();

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
    _rawIndexController.dispose();
    _rawValueController.dispose();
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

  Future<void> _pickAndConnect() async {
    final service = ref.read(bluetoothConnectionServiceProvider.notifier);
    var devices = const <DiscoveredDevice>[];
    final subscription = service.bleScanResults.listen(
      (found) => devices = found,
    );
    unawaited(service.startBleScan());
    if (!mounted) return;
    final selected = await showDialog<DiscoveredDevice>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          subscription.onData((found) => setDialogState(() => devices = found));
          return SimpleDialog(
            title: const Text('Escanejant BLE...'),
            children: [
              if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Cercant dispositius…'),
                ),
              for (final device in devices)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(device),
                  child: Text(device.name ?? device.address),
                ),
            ],
          );
        },
      ),
    );
    await subscription.cancel();
    await service.stopBleScan();
    if (selected == null) return;
    await service.connect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(bluetoothConnectionServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Depuració BLE / Protocol')),
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
