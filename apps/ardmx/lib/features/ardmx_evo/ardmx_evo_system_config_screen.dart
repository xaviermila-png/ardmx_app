import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/device_identification_service.dart';
import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'config_json.dart';

/// ARDMX EVO's "Configuració del sistema" screen — one level below
/// "Paràmetres" (reached via its own button, not the back arrow), same
/// reasoning as ARDMX4's and ARDMX One's own split: everything here
/// (Bluetooth rename, factory reset, full-config export/import) requires a
/// real recovery step or is destructive, so it shouldn't be as casually
/// reachable as the day-to-day controls on Paràmetres.
class ArdmxEvoSystemConfigScreen extends ConsumerWidget {
  const ArdmxEvoSystemConfigScreen({super.key});

  // Same disarm-on-leave fix as ARDMX One's system config screen: if the
  // user unlocks the reset (ON) and leaves without confirming, disarm it
  // first — otherwise it stays "ON" the next time this screen opens.
  // Centralized here (not in a widget's dispose()) so it covers both the
  // back-arrow FAB and the system back gesture (see PopScope below).
  void _attemptBack(WidgetRef ref, BuildContext context) {
    if (ref.read(appStateProvider).resetArmed) {
      ref.read(appStateProvider.notifier).setResetArmed(false);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _attemptBack(ref, context);
      },
      child: AppScaffold(
        title: 'Configuració',
        onBack: () => _attemptBack(ref, context),
        body: SingleChildScrollView(
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
                title: 'PIN de connexió',
                child: const _PinSection(),
              ),
              const SizedBox(height: 8),
              _Section(
                title: 'Exportació/Importació de la configuració',
                child: const _ExportImportSection(),
              ),
              const SizedBox(height: 8),
              const _ResetSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sets or clears the device's connection PIN (V74 to set/read, V75 to
/// clear — see [DeviceIdentificationService], which also handles V64's
/// "pin" flag and V73's verify-on-connect). Reading V74 back is only
/// reachable once already authenticated (or when no PIN is set), same
/// gating as any other index — see main.cpp's `gated` check — so showing
/// it here doesn't expose anything the app hasn't already proven it knows.
class _PinSection extends ConsumerStatefulWidget {
  const _PinSection();

  @override
  ConsumerState<_PinSection> createState() => _PinSectionState();
}

class _PinSectionState extends ConsumerState<_PinSection> {
  // Índex de lectura del PIN actual — deliberadament diferent del 74 (que
  // és l'índex d'escriptura/ACK de setPin, vegeu DeviceIdentificationService):
  // si es fes servir el mateix, l'ACK "OK"/"ERROR" d'una desada arribaria
  // per aquest mateix listener i es mostraria com si fos el PIN.
  static const _pinReadVIndex = 76;

  final _controller = TextEditingController();
  StreamSubscription<VirtuinoUpdate>? _subscription;
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      if (update is VirtuinoTUpdate && update.index == _pinReadVIndex) {
        _controller.text = update.text;
      }
    });
    ref.read(protocolProvider).requestT(_pinReadVIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _hasPin =>
      ref.read(deviceIdentificationServiceProvider.notifier).requiresPin;

  Future<void> _setPin() async {
    final pin = _controller.text;
    if (pin.length != 4) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(deviceIdentificationServiceProvider.notifier)
        .setPin(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'PIN activat.' : "No s'ha pogut desar el PIN."),
      ),
    );
  }

