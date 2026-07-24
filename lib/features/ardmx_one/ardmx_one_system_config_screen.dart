import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'config_json.dart';

/// ARDMX One's "Configuració del sistema" screen — one level below the
/// normal "Paràmetres" screen (reached via its own button, not the back
/// arrow), on purpose: both fields here require a real recovery step from
/// the user (re-pairing after a Bluetooth rename, losing the current scene
/// after a factory reset), so they shouldn't be as casually reachable as
/// the day-to-day channel controls.
class ArdmxOneSystemConfigScreen extends StatelessWidget {
  const ArdmxOneSystemConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Configuració del sistema',
      automaticallyImplyLeading: false,
      body: Column(
        children: [
          Expanded(
            // Without this, the keyboard opening while editing the
            // Bluetooth name shrinks the available height enough to
            // overflow the two sections below — same fix already applied
            // to ARDMX4's Parameters screen for the same reason.
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: 'Nom Bluetooth',
                    child: const _BluetoothNameSection(),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Configuració',
                    child: const _ExportImportSection(),
                  ),
                  const SizedBox(height: 8),
                  const _ResetSection(),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                FloatingActionButton(
                  heroTag: 'ardmxOneSystemConfigBack',
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Tornar a paràmetres',
                  child: const Icon(Icons.arrow_back),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the user rename the device's Bluetooth name (V63) — up to 12
/// characters, letters and digits only (see `sanitizeName()` in
/// `firmware/ardmx_one/src/main.cpp`, which enforces the same limit).
/// Renaming restarts the ESP32, so Android's paired-device name won't
/// update on its own — the confirmation dialog tells the user to
/// forget/re-pair it, then exits the app.
class _BluetoothNameSection extends ConsumerStatefulWidget {
  const _BluetoothNameSection();

  @override
  ConsumerState<_BluetoothNameSection> createState() =>
      _BluetoothNameSectionState();
}

class _BluetoothNameSectionState extends ConsumerState<_BluetoothNameSection> {
  static const _btNameVIndex = 63;
  static const _maxLength = 12;

  final _controller = TextEditingController();
  StreamSubscription<VirtuinoUpdate>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      if (update is VirtuinoTUpdate && update.index == _btNameVIndex) {
        _controller.text = update.text;
      }
    });
    ref.read(protocolProvider).requestT(_btNameVIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _rename() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    ref.read(protocolProvider).writeText(_btNameVIndex, name);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nom enviat'),
        content: Text(
          "L'ESP32 desarà el nom nou ($name) i es reiniciarà. "
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Fins a 12 caràcters, només lletres i xifres.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          textAlign: TextAlign.center,
          maxLength: _maxLength,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
          ],
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 4),
        ElevatedButton(onPressed: _rename, child: const Text('Canviar nom')),
      ],
    );
  }
}

/// Exports the whole device configuration (pessebre name, description,
/// active channel count, and every active channel's name+value) as a JSON
/// file shared via Android's system share sheet, or imports one back.
///
/// Channel data has no bulk read/write on the wire protocol — V01-03/
/// V04-06/V65-67 only ever expose the 3 currently-selected slider channels.
/// Both directions go through V70 instead (query/assign a single channel by
/// its explicit number, one round trip per channel — see
/// `firmware/ardmx_one/src/main.cpp`), sent sequentially and awaited one at
/// a time: the wire protocol has no request/response correlation (any
/// reply could be mistaken for a different in-flight request), and firing
/// hundreds of writes at once risked reintroducing the DMX-vs-NVS timing
/// crash that was just fixed on the firmware side.
class _ExportImportSection extends ConsumerStatefulWidget {
  const _ExportImportSection();

  @override
  ConsumerState<_ExportImportSection> createState() =>
      _ExportImportSectionState();
}

class _ExportImportSectionState extends ConsumerState<_ExportImportSection> {
  static const _pessebreVIndex = 68;
  static const _descripcioVIndex = 69;
  static const _numeroCanalsVIndex = 8;
  static const _channelBulkVIndex = 70;
  static const _roundTripTimeout = Duration(milliseconds: 800);

