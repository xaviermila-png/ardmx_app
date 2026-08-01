import 'dart:convert';

/// One exported/imported DMX channel on the ARDMX4 EVO: its 4 per-scene
/// values (0-255), 4 per-scene transition modes (0=gradual, 1=initial,
/// 2=final), and its editable name (up to 15 characters, V65-V67 for the 3
/// currently-selected slots) — the EVO firmware has channel names like
/// ARDMX One, unlike the Mega, so this mirrors `Ardmx4ChannelConfigEntry`
/// (`features/parameters/config_json.dart`) plus a [name] field.
class Ardmx4EvoChannelConfigEntry {
  const Ardmx4EvoChannelConfigEntry({
    required this.number,
    required this.valors,
    required this.modes,
    required this.name,
  });

  final int number;
  final List<int> valors;
  final List<int> modes;
  final String name;

  Map<String, dynamic> toJson() => {
    'canal': number,
    'valors': valors,
    'modes': modes,
    'nom': name,
  };

  factory Ardmx4EvoChannelConfigEntry.fromJson(
    int number,
    Map<String, dynamic> json,
  ) {
    final rawValors = json['valors'] as List? ?? const [];
    final rawModes = json['modes'] as List? ?? const [];
    return Ardmx4EvoChannelConfigEntry(
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
      name: json['nom'] as String? ?? '',
    );
  }
}

/// The full ARDMX4 EVO configuration as exported/imported via JSON — the
/// Mega's own scenes/song/volume/period fields (see `Ardmx4ConfigData`) plus
/// ARDMX One's pessebre/descripció fields, since the EVO firmware has both.
/// Channel data is queried/set one channel at a time over V71 (see
/// `handleChannelBulk()` in the EVO firmware's `main.cpp`), which — unlike
/// the Mega's V63 — replies automatically to a write, so each round trip is
/// a single frame.
class Ardmx4EvoConfigData {
  const Ardmx4EvoConfigData({
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
  static const defaultModel = 'ARDMX4 EVO';

  final int numeroEscenes;
  final int numeroCanals;
  final int numeroMusica;
  final int nivellVolum;
  final List<double> periodes;
  final String pessebre;
  final String descripcio;
  final List<Ardmx4EvoChannelConfigEntry> canals;
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

  factory Ardmx4EvoConfigData.fromJson(Map<String, dynamic> json) {
    final rawCanals = json['canals'] as List? ?? const [];
    final rawPeriodes = json['periodes'] as List? ?? const [];
    return Ardmx4EvoConfigData(
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
          Ardmx4EvoChannelConfigEntry.fromJson(
            i + 1,
            rawCanals[i] as Map<String, dynamic>,
          ),
      ],
    );
  }

  factory Ardmx4EvoConfigData.fromPrettyJson(String raw) =>
      Ardmx4EvoConfigData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
