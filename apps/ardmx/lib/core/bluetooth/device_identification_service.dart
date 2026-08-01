import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/virtuino_update.dart';
import '../../state/providers.dart';

/// Which product a connected device is. [unknown] means neither the V64
/// handshake nor the ARDMX4 name-prefix fallback recognized it.
enum DeviceType { ardmx4, ardmx4Evo, ardmxOne, unknown }

/// Tells an ARDMX4 (Mega) and an ARDMX One (ESP32) apart after a connection
/// is established, so the right screen tree can be shown — see
/// [identify] for the two-tier strategy (handshake, then name fallback).
///
/// Deliberately does not run itself on connect: the app never auto-connects
/// (see [BluetoothConnectionService]/SplashScreen), so nothing should
/// auto-identify either — whoever drives the manual connect (currently only
/// SplashScreen) calls [identify] explicitly once connected.
class DeviceIdentificationService extends Notifier<DeviceType?> {
  static const _identifyVIndex = 64;
  static const _identifyTimeout = Duration(seconds: 2);
  static const _cacheKeyPrefix = 'device_type_';

  @override
  DeviceType? build() => null;

  /// Identifies the currently connected device. Checks the cached
  /// MAC→type association first (see class doc); only when that's missing
  /// does it perform the V64 handshake, falling back to the ARDMX4
  /// name-prefix heuristic if the handshake times out (for the ARDMX4 Mega
  /// firmware, which is frozen and doesn't answer V64 — see
  /// firmware/ardmx_one/src/main.cpp for the ARDMX One side, which does).
  Future<DeviceType> identify() async {
    final connection = ref.read(bluetoothConnectionServiceProvider);
    final address = connection.deviceAddress;

    if (address != null) {
      final cached = await _readCache(address);
      if (cached != null) {
        state = cached;
        return cached;
      }
    }

    final json = await _requestIdentifyJson();
    final result = json != null
        ? _parseType(json)
        : _nameFallback(connection.deviceName);

    state = result;
    if (address != null && result != DeviceType.unknown) {
      await _writeCache(address, result);
    }
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
        'ARDMX4_EVO' => DeviceType.ardmx4Evo,
        'ARDMX4' => DeviceType.ardmx4,
        _ => DeviceType.unknown,
      };
    } catch (error) {
      debugPrint('DeviceIdentificationService: malformed V64 JSON: $error');
      return DeviceType.unknown;
    }
  }

  // Checked in order of specificity: the EVO's Bluetooth name
  // ("ARDMX4EVO...") also starts with "ARDMX4", so the Mega's plain prefix
  // must be checked second or every EVO whose handshake happened to fail
  // would be silently misclassified as a Mega.
  DeviceType _nameFallback(String? deviceName) {
    final name = deviceName ?? '';
    if (name.startsWith('ARDMX4EVO')) return DeviceType.ardmx4Evo;
    if (name.startsWith('ARDMX4')) return DeviceType.ardmx4;
    return DeviceType.unknown;
  }

  Future<DeviceType?> _readCache(String address) async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString('$_cacheKeyPrefix$address')) {
      'ardmxOne' => DeviceType.ardmxOne,
      'ardmx4Evo' => DeviceType.ardmx4Evo,
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