  Future<void> _removePin() async {
    setState(() => _busy = true);
    final ok = await ref
        .read(deviceIdentificationServiceProvider.notifier)
        .resetPin();
    if (!mounted) return;
    if (ok) _controller.clear();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'PIN desactivat.' : "No s'ha pogut treure el PIN."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _hasPin
              ? 'Activat: cal aquest PIN per connectar-s\'hi.'
              : "Desactivat: qualsevol es pot connectar-hi sense PIN.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: _obscure,
          enabled: !_busy,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: _busy ? null : _setPin,
              child: Text(_hasPin ? 'Canviar PIN' : 'Activar PIN'),
            ),
            if (_hasPin) ...[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy ? null : _removePin,
                child: const Text('Treure PIN'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Lets the user rename the device's Bluetooth name (V63, same wire index
/// as ARDMX One) — freely editable per the project spec (no reserved
/// prefix required), up to 15 characters. Renaming restarts the ESP32, so
/// Android's paired-device name won't update on its own.
class _BluetoothNameSection extends ConsumerStatefulWidget {
  const _BluetoothNameSection();

  @override
  ConsumerState<_BluetoothNameSection> createState() =>
      _BluetoothNameSectionState();
}

class _BluetoothNameSectionState extends ConsumerState<_BluetoothNameSection> {
  static const _btNameVIndex = 63;
  static const _maxLength = 15;

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
          'Fins a 15 caràcters: lletres, xifres i "_".',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          textAlign: TextAlign.center,
          maxLength: _maxLength,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
          ],
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 4),
        FilledButton(onPressed: _rename, child: const Text('Canviar nom')),
      ],
    );
  }
}

