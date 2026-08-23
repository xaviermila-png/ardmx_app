import 'dart:convert';

/// One exported/imported DMX channel on the ARDMX EVO: its 4 per-scene
/// values (0-255) and its editable name (up to 15 characters, V65-V67 for
/// the 3 currently-selected slots) — the EVO firmware has channel names
/// like ARDMX One, unlike the Mega, so this mirrors
/// `Ardmx4ChannelConfigEntry` (`features/parameters/config_json.dart`) plus
/// a [name] field. No longer carries a per-scene transition mode (that was
/// replaced by 4 GLOBAL transitions, not exported/imported here — see
/// `GlobalTransitionEditor`/V72).
class ArdmxEvoChannelConfigEntry {
  const ArdmxEvoChannelConfigEntry({
    required this.number,
    required this.valors,
    required this.name,
  });

  final int number;
  final List<int> valors;
  final String name;

  Map<String, dynamic> toJson() => {
    'canal': number,
    'valors': valors,
    'nom': name,
  };

  factory ArdmxEvoChannelConfigEntry.fromJson(
    int number,
    Map<String, dynamic> json,
  ) {
    final rawValors = json['valors'] as List? ?? const [];
    return ArdmxEvoChannelConfigEntry(
      number: (json['canal'] as num?)?.toInt() ?? number,
      valors: List.generate(
        4,
        (i) => i < rawValors.length
            ? ((rawValors[i] as num?) ?? 0).toInt().clamp(0, 255)
            : 0,
      ),
      name: json['nom'] as String? ?? '',
    );
  }
}

/// The full ARDMX EVO configuration as exported/imported via JSON — the
/// Mega's own scenes/song/volume/period fields (see `Ardmx4ConfigData`) plus
/// ARDMX One's pessebre/descripció fields, since the EVO firmware has both.
/// Channel data is queried/set one channel at a time over V71 (see
/// `handleChannelBulk()` in the EVO firmware's `main.cpp`), which — unlike
/// the Mega's V63 — replies automatically to a write, so each round trip is
/// a single frame.
class ArdmxEvoConfigData {
  const ArdmxEvoConfigData({
    required this.numeroEscenes,
    required this.numeroCanals,
    required this.numeroMusica,
    required this.nivellVolum,
    required this.periodes,
    required this.pessebre,
    required this.descripcio,
    required this.canals,
    this.model = defaultModel,
    this.firmwareVersio = '',
    this.exportatEl,
  });

  /// Identifies this app screen's own device — compared against an
  /// imported file's [model] to reject files exported from a different
  /// ARDMX device (e.g. ARDMX4 or ARDMX One).
  static const defaultModel = 'ARDMX EVO';

  final int numeroEscenes;
  final int numeroCanals;
  final int numeroMusica;
  final int nivellVolum;
  final List<double> periodes;
  final String pessebre;
  final String descripcio;
  final List<ArdmxEvoChannelConfigEntry> canals;
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
    'pessebre': pessebre,
    'descripcio': descripcio,
    'canals': [for (final c in canals) c.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ArdmxEvoConfigData.fromJson(Map<String, dynamic> json) {
    final rawCanals = json['canals'] as List? ?? const [];
    final rawPeriodes = json['periodes'] as List? ?? const [];
    return ArdmxEvoConfigData(
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
      pessebre: json['pessebre'] as String? ?? '',
      descripcio: json['descripcio'] as String? ?? '',
      canals: [
        for (var i = 0; i < rawCanals.length; i++)
          ArdmxEvoChannelConfigEntry.fromJson(
            i + 1,
            rawCanals[i] as Map<String, dynamic>,
          ),
      ],
    );
  }

  factory ArdmxEvoConfigData.fromPrettyJson(String raw) =>
      ArdmxEvoConfigData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
