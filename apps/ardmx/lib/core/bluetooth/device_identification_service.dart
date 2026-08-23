import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/virtuino_update.dart';
import '../../state/providers.dart';

/// Which product a connected device is. [unknown] means neither the V64
/// handshake nor the ARDMX4 name-prefix fallback recognized it.
enum DeviceType { ardmx4, ardmxEvo, ardmxOne, unknown }

/// Tells an ARDMX4 (Mega), ARDMX One and ARDMX EVO apart after a connection
/// is established, so the right screen tree can be shown — see [identify]
/// for the two-tier strategy (handshake, then name fallback) — and whether
/// the device requires a connection PIN (see [requiresPin], [verifyPin]).
///
/// Deliberately does not run itself on connect: the app never auto-connects
/// (see [BluetoothConnectionService]/SplashScreen), so nothing should
/// auto-identify either — whoever drives the manual connect (currently only
/// SplashScreen) calls [identify] explicitly once connected.
class DeviceIdentificationService extends Notifier<DeviceType?> {
  static const _identifyVIndex = 64;
  static const _pinVerifyVIndex = 73;
  static const _pinSetVIndex = 74;
  static const _pinResetVIndex = 75;
  static const _identifyTimeout = Duration(seconds: 2);
  static const _cacheKeyPrefix = 'device_type_';

  /// Set by the most recent [identify] call — whether the device asked for
  /// a PIN before it'll answer anything else. Deliberately re-checked fresh
  /// on every [identify] call (never read from the type cache below): a PIN
  /// requirement can change at any time (the owner sets/clears one from
  /// Configuració), and this is the one thing here that actually gates
  /// access, so it must never be stale.
  bool requiresPin = false;

  /// Set by the most recent [identify] call, only when [DeviceType.ardmxOne]
  /// — the major version parsed from the V64 handshake's `firmware` semver
  /// string (e.g. "2.0.0" → 2). `null` when unparseable/missing, or when the
  /// last identified device wasn't an ARDMX One at all. Deliberately never
  /// cached (same reasoning as [requiresPin]): a stale value here would
  /// misroute a real device to the wrong screen tree. Callers should treat
  /// anything other than `>= 2` as v1 — the conservative default, since real
  /// ARDMX One v1 units in the field are frozen and must always land on the
  /// v1 screens they've always used, even if this can't be determined for
  /// some reason (`tipus` alone doesn't distinguish v1 from v2, both report
  /// "ARDMX_ONE" — see ardmx-one-firmware/src/main.cpp's buildIdentifyJson()).
  int? ardmxOneMajorVersion;

  @override
  DeviceType? build() => null;

  /// Identifies the currently connected device and refreshes [requiresPin]/
  /// [ardmxOneMajorVersion]. Always performs the V64 handshake (never skips
  /// it on a cached-type hit like an earlier version of this class did) —
  /// harmless in practice since this app is BLE-only and both ARDMX One/EVO
  /// firmware always answer V64 promptly; the cached MAC→type association is
  /// only a fallback for when the handshake itself fails (falls back further
  /// still to the ARDMX4 name-prefix heuristic, for the frozen Mega
  /// firmware, which never answers V64 — see firmware/ardmx_one/src/main.cpp
  /// for the ARDMX One side, which does).
  Future<DeviceType> identify() async {
    final connection = ref.read(bluetoothConnectionServiceProvider);
    final address = connection.deviceAddress;

    final json = await _requestIdentifyJson();
    DeviceType result;
    if (json != null) {
      result = _parseType(json);
      requiresPin = _parsePinRequired(json);
      ardmxOneMajorVersion =
          result == DeviceType.ardmxOne ? _parseMajorVersion(json) : null;
    } else {
      requiresPin = false;
      ardmxOneMajorVersion = null;
      result = (address != null ? await _readCache(address) : null) ??
          _nameFallback(connection.deviceName);
    }

    state = result;
    if (address != null && result != DeviceType.unknown) {
      await _writeCache(address, result);
    }
    return result;
  }

  /// Sends [pin] (already validated to be 4 digits by the caller's input
  /// field) for verification — true if the device accepted it. The
  /// firmware ignores every other V/T index until this succeeds once per
  /// connection (see main.cpp's `gated` check), so nothing else in the app
  /// should be attempted before this returns true.
  Future<bool> verifyPin(String pin) async {
    final result = await _writeAndAwaitReply(_pinVerifyVIndex, pin);
    return result == 'OK';
  }

