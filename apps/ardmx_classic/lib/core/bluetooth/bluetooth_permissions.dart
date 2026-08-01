import 'package:permission_handler/permission_handler.dart';

/// This app only reads already-bonded devices and connects to one of them —
/// it never performs active scanning/discovery of new devices itself, so
/// location permissions are never needed.
///
/// We *do* request `BLUETOOTH_SCAN` here even though our own code never
/// scans: the `flutter_blue_classic` plugin's native `connect()`
/// implementation unconditionally requests `BLUETOOTH_CONNECT` +
/// `BLUETOOTH_SCAN` internally on Android 12+ (API 31+), and has a bug where
/// it checks the (asynchronous) permission result synchronously right after
/// firing the request — if the permission isn't already granted, it falls
/// through and replies to the method channel `Result` twice once the real
/// async grant/deny arrives, crashing the whole app with `IllegalStateException:
/// Reply already submitted`. Pre-granting both permissions before ever
/// calling `connect()` makes the plugin's internal check take its
/// already-granted synchronous fast path, avoiding the buggy async branch
/// entirely. Confirmed via a real crash on a physical Android 12 device.
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
