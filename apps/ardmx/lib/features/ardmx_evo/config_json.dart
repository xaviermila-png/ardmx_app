import 'dart:convert';

/// One of a channel's 4 transitions (V71, see `ChannelTransitionEditor`) —
/// [tipus] is a raw `TransitionType.vValue` (0-3), kept as a plain int here
/// rather than importing the enum, matching how [ArdmxEvoChannelConfigEntry]
/// stores raw wire values throughout this file. Per-channel, not shared —
/// each channel has its own 4, not one set shared by every channel.
class TransicioConfigEntry {
  const TransicioConfigEntry({required this.tipus, required this.saltPercent});

  final int tipus;
  final int saltPercent;

  Map<String, dynamic> toJson() => {'tipus': tipus, 'salt_percent': saltPercent};

  factory TransicioConfigEntry.fromJson(Map<String, dynamic> json) =>
      TransicioConfigEntry(
        tipus: ((json['tipus'] as num?) ?? 0).toInt().clamp(0, 3),
        saltPercent: ((json['salt_percent'] as num?) ?? 0).toInt().clamp(0, 100),
      );

  static const defaultLineal = TransicioConfigEntry(tipus: 0, saltPercent: 0);
}

/// One exported/imported DMX channel on the ARDMX EVO: its 4 per-scene
/// values (0-255), its own 4 transitions (type + salt%, per-channel — see
/// [TransicioConfigEntry]) and its editable name (up to 15 characters,
/// V65-V67 for the 3 currently-selected slots) — the EVO firmware has
/// channel names like ARDMX One, unlike the Mega, so this mirrors
/// `Ardmx4ChannelConfigEntry` (`features/parameters/config_json.dart`) plus
/// [name]/[transicions].
class ArdmxEvoChannelConfigEntry {
  const ArdmxEvoChannelConfigEntry({
    required this.number,
    required this.valors,
    required this.name,
    this.transicions = const [
      TransicioConfigEntry.defaultLineal,
      TransicioConfigEntry.defaultLineal,
      TransicioConfigEntry.defaultLineal,
      TransicioConfigEntry.defaultLineal,
    ],
  });

  final int number;
  final List<int> valors;
  final String name;
  final List<TransicioConfigEntry> transicions;

  Map<String, dynamic> toJson() => {
    'canal': number,
    'valors': valors,
    'transicions': [for (final t in transicions) t.toJson()],
    'nom': name,
  };

  /// Files exported before per-channel transitions existed have no
  /// "transicions" key on the channel entry — falls back to all-LINEAL/0%
  /// (the firmware's own factory-reset default) rather than failing to
  /// import at all.
  factory ArdmxEvoChannelConfigEntry.fromJson(
    int number,
    Map<String, dynamic> json,
  ) {
    final rawValors = json['valors'] as List? ?? const [];
    final rawTransicions = json['transicions'] as List? ?? const [];
    return ArdmxEvoChannelConfigEntry(
      number: (json['canal'] as num?)?.toInt() ?? number,
      valors: List.generate(
        4,
        (i) => i < rawValors.length
            ? ((rawValors[i] as num?) ?? 0).toInt().clamp(0, 255)
            : 0,
      ),
      transicions: List.generate(
        4,
        (i) => i < rawTransicions.length
            ? TransicioConfigEntry.fromJson(
                rawTransicions[i] as Map<String, dynamic>,
              )
            : TransicioConfigEntry.defaultLineal,
      ),
      name: json['nom'] as String? ?? '',
    );
  }
}

/// The full ARDMX EVO configuration as exported/imported via JSON — the
/// Mega's own scenes/song/volume/period fields (see `Ardmx4ConfigData`) plus
/// ARDMX One's pessebre/descripció fields, since the EVO firmware has both.
/// Channel data (values + each channel's own transitions) is queried/set
/// one channel at a time over V71 (see `handleChannelBulk()` in the EVO
/// firmware's `main.cpp`), which — unlike the Mega's V63 — replies
/// automatically to a write, so each round trip is a single frame.
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
