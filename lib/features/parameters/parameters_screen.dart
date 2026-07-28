import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'config_json.dart';

/// Parameters screen (V50=4): number of active scenes, song to play,
/// number of manageable channels, and the armed/confirm reset of Arduino
/// variables. All four values are plain Arduino state (V0/V18/V39/V40/V41),
/// never pushed unsolicited, so this screen polls them like every other
/// screen that shows live V-values.
class ParametersScreen extends ConsumerStatefulWidget {
  const ParametersScreen({super.key});

  @override
  ConsumerState<ParametersScreen> createState() => _ParametersScreenState();
}

class _ParametersScreenState extends ConsumerState<ParametersScreen> {
  static const _pollInterval = Duration(milliseconds: 400);

  Timer? _pollTimer;
  bool _resetPending = false;

  @override
  void initState() {
    super.initState();
    // Deferred a frame: _poll() calls ModalRoute.of(context), which isn't
    // resolvable synchronously inside initState (see Scene/Channels and RGB
    // Wheel for the same fix and the crash it avoids).
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    // Only the topmost route should poll — see Scene/Channels and RGB
    // Wheel's _poll() for why: two screens polling at once can corrupt the
    // wire protocol badly enough to leave garbage stuck in Arduino state.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    // While waiting for the reset confirmation, the Arduino can be busy
    // long enough (actually reinitializing its variables) that polling the
    // full bundle piles up faster than it drains — observed on real
    // hardware as a burst of ~30 queued requests all replied to at once.
    // Narrow to just the two indices we're actually waiting on so the
    // serial link stays light while it's busy.
    if (_resetPending) {
      ref.read(protocolProvider).requestAll([
        VIndex.resetConfirm1,
        VIndex.resetConfirm2,
      ]);
      return;
    }

    ref.read(protocolProvider).requestAll([
      VIndex.activeScenesCount,
      VIndex.songNumber,
      VIndex.activeChannelsCount,
      VIndex.maxChannels,
      VIndex.resetConfirm1,
      VIndex.resetConfirm2,
    ]);
  }

  Future<void> _editChannelsCount(int current, int max) async {
    final controller = TextEditingController(text: '$current');
    String? error;

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final parsed = int.tryParse(controller.text);
              if (parsed == null || parsed < 0 || parsed > max) {
                setDialogState(() => error = 'Ha de ser entre 0 i $max');
                return;
              }
              if (parsed % 3 != 0) {
                setDialogState(() => error = 'Ha de ser múltiple de 3');
                return;
              }
              Navigator.of(context).pop(parsed);
            }