  bool _running = false;
  String? _statusText;
  int _progress = 0;
  int _progressTotal = 1;

  Future<String?> _readText(int index) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> sub;
    sub = protocol.updates.listen((update) {
      if (update is VirtuinoTUpdate &&
          update.index == index &&
          !completer.isCompleted) {
        completer.complete(update.text);
      }
    });
    protocol.requestT(index);
    final result = await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    await sub.cancel();
    return result;
  }

  Future<int?> _readValue(int index) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<double?>();
    late final StreamSubscription<VirtuinoUpdate> sub;
    sub = protocol.updates.listen((update) {
      if (update is VirtuinoVUpdate &&
          update.index == index &&
          !completer.isCompleted) {
        completer.complete(update.value);
      }
    });
    protocol.requestV(index);
    final result = await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    await sub.cancel();
    return result?.round();
  }

  /// Sends a V70 payload (either `"N"` to query channel N, or
  /// `"N|value|name"` to assign it) and awaits the matching `"value|name"`
  /// reply, which the firmware sends for both cases.
  Future<(int value, String name)?> _channelRoundTrip(String payload) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> sub;
    sub = protocol.updates.listen((update) {
      if (update is VirtuinoTUpdate &&
          update.index == _channelBulkVIndex &&
          !completer.isCompleted) {
        completer.complete(update.text);
      }
    });
    protocol.writeText(_channelBulkVIndex, payload);
    final reply = await completer.future.timeout(
      _roundTripTimeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    if (reply == null) return null;
    final pipe = reply.indexOf('|');
    if (pipe == -1) return null;
    final value = int.tryParse(reply.substring(0, pipe)) ?? 0;
    return (value, reply.substring(pipe + 1));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    setState(() {
      _running = true;
      _statusText = 'Llegint configuració…';
      _progress = 0;
      _progressTotal = 1;
    });
    try {
      final pessebre = await _readText(_pessebreVIndex) ?? '';
      final descripcio = await _readText(_descripcioVIndex) ?? '';
      final numeroCanals = await _readValue(_numeroCanalsVIndex);
      if (numeroCanals == null || numeroCanals <= 0) {
        _showMessage('No s\'ha pogut llegir el nombre de canals actius.');
        return;
      }

      final canals = <ChannelConfigEntry>[];
      setState(() {
        _progressTotal = numeroCanals;
        _statusText = 'Llegint canals…';
      });
      for (var channel = 1; channel <= numeroCanals; channel++) {
        final result = await _channelRoundTrip('$channel');
        canals.add(
          ChannelConfigEntry(
            number: channel,
            name: result?.$2 ?? '',
            value: result?.$1 ?? 0,
          ),
        );
        if (!mounted) return;
        setState(() => _progress = channel);
      }

      final config = ArdmxOneConfigData(
        pessebre: pessebre,
        descripcio: descripcio,
        numeroCanals: numeroCanals,
        canals: canals,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ardmx_one_config.json');
      await file.writeAsString(config.toPrettyJson());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Configuració ARDMX One',
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _confirmImport(ArdmxOneConfigData config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar configuració?'),
        content: Text(
          'Es sobreescriuran el nom del pessebre, la descripció, el nombre '
          'de canals actius i els noms/valors de ${config.canals.length} '
          'canals amb el contingut del fitxer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel·lar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    final ArdmxOneConfigData config;
    try {
      config = ArdmxOneConfigData.fromPrettyJson(await File(path).readAsString());
    } catch (_) {
      _showMessage('El fitxer no és un JSON vàlid de configuració.');
      return;
    }
    if (config.numeroCanals <= 0 || config.canals.isEmpty) {
      _showMessage('El fitxer no conté cap canal.');
      return;
    }

    if (!await _confirmImport(config)) return;

    setState(() {
      _running = true;
      _statusText = 'Aplicant configuració…';
      _progress = 0;
      _progressTotal = config.canals.length;
    });
    try {
      final protocol = ref.read(protocolProvider);
      protocol.writeV(_numeroCanalsVIndex, config.numeroCanals);
      protocol.writeText(_pessebreVIndex, config.pessebre);
      protocol.writeText(_descripcioVIndex, config.descripcio);

      for (final entry in config.canals) {
        await _channelRoundTrip('${entry.number}|${entry.value}|${entry.name}');
        if (!mounted) return;
        setState(() => _progress++);
      }
      _showMessage('Configuració importada.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_running) {
      return Column(
        children: [
          Text(_statusText ?? '', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progressTotal > 0 ? _progress / _progressTotal : null,
          ),
          const SizedBox(height: 4),
          Text(
            '$_progress / $_progressTotal',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
    }

    return Column(
      children: [
        const Text(
          'Exporta tota la configuració (pessebre, descripció, canals) a un '
          'fitxer JSON, o importa\'n un per restaurar-la.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.upload_file),
              label: const Text('Exportar'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.download),
              label: const Text('Importar'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Factory-reset section: same armed/confirm two-step pattern as ARDMX4's
/// Parameters screen (V41 arm, V42 confirm), reusing the exact same
/// `appStateProvider` intent methods since the wire indices are identical —
/// only the firmware's idea of "what a reset resets" differs, and that's
/// entirely on the device side. Here it clears the current scene (all
/// channel values) and resets the active-channels count back to its
/// default; the Bluetooth name is left untouched. Owns its own poll timer
/// for V41/V42 (this screen has nothing else to poll), same "nothing is
/// pushed unsolicited" pattern as every other screen.
class _ResetSection extends ConsumerStatefulWidget {
  const _ResetSection();

  @override
  ConsumerState<_ResetSection> createState() => _ResetSectionState();
}

class _ResetSectionState extends ConsumerState<_ResetSection> {
  static const _pollInterval = Duration(milliseconds: 400);

  Timer? _pollTimer;
  bool _resetPending = false;

  @override
  void initState() {
    super.initState();
    // Deferred a frame: _poll() calls ModalRoute.of(context), not
    // resolvable synchronously inside initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    // Only the topmost route should poll — see Scene/Channels for why two
    // screens polling at once can corrupt the wire protocol.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.read(protocolProvider).requestAll([
      VIndex.resetConfirm1,
      VIndex.resetConfirm2,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final resetArmed = ref.watch(appStateProvider.select((s) => s.resetArmed));

    // Mirrors ARDMX4's Parameters screen: the firmware sets V41/V42 back to
    // 0 itself once the reset has actually run — that's the real completion
    // signal, not the instant the write is sent.
    ref.listen(
      appStateProvider.select((s) => (s.resetArmed, s.resetConfirm2)),
      (previous, next) {
        if (_resetPending && !next.$1 && next.$2 == 0) {
          setState(() => _resetPending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Escena i canals reinicialitzats')),
          );
        }
      },
    );

    return _Section(
      title: 'Reset de fàbrica',
      child: Column(
        children: [
          const Text(
            "Esborra l'escena actual (tots els canals a 0) i torna el "
            'nombre de canals actius al valor de fàbrica. El nom Bluetooth '
            'no es toca.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SelectableButton(
                label: resetArmed ? 'ON' : 'OFF',
                selected: resetArmed,
                onTap: _resetPending
                    ? () {}
                    : () => ref
                          .read(appStateProvider.notifier)
                          .setResetArmed(!resetArmed),
              ),
              if (resetArmed || _resetPending) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _resetPending
                      ? null
                      : () {
                          setState(() => _resetPending = true);
                          ref.read(appStateProvider.notifier).confirmReset();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _resetPending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectableButton extends StatelessWidget {
  const _SelectableButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? Colors.red.shade200 : null,
          foregroundColor: selected ? Colors.red.shade900 : null,
          elevation: selected ? 4 : 1,
          padding: const EdgeInsets.all(4),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
