import 'dart:convert';

/// One of a channel's 4 transitions (V71) — [tipus] is a raw
/// `TransitionType.vValue` (0-3), kept as a plain int here rather than
/// importing the enum. Per-channel, not shared — each channel has its own
/// 4, not one set shared by every channel. Identical on both firmwares
/// (`handleChannelBulk4Scene()` in ardmx-one-firmware, `handleChannelBulk()`
/// in ardmx4-evo-firmware).
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

  static const defaultFour = [
    defaultLineal,
    defaultLineal,
    defaultLineal,
    defaultLineal,
  ];
}

/// One exported/imported DMX channel: its 4 per-scene values (0-255), its
/// own 4 transitions (type + salt%, per-channel — see
/// [TransicioConfigEntry]) and its editable name. Same shape on the ARDMX
/// One v2 and ARDMX EVO trees (both go through V71 — see
/// `handleChannelBulk4Scene()`/`handleChannelBulk()`), which is exactly why
/// this class is shared between them instead of duplicated per product like
/// the old `ArdmxOneV2ChannelConfigEntry`/`ArdmxEvoChannelConfigEntry` were.
class ChannelConfigEntry {
  const ChannelConfigEntry({
    required this.number,
    required this.valors,
    required this.name,
    this.transicions = TransicioConfigEntry.defaultFour,
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
  factory ChannelConfigEntry.fromJson(int number, Map<String, dynamic> json) {
    final rawValors = json['valors'] as List? ?? const [];
    final rawTransicions = json['transicions'] as List? ?? const [];
    return ChannelConfigEntry(
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

/// EVO-only fields (DFPlayer audio + Mode Manual/Trigger) — grouped under
/// their own optional JSON object (`audio_manual`) rather than flat
/// top-level fields, so a One v2 export simply omits the whole object
/// instead of needing per-field sentinels. `null`/absent on a One v2
/// export; always present on an EVO export.
///
/// There's no separate persisted "Mode Manual" configuration beyond
/// selecting it as the live main-selector mode (V11=2, a runtime/navigation
/// value, not exported config on either firmware today) — so in practice
/// this object only ever carries the audio fields. It keeps the
/// "audio_manual" name from the spec for the cross-import messaging (an
/// EVO file genuinely does carry both audio settings and the *possibility*
/// of Mode Manual, from this device's perspective), but there's nothing
/// Manual-specific to serialize.
class AudioManualConfig {
  const AudioManualConfig({
    required this.numeroMusica,
    required this.nivellVolum,
  });

  final int numeroMusica;
  final int nivellVolum;

  Map<String, dynamic> toJson() => {
    'numero_musica': numeroMusica,
    'nivell_volum': nivellVolum,
  };

  factory AudioManualConfig.fromJson(Map<String, dynamic> json) =>
      AudioManualConfig(
        numeroMusica: ((json['numero_musica'] as num?) ?? 0).toInt(),
        nivellVolum: ((json['nivell_volum'] as num?) ?? 0).toInt(),
      );
}

/// One programmed event (V77) — a one-shot sound and/or a channel forced to
/// 255 at a given moment of the cycle, for a given duration. EVO-only (see
/// [ArdmxConfigData.events]) — matches `EventData`/`handleEventBulk()` in
/// ardmx4-evo-firmware's main.cpp. [index] (0-9) is the event's slot, kept
/// explicit here (unlike [ChannelConfigEntry], where the channel number
/// already IS the array position) because only the DEFINED events get
/// exported — see `ExportImportSection._export()` — so the list can have
/// gaps.
class EventConfigEntry {
  const EventConfigEntry({
    required this.index,
    required this.moment,
    required this.durada,
    required this.pista,
    required this.canal,
  });

  final int index;
  final int moment;
  final int durada;
  final int pista;
  final int canal;

  Map<String, dynamic> toJson() => {
    'index': index,
    'moment': moment,
    'durada': durada,
    'pista': pista,
    'canal': canal,
  };

  factory EventConfigEntry.fromJson(Map<String, dynamic> json) =>
      EventConfigEntry(
        index: ((json['index'] as num?) ?? 0).toInt().clamp(0, 9),
        moment: ((json['moment'] as num?) ?? 0).toInt(),
        durada: ((json['durada'] as num?) ?? 0).toInt(),
        pista: ((json['pista'] as num?) ?? 0).toInt(),
        canal: ((json['canal'] as num?) ?? 0).toInt(),
      );
}

/// Unified export/import format for ARDMX One v2 and ARDMX EVO — a
/// configuration exported from either device can be imported into the
/// other. Replaces the old per-product `ArdmxOneV2ConfigData`/
/// `ArdmxEvoConfigData` (structurally identical except for the audio
/// fields), which used to reject any cross-product import outright via
/// their own `defaultModel` check.
///
/// [origen] (`origenOne`/`origenEvo`, same values as the V64 handshake's
/// "tipus") replaces the old "model" field as the source of truth for
/// which device an export came from — no longer used to REJECT an import,
/// only to decide how to handle [audioManual] (see
/// `ExportImportSection._import()`): missing on a One v2 export because
/// that hardware has none, present on an EVO export.
///
/// No backward compatibility with the pre-unification per-product format —
/// exports made before this change cannot be imported (not versioned via
/// [versioEsquema], which starts fresh at 1 for this format).
class ArdmxConfigData {
  const ArdmxConfigData({
    required this.origen,
    required this.numeroEscenes,
    required this.numeroCanals,
    required this.periodes,
    required this.pessebre,
    required this.descripcio,
    required this.canals,
    this.versioEsquema = currentSchemaVersion,
    this.audioManual,
    this.events,
    this.firmwareVersio = '',
    this.exportatEl,
  });

  static const origenOne = 'ARDMX_ONE';
  static const origenEvo = 'ARDMX_EVO';
  static const currentSchemaVersion = 1;

  final String origen;
  final int versioEsquema;
  final int numeroEscenes;
  final int numeroCanals;
  final List<double> periodes;
  final String pessebre;
  final String descripcio;
  final List<ChannelConfigEntry> canals;

  /// EVO-only fields — see [AudioManualConfig]. `null` on a One v2 export.
  final AudioManualConfig? audioManual;

  /// EVO-only: the DEFINED events (see [EventConfigEntry]) — `null` on a
  /// One v2 export (that firmware has no V77 at all), same "absent, not an
  /// empty list" convention as [audioManual].
  final List<EventConfigEntry>? events;

  final String firmwareVersio;
  final DateTime? exportatEl;

  Map<String, dynamic> toJson() => {
    'origen': origen,
    'versio_esquema': versioEsquema,
    'versio_firmware': firmwareVersio,
    'exportat_el': exportatEl?.toIso8601String(),
    'numero_escenes': numeroEscenes,
    'numero_canals': numeroCanals,
    'periodes': periodes,
    'pessebre': pessebre,
    'descripcio': descripcio,
    if (audioManual != null) 'audio_manual': audioManual!.toJson(),
    if (events != null) 'events': [for (final e in events!) e.toJson()],
    'canals': [for (final c in canals) c.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ArdmxConfigData.fromJson(Map<String, dynamic> json) {
    final rawCanals = json['canals'] as List? ?? const [];
    final rawPeriodes = json['periodes'] as List? ?? const [];
    final rawAudio = json['audio_manual'] as Map<String, dynamic>?;
    final rawEvents = json['events'] as List?;
    return ArdmxConfigData(
      origen: json['origen'] as String? ?? '',
      versioEsquema: ((json['versio_esquema'] as num?) ?? 1).toInt(),
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
      audioManual: rawAudio != null
          ? AudioManualConfig.fromJson(rawAudio)
          : null,
      events: rawEvents != null
          ? [
              for (final e in rawEvents)
                EventConfigEntry.fromJson(e as Map<String, dynamic>),
            ]
          : null,
      canals: [
        for (var i = 0; i < rawCanals.length; i++)
          ChannelConfigEntry.fromJson(i + 1, rawCanals[i] as Map<String, dynamic>),
      ],
    );
  }

  factory ArdmxConfigData.fromPrettyJson(String raw) =>
      ArdmxConfigData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
