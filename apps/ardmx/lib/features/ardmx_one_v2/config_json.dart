import 'dart:convert';

/// One of a channel's 4 transitions (V71, see `ChannelTransitionEditor`) —
/// [tipus] is a raw `TransitionType.vValue` (0-3), kept as a plain int here
/// rather than importing the enum, matching how
/// [ArdmxOneV2ChannelConfigEntry] stores raw wire values throughout this
/// file. Per-channel, not shared — each channel has its own 4, not one set
/// shared by every channel.
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

/// One exported/imported DMX channel on the ARDMX One v2: its 4 per-scene
/// values (0-255), its own 4 transitions (type + salt%, per-channel — see
/// [TransicioConfigEntry]) and its editable name — same shape as the ARDMX
/// EVO tree's own `ArdmxEvoChannelConfigEntry`, kept as its own copy
/// (separate DTO per product, same convention already used for ARDMX4/One
/// v1/EVO) rather than shared, partly so a v1/v2/EVO export can never be
/// cross-imported by mistake (see [ArdmxOneV2ConfigData.defaultModel]).
class ArdmxOneV2ChannelConfigEntry {
  const ArdmxOneV2ChannelConfigEntry({
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
  factory ArdmxOneV2ChannelConfigEntry.fromJson(
    int number,
    Map<String, dynamic> json,
  ) {
    final rawValors = json['valors'] as List? ?? const [];
    final rawTransicions = json['transicions'] as List? ?? const [];
    return ArdmxOneV2ChannelConfigEntry(
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

/// The full ARDMX One v2 configuration as exported/imported via JSON —
/// scene count, active channel count, the 8 cycle period durations,
/// pessebre name, descripció and every active channel's 4 per-scene values
/// + its own 4 transitions + name. No song/volume fields (no DFPlayer on
/// this hardware, unlike EVO's `ArdmxEvoConfigData`). Channel data goes
/// through V71 (see `handleChannelBulk4Scene()` in ardmx-one-firmware's
/// `main.cpp`).
class ArdmxOneV2ConfigData {
  const ArdmxOneV2ConfigData({
    required this.numeroEscenes,
    required this.numeroCanals,
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
  /// ARDMX device (ARDMX4, ARDMX One v1, or EVO).
  static const defaultModel = 'ARDMX One v2';

  final int numeroEscenes;
  final int numeroCanals;
  final List<double> periodes;
  final String pessebre;
  final String descripcio;
  final List<ArdmxOneV2ChannelConfigEntry> canals;
  final String model;
  final String firmwareVersio;
  final DateTime? exportatEl;

  Map<String, dynamic> toJson() => {
    'model': model,
    'versio_firmware': firmwareVersio,
    'exportat_el': exportatEl?.toIso8601String(),
    'numero_escenes': numeroEscenes,
    'numero_canals': numeroCanals,
    'periodes': periodes,
    'pessebre': pessebre,
    'descripcio': descripcio,
    'canals': [for (final c in canals) c.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ArdmxOneV2ConfigData.fromJson(Map<String, dynamic> json) {
    final rawCanals = json['canals'] as List? ?? const [];
    final rawPeriodes = json['periodes'] as List? ?? const [];
    return ArdmxOneV2ConfigData(
      model: json['model'] as String? ?? '',
      firmwareVersio: json['versio_firmware'] as String? ?? '',
      exportatEl: DateTime.tryParse(json['exportat_el'] as String? ?? ''),
      numeroEscenes: ((json['numero_escenes'] as num?) ?? 0).toInt(),
      numeroCanals: ((json['numero_canals'] as num?) ?? 0).toInt(),
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
          ArdmxOneV2ChannelConfigEntry.fromJson(
            i + 1,
            rawCanals[i] as Map<String, dynamic>,
          ),
      ],
    );
  }

  factory ArdmxOneV2ConfigData.fromPrettyJson(String raw) =>
      ArdmxOneV2ConfigData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