            return AlertDialog(
              title: const Text('Canals gestionables'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  errorText: error,
                  helperText: 'Múltiple de 3, entre 0 i $max',
                ),
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel·la'),
                ),
                TextButton(onPressed: submit, child: const Text("D'acord")),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      ref.read(appStateProvider.notifier).setActiveChannelsCount(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenesCount = ref.watch(
      appStateProvider.select((s) => s.activeScenesCount),
    );
    final songNumber = ref.watch(appStateProvider.select((s) => s.songNumber));
    final channelsCount = ref.watch(
      appStateProvider.select((s) => s.activeChannelsCount),
    );
    final maxChannels = ref.watch(
      appStateProvider.select((s) => s.maxChannels),
    );
    final resetArmed = ref.watch(appStateProvider.select((s) => s.resetArmed));

    // The Arduino sets V41/V42 back to 0 itself once it has actually
    // finished reinitializing its variables — that's the real confirmation
    // of completion, not the instant we send the trigger (which only ever
    // proves the write was sent, not that the reset ran).
    ref.listen(
      appStateProvider.select((s) => (s.resetArmed, s.resetConfirm2)),
      (previous, next) {
        if (_resetPending && !next.$1 && next.$2 == 0) {
          setState(() => _resetPending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Variables reinicialitzades')),
          );
        }
      },
    );

    return AppScaffold(
      title: 'Paràmetres',
      automaticallyImplyLeading: false,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: "Nombre d'escenes",
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var n = 1; n <= 4; n++)
                          _SelectableButton(
                            label: '$n',
                            selected: scenesCount == n,
                            selectedBackground: Colors.orange.shade200,
                            selectedForeground: Colors.orange.shade900,
                            onTap: () => ref
                                .read(appStateProvider.notifier)
                                .setActiveScenesCount(n),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Cançó a reproduir',
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _SelectableButton(
                              label: 'Off',
                              selected: songNumber == 0,
                              selectedBackground: Colors.blue.shade200,
                              selectedForeground: Colors.blue.shade900,
                              onTap: () => ref
                                  .read(appStateProvider.notifier)
                                  .setSongNumber(0),
                            ),
                            for (var n = 1; n <= 4; n++)
                              _SelectableButton(
                                label: '$n',
                                selected: songNumber == n,
                                selectedBackground: Colors.blue.shade200,
                                selectedForeground: Colors.blue.shade900,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setSongNumber(n),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Off = No música',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Canals gestionables',
                    child: Column(
                      children: [
                        const Text(
                          'Màxim nombre de canals: 99',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '(ha de ser múltiple de 3)',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _editChannelsCount(
                              channelsCount ?? 0,
                              maxChannels ?? 100,
                            ),
                            child: Container(
                              width: 90,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${channelsCount ?? '—'}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'En transicions és recomanable que el nombre de '
                          'canals a gestionar no passi de 48',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Reset de fàbrica',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Single toggle button: tap to arm (OFF -> ON), tap again
                        // to disarm — this alone never resets anything, it just
                        // reveals the confirm button below/beside it.
                        _SelectableButton(
                          label: resetArmed ? 'ON' : 'OFF',
                          selected: resetArmed,
                          selectedBackground: Colors.red.shade200,
                          selectedForeground: Colors.red.shade900,
                          onTap: _resetPending
                              ? () {}
                              : () => ref
                                    .read(appStateProvider.notifier)
                                    .setResetArmed(!resetArmed),
                        ),
                        // Keep showing the confirm button (as a spinner)
                        // while _resetPending — confirmReset() optimistically
                        // flips resetArmed back to false immediately, but
                        // the button must stay up until the Arduino's own
                        // confirmation arrives.
                        if (resetArmed || _resetPending) ...[
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _resetPending
                                ? null
                                : () {
                                    setState(() => _resetPending = true);
                                    ref
                                        .read(appStateProvider.notifier)
                                        .confirmReset();
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
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Configuració',
                    child: const _ExportImportSection(),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                FloatingActionButton(
                  heroTag: 'parametersBack',
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Tornar al menú principal',
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

class _SelectableButton extends StatelessWidget {
  const _SelectableButton({
    required this.label,
    required this.selected,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedBackground;
  final Color selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? selectedBackground : null,
          foregroundColor: selected ? selectedForeground : null,
          elevation: selected ? 4 : 1,
          // Material's default button padding left almost no room for
          // 3-letter labels ("Off"/"OFF") inside a 56×56 box, forcing the
          // FittedBox below to shrink them down to near-invisible.
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

/// Exports the whole device configuration (scene count, song, volume,
/// active channel count, the 8 cycle period durations, and every active
/// channel's 4 per-scene values+transition modes) as a JSON file shared via
/// Android's system share sheet, or imports one back. Mirrors ARDMX One's
/// own `_ExportImportSection` (`features/ardmx_one/ardmx_one_config_screen.dart`).
///
/// Channel data has no bulk read/write on the wire protocol — V01-03/V31-33
/// only ever expose the 3 currently-selected channels' values/modes for the
/// *active* scene. Both directions go through V63 instead (query/assign a
/// single channel's 4 scenes at once by its explicit number — see
/// `handleChannelBulk()` in `ARDMX4.ino`), sent sequentially and awaited one
/// at a time: the wire protocol has no request/response correlation (any
/// reply could be mistaken for a different in-flight request).
///
/// Unlike ARDMX One's V70, a plain write to V63 gets no automatic reply —
/// the Mega's VirtuinoCM library only replies to reads — so each channel
/// round trip is two frames (write the query/assignment, then explicitly
/// request a read) instead of one.
class _ExportImportSection extends ConsumerStatefulWidget {
  const _ExportImportSection();

  @override
  ConsumerState<_ExportImportSection> createState() =>
      _ExportImportSectionState();
}

class _ExportImportSectionState extends ConsumerState<_ExportImportSection> {
  static const _firmwareVersionVIndex = 62;
  static const _channelBulkVIndex = 63;
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

  /// Sends a V63 payload (either `"N"` to query channel N, or
  /// `"N|v1|m1|v2|m2|v3|m3|v4|m4"` to assign it) then a follow-up read
  /// request, and awaits the matching `"v1|m1|v2|m2|v3|m3|v4|m4"` reply the
  /// firmware leaves for either case — see the class doc for why this is
  /// two frames, not one.
  Future<String?> _channelRoundTrip(String payload) async {
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
    protocol.requestT(_channelBulkVIndex);
    final reply = await completer.future.timeout(
      _roundTripTimeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    return reply;
  }

  (List<int>, List<int>)? _parseChannelReply(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length != 8) return null;
    final valors = <int>[];
    final modes = <int>[];
    for (var i = 0; i < 8; i += 2) {
      valors.add(int.tryParse(parts[i]) ?? 0);
      modes.add(int.tryParse(parts[i + 1]) ?? 0);
    }
    return (valors, modes);
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
      final canals = <Ardmx4ChannelConfigEntry>[];
      setState(() {
        _progressTotal = canalsCount;
        _statusText = 'Llegint canals…';
      });
      for (var channel = 1; channel <= canalsCount; channel++) {
        final parsed = _parseChannelReply(await _channelRoundTrip('$channel'));
        canals.add(
          Ardmx4ChannelConfigEntry(
            number: channel,
            valors: parsed?.$1 ?? const [0, 0, 0, 0],
            modes: parsed?.$2 ?? const [0, 0, 0, 0],
          ),
        );
        if (!mounted) return;
        setState(() => _progress = channel);
      }

      final config = Ardmx4ConfigData(
        numeroEscenes: numeroEscenes.round(),
        numeroCanals: canalsCount,
        numeroMusica: numeroMusica.round(),
        nivellVolum: nivellVolum.round(),
        periodes: periodes,
        canals: canals,
        firmwareVersio: firmwareVersio,
        exportatEl: DateTime.now(),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ardmx4_config.json');
      await file.writeAsString(config.toPrettyJson());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Configuració ARDMX4'),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _confirmImport(Ardmx4ConfigData config) async {
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
          'nombre de canals, els temps de transició i els valors/modes de '
          '${config.canals.length} canals amb el contingut del fitxer.'
          '${origen.isNotEmpty ? '\n\nFitxer: $origen' : ''}',
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

    final Ardmx4ConfigData config;
    try {
      config = Ardmx4ConfigData.fromPrettyJson(await File(path).readAsString());
    } catch (_) {
      _showMessage('El fitxer no és un JSON vàlid de configuració.');
      return;
    }
    if (config.numeroCanals <= 0 || config.canals.isEmpty) {
      _showMessage('El fitxer no conté cap canal.');
      return;
    }
    // Fitxers antics exportats abans d'aquest camp tenen model buit — es
    // consideren compatibles. Només es bloqueja quan el fitxer indica
    // explícitament un model diferent (p.ex. exportat des de l'ARDMX One).
    if (config.model.isNotEmpty &&
        config.model != Ardmx4ConfigData.defaultModel) {
      _showMessage(
        'Aquest fitxer és de "${config.model}", no d\'ARDMX4. '
        'No s\'ha importat.',
      );
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
      protocol.writeV(VIndex.activeScenesCount, config.numeroEscenes);
      protocol.writeV(VIndex.songNumber, config.numeroMusica);
      protocol.writeV(VIndex.volume, config.nivellVolum);
      protocol.writeV(VIndex.activeChannelsCount, config.numeroCanals);
      for (var i = 0; i < 8 && i < config.periodes.length; i++) {
        protocol.writeV(VIndex.periodDuration(i), config.periodes[i]);
      }

      for (final entry in config.canals) {
        final fields = <String>[];
        for (var i = 0; i < 4; i++) {
          fields.add('${entry.valors[i]}');
          fields.add('${entry.modes[i]}');
        }
        await _channelRoundTrip('${entry.number}|${fields.join('|')}');
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
          'Exporta o importa tota la configuració en un fitxer JSON.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 6),
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
