import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../core/protocol/virtuino_update.dart';
import '../../../state/providers.dart';
import '../config_json.dart';

/// Exports the whole device configuration (scene count, active channel
/// count, the 8 cycle period durations, pessebre name, descripció, every
/// active channel's 4 per-scene values + own 4 transitions + name, and —
/// only when [hasAudio] — the song/volume; only when [hasEvents] — the
/// defined events) as a JSON file, or imports one back. Shared by the ARDMX
/// One v2 and ARDMX EVO trees (was two
/// near-identical copies, `_ExportImportSection` in each product's own
/// `..._system_config_screen.dart`) — unified so a file exported from
/// either device can be imported into the other (see
/// `ArdmxConfigData`/[origen]).
///
/// Channel data goes through V71 (`handleChannelBulk4Scene()`/
/// `handleChannelBulk()`), which replies to a write automatically, so each
/// round trip is a single frame.
class ExportImportSection extends ConsumerStatefulWidget {
  const ExportImportSection({
    super.key,
    required this.origen,
    required this.channelCountVIndex,
    required this.hasAudio,
    required this.hasEvents,
    required this.fileNamePrefix,
  });

  /// This device's own [ArdmxConfigData.origenOne]/[ArdmxConfigData.origenEvo]
  /// — written on export, and used on import to decide the cross-device
  /// warning message (not to reject the import: any origen is accepted).
  final String origen;

  /// V-index for "number of managed channels" — V08 on the ARDMX One v2
  /// (a literal, not in [VIndex]: that product's own numbering, unrelated
  /// to the EVO's V39/V40), [VIndex.activeChannelsCount] on the EVO.
  final int channelCountVIndex;

  /// Whether this device has DFPlayer audio (EVO) or not (One v2) — decides
  /// whether song/volume are read/written at all, and which cross-import
  /// warning applies when the file's [ArdmxConfigData.audioManual] presence
  /// doesn't match.
  final bool hasAudio;

  /// Whether this device has programmed events (V77, EVO only) — decides
  /// whether the 10 event slots are read/written at all, and the
  /// cross-import warning when the file's [ArdmxConfigData.events] presence
  /// doesn't match. Same reasoning/shape as [hasAudio].
  final bool hasEvents;

  /// `"ardmx_one"` / `"ardmx_evo"` — prefix of the suggested export filename.
  final String fileNamePrefix;

  @override
  ConsumerState<ExportImportSection> createState() =>
      _ExportImportSectionState();
}

class _ExportImportSectionState extends ConsumerState<ExportImportSection> {
  static const _firmwareVersionVIndex = 62;
  static const _pessebreVIndex = 68;
  static const _descripcioVIndex = 69;
  static const _channelBulkVIndex = 71;
  static const _eventBulkVIndex = 77;
  static const _eventCount = 10;
  static const _roundTripTimeout = Duration(milliseconds: 800);

  // The Baixades/Downloads document tree on Android's default (primary)
  // storage volume, addressed the way the Storage Access Framework expects
  // for EXTRA_INITIAL_URI — not a filesystem path. Best-effort only (see
  // file_picker docs): it just no-ops if this doesn't resolve on a given
  // OEM skin, falling back to the system's own last-used location.
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

