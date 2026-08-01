import 'package:permission_handler/permission_handler.dart';

/// `BLUETOOTH_CONNECT` + `BLUETOOTH_SCAN` (Android 12+/API 31+ runtime
/// permissions) — both needed here since this app actively scans for BLE
/// devices (unlike the sibling Classic app, which only ever reads
/// already-bonded devices). Requested together and up front (before Splash
/// ever calls `startBleScan()`/`connect()`), matching a bug workaround
/// originally found necessary for `flutter_blue_classic`'s `connect()`
/// (crashed with `IllegalStateException: Reply already submitted` if the
/// permission wasn't already granted when it fired its own internal
/// request) — pre-granting is harmless and low-cost to keep doing here even
/// though this app no longer uses that plugin.
///
/// No location permission: `BLUETOOTH_SCAN` is declared with
/// `neverForLocation` in the manifest, valid on Android 12+ — this app's
/// fleet is all Android 12+, so no runtime location request is implemented
/// (see the manifest's own comment for what a pre-12 device would need).
class BluetoothPermissions {
  const BluetoothPermissions._();

  static const _permissions = [Permission.bluetoothConnect, Permission.bluetoothScan];

  /// Guards against two concurrent `.request()` calls: the Android
  /// permission_handler plugin throws `PlatformException` ("A request for
  /// permissions is already running") if a second request is fired while
  /// one is in flight — observed in practice when something triggers
  /// [ensureGranted] twice in quick succession during app startup. Callers
  /// racing each other simply await the same in-flight request instead.
  static Future<bool>? _pendingRequest;

  static Future<bool> ensureGranted() {
    final pending = _pendingRequest;
    if (pending != null) return pending;

    final request = _requestAll();
    _pendingRequest = request;
    request.whenComplete(() => _pendingRequest = null);
    return request;
  }

  static Future<bool> _requestAll() async {
    final statuses = await _permissions.request();
    return statuses.values.every((status) => status.isGranted);
  }

  static Future<bool> isGranted() async {
    for (final permission in _permissions) {
      if (!await permission.status.then((s) => s.isGranted)) return false;
    }
    return true;
  }

  static Future<bool> isPermanentlyDenied() async {
    for (final permission in _permissions) {
      if (await permission.status.then((s) => s.isPermanentlyDenied)) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> openSettings() => openAppSettings();
}
