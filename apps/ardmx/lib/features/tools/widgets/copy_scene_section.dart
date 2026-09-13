import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/protocol/virtuino_update.dart';
import '../../../state/providers.dart';
import '../../system_config/config_json.dart';

/// Copies every managed channel's value at [_SceneRow.origen] onto
/// [_SceneRow.desti], leaving the channel's other 3 scene values, its own 4
/// transitions and its name untouched. Round-trips each channel 1..N
/// through V71 (`handleChannelBulk4Scene()`/`handleChannelBulk()`) — same
/// read-modify-write shape and same verify-on-write retry pattern as
/// [ExportImportSection]'s own channel loop, since both need the same
/// reliability over an unreliable BLE round trip.
class CopySceneSection extends ConsumerStatefulWidget {
  const CopySceneSection({super.key, required this.channelCountVIndex});

  /// V-index for "number of managed channels" — see
  /// [ExportImportSection.channelCountVIndex] for why this differs per
  /// product (V08 literal on the ARDMX One v2, [VIndex.activeChannelsCount]
  /// on the EVO).
  final int channelCountVIndex;

  @override
  ConsumerState<CopySceneSection> createState() => _CopySceneSectionState();
}

class _CopySceneSectionState extends ConsumerState<CopySceneSection> {
  static const _channelBulkVIndex = 71;
  static const _roundTripTimeout = Duration(milliseconds: 800);

  bool _running = false;
  String? _statusText;
  int _progress = 0;
  int _progressTotal = 1;
  int _origen = 1;
  int _desti = 2;

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

  /// Same reply shape as ExportImportSection's own parser — 4 values + 4
  /// transitions (8 fields) + name, `|`-delimited; the name may itself
  /// contain `|`, hence `sublist(12).join('|')` rather than indexing part 12.
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(int origen, int desti) async {
    if (origen == desti) {
      _showMessage('Tria dues escenes diferents.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copiar canals?'),
        content: Text(
          "Se sobreescriuran tots els valors de l'escena $desti amb els de "
          "l'escena $origen, a tots els canals gestionats. Els noms i les "
          'transicions de cada canal no es toquen. Aquesta acció no es pot '
          'desfer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel·lar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Copiar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _running = true;
      _statusText = 'Llegint nombre de canals…';
      _progress = 0;
      _progressTotal = 1;
    });
    try {
      final numeroCanals = await _readValue(widget.channelCountVIndex);
      if (numeroCanals == null || numeroCanals <= 0) {
        _showMessage('No s\'ha pogut llegir el nombre de canals gestionables.');
        return;
      }
      final canalsCount = numeroCanals.round();
      setState(() {
        _progressTotal = canalsCount;
        _statusText = 'Copiant escena $origen -> escena $desti…';
      });

      final failed = <int>[];
      for (var channel = 1; channel <= canalsCount; channel++) {
        final parsed = _parseChannelReply(await _channelRoundTrip('$channel'));
        if (parsed == null) {
          failed.add(channel);
        } else {
          final (valors, transicions, name) = parsed;
          final newValors = [...valors];
          newValors[desti - 1] = valors[origen - 1];
          final ok = await _assignChannelVerified(
            ChannelConfigEntry(
              number: channel,
              valors: newValors,
              name: name,
              transicions: transicions,
            ),
          );
          if (!ok) failed.add(channel);
        }
        if (!mounted) return;
        setState(() => _progress = channel);
      }

      _showMessage(
        failed.isEmpty
            ? 'Canals copiats.'
            : 'Copiat amb incidències — ${failed.length} canal(s) no '
                  'confirmats: ${failed.join(', ')}.',
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final numeroEscenes =
        ref.watch(appStateProvider.select((s) => s.activeScenesCount)) ?? 1;

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
            _progressTotal > 0 ? 'Canal $_progress de $_progressTotal' : '',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
    }

    if (numeroEscenes <= 1) {
      return const Text(
        'Calen almenys 2 escenes actives per poder copiar-ne els canals.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13),
      );
    }

    final origen = _origen.clamp(1, numeroEscenes);
    final desti = _desti.clamp(1, numeroEscenes);

    // Llista desplegable, no un selector de segments: amb 4 escenes actives
    // (el màxim), dos SegmentedButton costat a costat més la fletxa no
    // càpiga a l'amplada d'un mòbil normal i es tallaven — confirmat en
    // maquinari real. Un dropdown sempre ocupa el mateix amplat tancat,
    // sigui quantes escenes hi hagi.
    Widget picker(String label, int value, ValueChanged<int> onChanged) {
      return Expanded(
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButton<int>(
              value: value,
              isExpanded: true,
              items: [
                for (var s = 1; s <= numeroEscenes; s++)
                  DropdownMenuItem(value: s, child: Text('Escena $s')),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        const Text(
          "Copia tots els valors dels canals gestionats d'una escena a "
          'una altra.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            picker('Origen', origen, (v) => setState(() => _origen = v)),
            const Padding(
              padding: EdgeInsets.only(bottom: 12, left: 4, right: 4),
              child: Icon(Icons.arrow_forward),
            ),
            picker('Destí', desti, (v) => setState(() => _desti = v)),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _copy(origen, desti),
          icon: const Icon(Icons.content_copy),
          label: const Text('Copiar'),
        ),
      ],
    );
  }
}