  /// Sets a new PIN (Configuració screens) — only takes effect device-side
  /// if already authenticated (or no PIN was set yet), same rule as any
  /// other write while gated.
  Future<bool> setPin(String pin) async {
    final ok = await _writeAndAwaitReply(_pinSetVIndex, pin) == 'OK';
    if (ok) requiresPin = true;
    return ok;
  }

  /// Clears the device's PIN entirely (back to "no PIN") — the firmware
  /// always accepts this regardless of authentication state, by design
  /// (see main.cpp) — this is both the in-Configuració "treure PIN" action
  /// and the "Restablir PIN" recovery path reached via long-press on the
  /// Splash logo, for when the PIN itself is forgotten.
  Future<bool> resetPin() async {
    final ok = await _writeAndAwaitReply(_pinResetVIndex, '1') == 'OK';
    if (ok) requiresPin = false;
    return ok;
  }

  Future<String?> _writeAndAwaitReply(int index, String value) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> subscription;

    subscription = protocol.updates.listen((update) {
      if (update is VirtuinoTUpdate &&
          update.index == index &&
          !completer.isCompleted) {
        completer.complete(update.text);
      }
    });

    protocol.writeText(index, value);
    final result = await completer.future
        .timeout(_identifyTimeout, onTimeout: () => null)
        .catchError((Object error) {
          debugPrint('DeviceIdentificationService: V$index reply error: $error');
          return null;
        });
    await subscription.cancel();
    return result;
  }

  Future<String?> _requestIdentifyJson() async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> subscription;

    subscription = protocol.updates.listen((update) {
      if (update is VirtuinoTUpdate &&
          update.index == _identifyVIndex &&
          !completer.isCompleted) {
        completer.complete(update.text);
      }
    });

    protocol.requestT(_identifyVIndex);
    final json = await completer.future
        .timeout(_identifyTimeout, onTimeout: () => null)
        .catchError((Object error) {
          debugPrint('DeviceIdentificationService: identify error: $error');
          return null;
        });
    await subscription.cancel();
    return json;
  }

  DeviceType _parseType(String json) {
    try {
      final doc = jsonDecode(json) as Map<String, dynamic>;
      return switch (doc['tipus']) {
        'ARDMX_ONE' => DeviceType.ardmxOne,
        'ARDMX_EVO' => DeviceType.ardmxEvo,
        'ARDMX4' => DeviceType.ardmx4,
        _ => DeviceType.unknown,
      };
    } catch (error) {
      debugPrint('DeviceIdentificationService: malformed V64 JSON: $error');
      return DeviceType.unknown;
    }
  }

  bool _parsePinRequired(String json) {
    try {
      final doc = jsonDecode(json) as Map<String, dynamic>;
      return doc['pin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Parses just the major version out of the `firmware` semver string
  /// (e.g. "2.0.0" → 2) — `null` on anything unparseable, which callers
  /// must treat as v1 (see [ardmxOneMajorVersion]'s own doc).
  int? _parseMajorVersion(String json) {
    try {
      final doc = jsonDecode(json) as Map<String, dynamic>;
      final firmware = doc['firmware'];
      if (firmware is! String) return null;
      return int.tryParse(firmware.split('.').first);
    } catch (_) {
      return null;
    }
  }

  // No prefix ambiguity between these two (unlike the old "ARDMX4EVO"
  // naming, which shared a prefix with the Mega's "ARDMX4") — order doesn't
  // matter here, but kept in the same order as [_parseType] for consistency.
  DeviceType _nameFallback(String? deviceName) {
    final name = deviceName ?? '';
    if (name.startsWith('ARDMXEVO')) return DeviceType.ardmxEvo;
    if (name.startsWith('ARDMX4')) return DeviceType.ardmx4;
    return DeviceType.unknown;
  }

  Future<DeviceType?> _readCache(String address) async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString('$_cacheKeyPrefix$address')) {
      'ardmxOne' => DeviceType.ardmxOne,
      'ardmxEvo' => DeviceType.ardmxEvo,
      'ardmx4' => DeviceType.ardmx4,
      _ => null,
    };
  }

  Future<void> _writeCache(String address, DeviceType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cacheKeyPrefix$address', type.name);
  }
}

final deviceIdentificationServiceProvider =
    NotifierProvider<DeviceIdentificationService, DeviceType?>(
      DeviceIdentificationService.new,
    );
