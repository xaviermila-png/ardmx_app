import 'dart:convert';

/// One exported/imported DMX channel: its editable name and its current
/// 0-255 value. [number] is the DMX channel number (1-based), included
/// explicitly in the JSON (not just implied by array position) so a
/// hand-edited or reordered file still imports correctly.
class ChannelConfigEntry {
  const ChannelConfigEntry({
    required this.number,
    required this.name,
    required this.value,
  });

  final int number;
  final String name;
  final int value;

  Map<String, dynamic> toJson() => {
    'canal': number,
    'nom': name,
    'valor': value,
  };

  factory ChannelConfigEntry.fromJson(int number, Map<String, dynamic> json) {
    return ChannelConfigEntry(
      number: (json['canal'] as num?)?.toInt() ?? number,
      name: json['nom'] as String? ?? '',
      value: ((json['valor'] as num?) ?? 0).toInt().clamp(0, 255),
    );
  }
}

/// The full ARDMX One configuration as exported/imported via JSON — mirrors
/// what [ArdmxOneConfigScreen] lets the user edit (pessebre name,
/// description, active channel count) plus every active channel's name and
/// current value (queried/set one at a time over the wire index V70 — see
/// `firmware/ardmx_one/src/main.cpp`).
///
/// [model]/[firmwareVersio]/[exportatEl] identify where the file came from,
/// so an import can be checked for compatibility before overwriting the
/// device's config (see `_confirmImport` in `ardmx_one_config_screen.dart`)
/// instead of silently applying a file meant for a different ARDMX model.
/// Older files exported before this existed simply have empty/null values
/// here — treated as "unknown, assume compatible", not as a mismatch.
class ArdmxOneConfigData {
  const ArdmxOneConfigData({
    required this.pessebre,
    required this.descripcio,
    required this.numeroCanals,
    required this.canals,
    this.model = defaultModel,
    this.firmwareVersio = '',
    this.exportatEl,
  });

  /// Identifies this app screen's own device — compared against an
  /// imported file's [model] to reject files exported from a different
  /// ARDMX device (e.g. ARDMX4).
  static const defaultModel = 'ARDMX One';

  final String pessebre;
  final String descripcio;
  final int numeroCanals;
  final List<ChannelConfigEntry> canals;
  final String model;
  final String firmwareVersio;
  final DateTime? exportatEl;

  Map<String, dynamic> toJson() => {
    'model': model,
    'versio_firmware': firmwareVersio,
    'exportat_el': exportatEl?.toIso8601String(),
    'pessebre': pessebre,
    'descripcio': descripcio,
    'numero_canals': numeroCanals,
    'canals': [for (final c in canals) c.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory ArdmxOneConfigData.fromJson(Map<String, dynamic> json) {
    final rawCanals = json['canals'] as List? ?? const [];
    return ArdmxOneConfigData(
      model: json['model'] as String? ?? '',
      firmwareVersio: json['versio_firmware'] as String? ?? '',
      exportatEl: DateTime.tryParse(json['exportat_el'] as String? ?? ''),
      pessebre: json['pessebre'] as String? ?? '',
      descripcio: json['descripcio'] as String? ?? '',
      numeroCanals: ((json['numero_canals'] as num?) ?? 0).toInt(),
      canals: [
        for (var i = 0; i < rawCanals.length; i++)
          ChannelConfigEntry.fromJson(
            i + 1,
            rawCanals[i] as Map<String, dynamic>,
          ),
      ],
    );
  }

  factory ArdmxOneConfigData.fromPrettyJson(String raw) =>
      ArdmxOneConfigData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