/// Factory-reset section: same armed/confirm two-step pattern (V41 arm, V42
/// confirm) as ARDMX4's and ARDMX One's own reset sections, reusing the
/// same `appStateProvider` intent methods since the wire indices are
/// identical (the EVO firmware ports `performFactoryReset()` from the
/// Mega). Owns its own poll timer for V41/V42.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.read(protocolProvider).requestAll([
      VIndex.resetConfirm1,
      VIndex.resetConfirm2,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final resetArmed = ref.watch(appStateProvider.select((s) => s.resetArmed));

    ref.listen(
      appStateProvider.select((s) => (s.resetArmed, s.resetConfirm2)),
      (previous, next) {
        if (_resetPending && !next.$1 && next.$2 == 0) {
          setState(() => _resetPending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Configuració reinicialitzada')),
          );
          // Mateix problema que a ARDMX4/ARDMX One: sense re-demanar-ho
          // explícitament, qualsevol pantalla oberta per sota (Escenes,
          // Paràmetres) es queda amb els valors antics fins a reconnectar.
          final protocol = ref.read(protocolProvider);
          protocol.requestV(VIndex.activeScenesCount);
          protocol.requestV(VIndex.songNumber);
          protocol.requestV(VIndex.activeChannelsCount);
          protocol.requestV(VIndex.activeScene);
          protocol.requestV(VIndex.channel1Value);
          protocol.requestV(VIndex.channel2Value);
          protocol.requestV(VIndex.channel3Value);
          protocol.requestT(65);
          protocol.requestT(66);
          protocol.requestT(67);
          protocol.requestT(68);
          protocol.requestT(69);
        }
      },
    );

    return _Section(
      title: 'Reset de fàbrica',
      child: Column(
        children: [
          const Text(
            'Esborra tota la configuració (escenes, canals, noms, pessebre '
            'i descripció) i la torna als valors de fàbrica. El nom '
            'Bluetooth no es toca.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SelectableButton(
                // Action-oriented label (what tapping does), not a state
                // display: "ON" invites arming it, and once armed (Reset
                // button showing) it becomes "OFF" to invite disarming it.
                label: resetArmed ? 'OFF' : 'ON',
                selected: resetArmed,
                onTap: _resetPending
                    ? () {}
                    : () => ref
                          .read(appStateProvider.notifier)
                          .setResetArmed(!resetArmed),
              ),
              if (resetArmed || _resetPending) ...[
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _resetPending
                      ? null
                      : () {
                          setState(() => _resetPending = true);
                          ref.read(appStateProvider.notifier).confirmReset();
                        },
                  style: FilledButton.styleFrom(
                    // A destructive action, not a normal selected/active
                    // state — colorScheme.error is MD3's semantic role for
                    // this, not primary.
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _resetPending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onError,
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

/// Exports the whole EVO device configuration (scene count, song, volume,
/// active channel count, the 8 cycle period durations, pessebre name,
/// descripció, and every active channel's 4 per-scene values+modes+name) as
/// a JSON file, or imports one back. Channel data goes through V71 (see
/// `handleChannelBulk()` in the EVO firmware) — unlike the Mega's V63, the
/// EVO's custom parser replies to a write automatically, so each round trip
/// is a single frame (write, then listen — no follow-up read request),
/// mirroring ARDMX One's own V70.
class _ExportImportSection extends ConsumerStatefulWidget {
  const _ExportImportSection();

  @override
  ConsumerState<_ExportImportSection> createState() =>
      _ExportImportSectionState();
}

class _ExportImportSectionState extends ConsumerState<_ExportImportSection> {
  static const _firmwareVersionVIndex = 62;
  static const _pessebreVIndex = 68;
  static const _descripcioVIndex = 69;
  static const _channelBulkVIndex = 71;
  static const _roundTripTimeout = Duration(milliseconds: 800);

  // The Baixades/Downloads document tree on Android's default (primary)
  // storage volume, addressed the way the Storage Access Framework expects
  // for EXTRA_INITIAL_URI — not a filesystem path. Not guaranteed to exist
  // on every OEM skin, but it's the standard convention and file_picker
  // just no-ops (falls back to the system's own last-used location) if it
  // doesn't resolve, so there's nothing to fall back to manually here.
  static const _androidDownloadsUri =
      'content://com.android.externalstorage.documents/document/primary:Download';

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

  Future<double?> _readValue(int index) async {
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
    return result;
  }

  Future<bool> _writeVerified(int index, num value) async {
    final protocol = ref.read(protocolProvider);
    for (var attempt = 0; attempt < 6; attempt++) {
      protocol.writeV(index, value);
      final readBack = await _readValue(index);
      if (readBack != null && readBack.round() == value.round()) return true;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  /// Sends a V71 payload (`"N"` to query channel N, or
  /// `"N|v1|m1|v2|m2|v3|m3|v4|m4|nom"` to assign it) and awaits the matching
  /// `"v1|m1|v2|m2|v3|m3|v4|m4|nom"` reply — a single frame, since the EVO
  /// firmware's custom parser replies to a write automatically (unlike the
  /// Mega's V63/VirtuinoCM, which only replies to a subsequent read).
  Future<String?> _channelRoundTripOnce(String payload) async {
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
    return reply;
  }

  Future<String?> _channelRoundTrip(String payload) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final reply = await _channelRoundTripOnce(payload);
      if (reply != null) return reply;
    }
    return null;
  }

  (List<int>, List<int>, String)? _parseChannelReply(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 9) return null;
    final valors = <int>[];
    final modes = <int>[];
    for (var i = 0; i < 8; i += 2) {
      valors.add(int.tryParse(parts[i]) ?? 0);
      modes.add(int.tryParse(parts[i + 1]) ?? 0);
    }
    final name = parts.sublist(8).join('|');
    return (valors, modes, name);
  }

  Future<bool> _assignChannelVerified(ArdmxEvoChannelConfigEntry entry) async {
    final fields = <String>[];
    for (var i = 0; i < 4; i++) {
      fields.add('${entry.valors[i]}');
      fields.add('${entry.modes[i]}');
    }
    final payload = '${entry.number}|${fields.join('|')}|${entry.name}';

    for (var attempt = 0; attempt < 6; attempt++) {
      final parsed = _parseChannelReply(await _channelRoundTripOnce(payload));
      if (parsed != null &&
          _listEquals(parsed.$1, entry.valors) &&
          _listEquals(parsed.$2, entry.modes) &&
          parsed.$3 == entry.name) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
      final firmwareVersio = await _readText(_firmwareVersionVIndex) ?? '';
      final pessebre = await _readText(_pessebreVIndex) ?? '';
      final descripcio = await _readText(_descripcioVIndex) ?? '';
      final numeroEscenes = await _readValue(VIndex.activeScenesCount) ?? 0;
      final numeroCanals = await _readValue(VIndex.activeChannelsCount);
      final numeroMusica = await _readValue(VIndex.songNumber) ?? 0;
      final nivellVolum = await _readValue(VIndex.volume) ?? 0;
      if (numeroCanals == null || numeroCanals <= 0) {
        _showMessage('No s\'ha pogut llegir el nombre de canals gestionables.');
        return;
      }

      final periodes = <double>[];
      for (var i = 0; i < 8; i++) {
        periodes.add(await _readValue(VIndex.periodDuration(i)) ?? 0);
      }

      final canalsCount = numeroCanals.round();
      final canals = <ArdmxEvoChannelConfigEntry>[];
      setState(() {
        _progressTotal = canalsCount;
        _statusText = 'Llegint canals…';
      });
      for (var channel = 1; channel <= canalsCount; channel++) {
        final parsed = _parseChannelReply(await _channelRoundTrip('$channel'));
        canals.add(
          ArdmxEvoChannelConfigEntry(
            number: channel,
            valors: parsed?.$1 ?? const [0, 0, 0, 0],
            modes: parsed?.$2 ?? const [0, 0, 0, 0],
            name: parsed?.$3 ?? '',
          ),
        );
        if (!mounted) return;
        setState(() => _progress = channel);
      }

      final config = ArdmxEvoConfigData(
        numeroEscenes: numeroEscenes.round(),
        numeroCanals: canalsCount,
        numeroMusica: numeroMusica.round(),
        nivellVolum: nivellVolum.round(),
        periodes: periodes,
        pessebre: pessebre,
        descripcio: descripcio,
        canals: canals,
        firmwareVersio: firmwareVersio,
        exportatEl: DateTime.now(),
      );
      final savedPath = await FilePicker.saveFile(
        fileName: _suggestedFileName(pessebre),
        type: FileType.custom,
        allowedExtensions: ['json'],
        // Best-effort only — the Android SAF picker this opens ignores
        // initialDirectory unless it can resolve to a real content:// tree
        // URI (a plain path like getExternalStoragePublicDirectory's won't
        // do), so this is the one document-provider URI that reliably
        // resolves to Baixades/Downloads on stock Android. Once the user
        // saves here once, Android's own "recent location" memory tends to
        // keep both this and _import()'s picker opening there afterwards
        // even where this hint doesn't apply (desktop only, per file_picker
        // docs — irrelevant here, this app is Android-only, kept anyway for
        // parity with _import()'s use of the same constant).
        initialDirectory: _androidDownloadsUri,
        bytes: Uint8List.fromList(utf8.encode(config.toPrettyJson())),
      );
      if (savedPath != null) _showMessage('Configuració desada.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// `"ardmx_evo_<pessebre>.json"` so multiple pessebres' exports don't
  /// collide/overwrite each other by filename alone — falls back to the
  /// bare name when there's no pessebre name set. Strips characters invalid
  /// in a filename on Android/Windows rather than rejecting them, since the
  /// pessebre name itself has no such restriction.
  String _suggestedFileName(String pessebre) {
    final clean = pessebre
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return clean.isEmpty ? 'ardmx_evo.json' : 'ardmx_evo_$clean.json';
  }

  Future<bool> _confirmImport(ArdmxEvoConfigData config) async {
    final exportatEl = config.exportatEl;
    final origen = [
      if (config.firmwareVersio.isNotEmpty) config.firmwareVersio,
      if (exportatEl != null)
        'exportat el ${exportatEl.day.toString().padLeft(2, '0')}/'
            '${exportatEl.month.toString().padLeft(2, '0')}/'
            '${exportatEl.year} '
            '${exportatEl.hour.toString().padLeft(2, '0')}:'
            '${exportatEl.minute.toString().padLeft(2, '0')}',
    ].join(', ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar configuració?'),
        content: Text(
          "Es sobreescriuran el nombre d'escenes, la cançó, el volum, el "
          'nombre de canals, els temps de transició, el pessebre, la '
          'descripció i els valors/modes/noms de ${config.canals.length} '
          'canals amb el contingut del fitxer.'
          '${origen.isNotEmpty ? '\n\nFitxer: $origen' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel·lar'),
          ),
          FilledButton(
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
      // No effect on Android (file_picker only wires initialDirectory
      // through on desktop for pickFiles — see _androidDownloadsUri's own
      // comment on _export()), kept for symmetry/desktop parity. On Android
      // this picker tends to open wherever was last used anyway, which in
      // practice is Baixades/Downloads once _export() has been used once.
      initialDirectory: _androidDownloadsUri,
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    final ArdmxEvoConfigData config;
    try {
      config = ArdmxEvoConfigData.fromPrettyJson(
        await File(path).readAsString(),
      );
    } catch (_) {
      _showMessage('El fitxer no és un JSON vàlid de configuració.');
      return;
    }
    if (config.numeroCanals <= 0 || config.canals.isEmpty) {
      _showMessage('El fitxer no conté cap canal.');
      return;
    }
    if (config.model.isNotEmpty &&
        config.model != ArdmxEvoConfigData.defaultModel) {
      _showMessage(
        'Aquest fitxer és de "${config.model}", no d\'ARDMX EVO. '
        'No s\'ha importat.',
      );
      return;
    }

    if (!await _confirmImport(config)) return;

    const paramStepCount = 14;
    setState(() {
      _running = true;
      _statusText = 'Aplicant configuració…';
      _progress = 0;
      _progressTotal = paramStepCount + config.canals.length;
    });
    try {
      final paramFailures = <String>[];
      Future<void> writeParam(String label, int index, num value) async {
        if (!await _writeVerified(index, value)) paramFailures.add(label);
        if (mounted) setState(() => _progress++);
      }

      await writeParam(
        'nombre d\'escenes',
        VIndex.activeScenesCount,
        config.numeroEscenes,
      );
      await writeParam('cançó', VIndex.songNumber, config.numeroMusica);
      await writeParam('volum', VIndex.volume, config.nivellVolum);
      await writeParam(
        'nombre de canals',
        VIndex.activeChannelsCount,
        config.numeroCanals,
      );
      for (var i = 0; i < 8 && i < config.periodes.length; i++) {
        await writeParam(
          'temps de transició ${i + 1}',
          VIndex.periodDuration(i),
          config.periodes[i],
        );
      }

      final protocol = ref.read(protocolProvider);
      protocol.writeText(_pessebreVIndex, config.pessebre);
      if (mounted) setState(() => _progress++);
      protocol.writeText(_descripcioVIndex, config.descripcio);
      if (mounted) setState(() => _progress++);

      // Marge d'assentament abans del bombardeig de canals — mateix motiu
      // que ARDMX4: si el nombre d'escenes/canals acaba de canviar, el
      // firmware pot trigar a assentar-se abans de respondre amb fiabilitat.
      await Future.delayed(const Duration(seconds: 3));

      final failedChannels = <int>[];
      for (final entry in config.canals) {
        final ok = await _assignChannelVerified(entry);
        if (!ok) failedChannels.add(entry.number);
        if (!mounted) return;
        setState(() => _progress++);
      }

      final problems = [
        if (paramFailures.isNotEmpty)
          'paràmetres no confirmats: ${paramFailures.join(', ')}',
        if (failedChannels.isNotEmpty)
          '${failedChannels.length} canal(s) no confirmats: '
              '${failedChannels.join(', ')}',
      ];
      _showMessage(
        problems.isEmpty
            ? 'Configuració importada.'
            : 'Configuració importada amb incidències — ${problems.join('; ')}.',
      );
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
            _progressTotal > 0
                ? '${(100 * _progress / _progressTotal).round()} %'
                : '',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
    }

    return Column(
      children: [
        const Text(
          'Exporta o importa tota la configuració en un fitxer JSON',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.upload_file),
              label: const Text('Exportar'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
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
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: SizedBox(
        width: 56,
        height: 56,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            // Armed/OFF toggle for the destructive reset flow below — the
            // errorContainer pair (not primaryContainer) since it's arming a
            // dangerous action, not a normal selection.
            backgroundColor: selected
                ? scheme.errorContainer
                : scheme.surfaceContainerHighest,
            foregroundColor: selected
                ? scheme.onErrorContainer
                : scheme.onSurfaceVariant,
            elevation: selected ? 4 : 1,
            padding: const EdgeInsets.all(4),
            minimumSize: Size.zero,
            // The selected (armed) state isn't color/elevation alone — a
            // visible border carries the same information non-color-
            // dependently too.
            side: selected
                ? BorderSide(color: scheme.error, width: 2)
                : BorderSide.none,
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