  /// V71's reply carries a channel's own 4 transitions alongside its 4
  /// values, 13 fields total before the name (which may itself contain
  /// `|`, hence `sublist(12).join('|')` rather than just indexing part 12).
  (List<int>, List<TransicioConfigEntry>, String)? _parseChannelReply(
    String? reply,
  ) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 13) return null;
    final valors = [for (var i = 0; i < 4; i++) int.tryParse(parts[i]) ?? 0];
    final transicions = [
      for (var i = 0; i < 4; i++)
        TransicioConfigEntry(
          tipus: int.tryParse(parts[4 + i * 2]) ?? 0,
          saltPercent: int.tryParse(parts[4 + i * 2 + 1]) ?? 0,
        ),
    ];
    final name = parts.sublist(12).join('|');
    return (valors, transicions, name);
  }

  Future<bool> _assignChannelVerified(ChannelConfigEntry entry) async {
    final transicionsPart = [
      for (final t in entry.transicions) '${t.tipus}|${t.saltPercent}',
    ].join('|');
    final payload =
        '${entry.number}|${entry.valors.join('|')}|$transicionsPart|${entry.name}';

    for (var attempt = 0; attempt < 6; attempt++) {
      final parsed = _parseChannelReply(await _channelRoundTripOnce(payload));
      if (parsed != null &&
          _listEquals(parsed.$1, entry.valors) &&
          _transitionsEqual(parsed.$2, entry.transicions) &&
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

  bool _transitionsEqual(
    List<TransicioConfigEntry> a,
    List<TransicioConfigEntry> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].tipus != b[i].tipus || a[i].saltPercent != b[i].saltPercent) {
        return false;
      }
    }
    return true;
  }

  Future<String?> _eventRoundTripOnce(String payload) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> sub;
    sub = protocol.updates.listen((update) {
      if (update is VirtuinoTUpdate &&
          update.index == _eventBulkVIndex &&
          !completer.isCompleted) {
        completer.complete(update.text);
      }
    });
    protocol.writeText(_eventBulkVIndex, payload);
    final reply = await completer.future.timeout(
      _roundTripTimeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    return reply;
  }

  Future<String?> _eventRoundTrip(String payload) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final reply = await _eventRoundTripOnce(payload);
      if (reply != null) return reply;
    }
    return null;
  }

  /// V77's reply: `"moment|durada|pista|canal"` — see handleEventBulk() in
  /// ardmx4-evo-firmware's main.cpp.
  (int, int, int, int)? _parseEventReply(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 4) return null;
    return (
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
      int.tryParse(parts[2]) ?? 0,
      int.tryParse(parts[3]) ?? 0,
    );
  }

  Future<bool> _assignEventVerified(EventConfigEntry entry) async {
    final payload =
        '${entry.index}|${entry.moment}|${entry.durada}|${entry.pista}|${entry.canal}';
    for (var attempt = 0; attempt < 6; attempt++) {
      final parsed = _parseEventReply(await _eventRoundTripOnce(payload));
      if (parsed != null &&
          parsed.$1 == entry.moment &&
          parsed.$2 == entry.durada &&
          parsed.$3 == entry.pista &&
          parsed.$4 == entry.canal) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _suggestedFileName(String pessebre) {
    final clean = pessebre
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return clean.isEmpty
        ? '${widget.fileNamePrefix}.json'
        : '${widget.fileNamePrefix}_$clean.json';
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
      final numeroCanals = await _readValue(widget.channelCountVIndex);
      if (numeroCanals == null || numeroCanals <= 0) {
        _showMessage('No s\'ha pogut llegir el nombre de canals gestionables.');
        return;
      }

      AudioManualConfig? audioManual;
      if (widget.hasAudio) {
        final numeroMusica = await _readValue(VIndex.songNumber) ?? 0;
        final nivellVolum = await _readValue(VIndex.volume) ?? 0;
        audioManual = AudioManualConfig(
          numeroMusica: numeroMusica.round(),
          nivellVolum: nivellVolum.round(),
        );
      }

      final periodes = <double>[];
      for (var i = 0; i < 8; i++) {
        periodes.add(await _readValue(VIndex.periodDuration(i)) ?? 0);
      }

      List<EventConfigEntry>? events;
      if (widget.hasEvents) {
        setState(() => _statusText = 'Llegint events…');
        events = [];
        for (var i = 0; i < _eventCount; i++) {
          final parsed = _parseEventReply(await _eventRoundTrip('$i'));
          if (parsed == null) continue;
          final (moment, durada, pista, canal) = parsed;
          // Only exports the DEFINED events (same "so or canal" test the
          // Events screen uses) — matches that screen only showing defined
          // events, and keeps the file free of 10 near-empty entries.
          if (pista > 0 || canal > 0) {
            events.add(
              EventConfigEntry(
                index: i,
                moment: moment,
                durada: durada,
                pista: pista,
                canal: canal,
              ),
            );
          }
        }
      }

      final canalsCount = numeroCanals.round();
      final canals = <ChannelConfigEntry>[];
      setState(() {
        _progressTotal = canalsCount;
        _statusText = 'Llegint canals…';
      });
      for (var channel = 1; channel <= canalsCount; channel++) {
        final parsed = _parseChannelReply(await _channelRoundTrip('$channel'));
        canals.add(
          ChannelConfigEntry(
            number: channel,
            valors: parsed?.$1 ?? const [0, 0, 0, 0],
            transicions: parsed?.$2 ?? TransicioConfigEntry.defaultFour,
            name: parsed?.$3 ?? '',
          ),
        );
        if (!mounted) return;
        setState(() => _progress = channel);
      }

      final config = ArdmxConfigData(
        origen: widget.origen,
        numeroEscenes: numeroEscenes.round(),
        numeroCanals: canalsCount,
        periodes: periodes,
        pessebre: pessebre,
        descripcio: descripcio,
        canals: canals,
        events: events,
        audioManual: audioManual,
        firmwareVersio: firmwareVersio,
        exportatEl: DateTime.now(),
      );
      final savedPath = await FilePicker.saveFile(
        fileName: _suggestedFileName(pessebre),
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: _androidDownloadsUri,
        bytes: Uint8List.fromList(utf8.encode(config.toPrettyJson())),
      );
      if (savedPath != null) _showMessage('Configuració desada.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Empty when the file's audio/events presence matches this device
  /// (nothing unusual to call out); otherwise one line per mismatch — shown
  /// as extra lines inside the same confirm dialog rather than a separate
  /// blocking one, since it's informational, not a decision point (the
  /// import proceeds either way once confirmed).
  List<String> _crossImportNotices(ArdmxConfigData config) {
    final notices = <String>[];
    if (widget.hasAudio && config.audioManual == null) {
      notices.add(
        'Aquesta configuració no inclou àudio ni mode manual — es '
        'desactivaran en importar-la.',
      );
    }
    if (!widget.hasAudio && config.audioManual != null) {
      notices.add(
        'Aquesta configuració inclou àudio i mode manual, que aquest '
        'dispositiu no té — s\'ignoraran aquests camps.',
      );
    }
    if (widget.hasEvents && config.events == null) {
      notices.add(
        'Aquesta configuració no inclou events — s\'esborraran els que '
        'hi hagi configurats en aquest dispositiu.',
      );
    }
    if (!widget.hasEvents && config.events != null) {
      notices.add(
        'Aquesta configuració inclou events, que aquest dispositiu no té '
        '— s\'ignoraran.',
      );
    }
    return notices;
  }

  Future<bool> _confirmImport(ArdmxConfigData config) async {
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
    final notices = _crossImportNotices(config);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar configuració?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Es sobreescriuran el nombre d'escenes, el nombre de canals, "
              'els temps de transició, el pessebre, la descripció'
              '${widget.hasAudio ? ', la cançó, el volum' : ''}'
              '${widget.hasEvents ? ', els events' : ''} i els '
              'valors/transicions/noms de ${config.canals.length} canals '
              'amb el contingut del fitxer.'
              '${origen.isNotEmpty ? '\n\nFitxer: $origen' : ''}',
            ),
            for (final notice in notices) ...[
              const SizedBox(height: 12),
              Text(
                notice,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
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
      initialDirectory: _androidDownloadsUri,
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    final ArdmxConfigData config;
    try {
      config = ArdmxConfigData.fromPrettyJson(await File(path).readAsString());
    } catch (_) {
      _showMessage('El fitxer no és un JSON vàlid de configuració.');
      return;
    }
    if (config.numeroCanals <= 0 || config.canals.isEmpty) {
      _showMessage('El fitxer no conté cap canal.');
      return;
    }
    // No longer rejected by origen/model mismatch — a file exported from
    // either device can now be imported into the other (see
    // ArdmxConfigData's header doc). Only the audio_manual presence changes
    // what gets applied (see _crossImportNotice()/below).

    if (!await _confirmImport(config)) return;

    final paramStepCount =
        12 + (widget.hasAudio ? 2 : 0) + (widget.hasEvents ? _eventCount : 0);
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
      await writeParam(
        'nombre de canals',
        widget.channelCountVIndex,
        config.numeroCanals,
      );
      if (widget.hasAudio) {
        // config.audioManual is only non-null when the file itself came
        // from a device with audio (an EVO export) — a One v2 file has none,
        // so this device's own audio gets explicitly forced off (0/Off)
        // rather than left at whatever it happened to be before the import,
        // per the cross-import spec ("es desactivaran en importar-la").
        final audio = config.audioManual;
        await writeParam(
          'cançó',
          VIndex.songNumber,
          audio?.numeroMusica ?? 0,
        );
        await writeParam('volum', VIndex.volume, audio?.nivellVolum ?? 0);
      }
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

      // Marge d'assentament abans del bombardeig de canals — si el nombre
      // d'escenes/canals acaba de canviar, el firmware pot trigar a
      // assentar-se abans de respondre amb fiabilitat.
      await Future.delayed(const Duration(seconds: 3));

      final failedChannels = <int>[];
      for (final entry in config.canals) {
        final ok = await _assignChannelVerified(entry);
        if (!ok) failedChannels.add(entry.number);
        if (!mounted) return;
        setState(() => _progress++);
      }

      final failedEvents = <int>[];
      if (widget.hasEvents) {
        // config.events is only non-null when the file itself came from a
        // device with events (an EVO export) — a One v2 file has none, so
        // every one of THIS device's 10 slots gets explicitly cleared
        // rather than left as-is, same "force off, don't just leave it"
        // reasoning as the audio fields above (see _crossImportNotices()).
        // On an EVO->EVO import, any of the 10 slots NOT present in the
        // file is cleared the same way, so the import fully replaces the
        // event configuration instead of only overlaying what the file
        // happens to mention.
        final byIndex = <int, EventConfigEntry>{
          for (final e in config.events ?? const <EventConfigEntry>[])
            e.index: e,
        };
        for (var i = 0; i < _eventCount; i++) {
          final entry =
              byIndex[i] ??
              EventConfigEntry(index: i, moment: 0, durada: 0, pista: 0, canal: 0);
          final ok = await _assignEventVerified(entry);
          if (!ok) failedEvents.add(i + 1);
          if (mounted) setState(() => _progress++);
        }
      }

      final problems = [
        if (paramFailures.isNotEmpty)
          'paràmetres no confirmats: ${paramFailures.join(', ')}',
        if (failedChannels.isNotEmpty)
          '${failedChannels.length} canal(s) no confirmats: '
              '${failedChannels.join(', ')}',
        if (failedEvents.isNotEmpty)
          '${failedEvents.length} event(s) no confirmats: '
              '${failedEvents.join(', ')}',
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
          'Exporta o importa tota la configuració en un fitxer JSON — '
          'compatible entre ARDMX One v2 i ARDMX EVO',
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
