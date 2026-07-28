import 'dart:convert';

/// One exported/imported DMX channel: its 4 per-scene values (0-255) and 4
/// per-scene transition modes (0=gradual, 1=initial, 2=final — see
/// [TransitionMode] in `core/constants/v_map.dart`). [number] is the DMX
/// channel number (1-based), included explicitly in the JSON (not just
/// implied by array position) so a hand-edited or reordered file still
/// imports correctly.
class Ardmx4ChannelConfigEntry {
  const Ardmx4ChannelConfigEntry({
    required this.number,
    required this.valors,
    required this.modes,
  });

  final int number;
  final List<int> valors;
  final List<int> modes;

  Map<String, dynamic> toJson() => {
    'canal': number,
    'valors': valors,
    'modes': modes,
  };

  factory Ardmx4ChannelConfigEntry.fromJson(
    int number,
    Map<String, dynamic> json,
  ) {
    final rawValors = json['valors'] as List? ?? const [];
    final rawModes = json['modes'] as List? ?? const [];
    return Ardmx4ChannelConfigEntry(
      number: (json['canal'] as num?)?.toInt() ?? number,
      valors: List.generate(
        4,
        (i) => i < rawValors.length
            ? ((rawValors[i] as num?) ?? 0).toInt().clamp(0, 255)
            : 0,
      ),
      modes: List.generate(
        4,
        (i) => i < rawModes.length
            ? ((rawModes[i] as num?) ?? 0).toInt().clamp(0, 2)
            : 0,
      ),
    );
  }
}

/// The full ARDMX4 configuration as exported/imported via JSON — mirrors
/// what [ParametersScreen] lets the user edit (number of scenes, song,
/// active channel count, volume) plus the 8 cycle period durations and
/// every active channel's 4 per-scene values/modes (queried/set 4-at-a-time
/// over the wire index V63 — see `ARDMX4.ino`'s `handleChannelBulk()`).
///
/// [model]/[firmwareVersio]/[exportatEl] identify where the file came from,
/// so an import can be checked for compatibility before overwriting the
/// device's config (same pattern as `ArdmxOneConfigData` in
/// `features/ardmx_one/config_json.dart`) instead of silently applying a
/// file meant for a different ARDMX model. Older files exported before this
/// existed simply have empty/null values here — treated as "unknown, assume
/// compatible", not as a mismatch.
class Ardmx4ConfigData {
  const Ardmx4ConfigData({
    required this.numeroEscenes,
    required this.numeroCanals,
    required this.numeroMusica,
    required this.nivellVolum,
    required this.periodes,
    required this.canals,
    this.model = defaultModel,
    this.firmwareVersio = '',
    this.exportatEl,
  });

  /// Identifies this app screen's own device — compared against an
  /// imported file's [model] to reject files exported from a different
  /// ARDMX device (e.g. ARDMX One).
  static const defaultModel = 'ARDMX4';

  final int numeroEscenes;
  final int numeroCanals;
  final int numeroMusica;
  final int nivellVolum;
  final List<double> periodes;
  final List<Ardmx4ChannelConfigEntry> canals;
  final String model;
  final String firmwareVersio;
  final DateTime? exportatEl;

  Map<String, dynamic> toJson() => {
    'model': model,
    'versio_firmware': firmwareVersio,
    'exportat_el': exportatEl?.toIso8601String(),
    'numero_escenes': numeroEscenes,
    'numero_canals': numeroCanals,
    'numero_musica': numeroMusica,
    'nivell_volum': nivellVolum,
    'periodes': periodes,
    'canals': [for (final c in canals) c.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory Ardmx4ConfigData.fromJson(Map<String, dynamic> json) {
    final rawCanals = json['canals'] as List? ?? const [];
    final rawPeriodes = json['periodes'] as List? ?? const [];
    return Ardmx4ConfigData(
      model: json['model'] as String? ?? '',
      firmwareVersio: json['versio_firmware'] as String? ?? '',
      exportatEl: DateTime.tryParse(json['exportat_el'] as String? ?? ''),
      numeroEscenes: ((json['numero_escenes'] as num?) ?? 0).toInt(),
      numeroCanals: ((json['numero_canals'] as num?) ?? 0).toInt(),
      numeroMusica: ((json['numero_musica'] as num?) ?? 0).toInt(),
      nivellVolum: ((json['nivell_volum'] as num?) ?? 0).toInt(),
      periodes: List.generate(
        8,
        (i) => i < rawPeriodes.length
            ? ((rawPeriodes[i] as num?) ?? 0).toDouble()
            : 0,
      ),
      canals: [
        for (var i = 0; i < rawCanals.length; i++)
          Ardmx4ChannelConfigEntry.fromJson(
            i + 1,
            rawCanals[i] as Map<String, dynamic>,
          ),
      ],
    );
  }

  factory Ardmx4ConfigData.fromPrettyJson(String raw) =>
      Ardmx4ConfigData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
