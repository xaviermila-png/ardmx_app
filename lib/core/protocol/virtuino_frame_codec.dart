import 'virtuino_update.dart';

/// Extracts complete `!Vxx=value$` / `!Txx=text$` frames out of a raw,
/// chunk-at-a-time byte stream from the Bluetooth Classic SPP connection.
///
/// A single physical read may contain a partial frame, one complete frame,
/// or several frames concatenated together (the Arduino sends batches like
/// `!V14=23.78$!T61=Playing$`), so frame boundaries never line up with chunk
/// boundaries. This class is pure logic (no I/O) so it can be unit tested in
/// isolation from the Bluetooth transport.
class VirtuinoFrameCodec {
  VirtuinoFrameCodec({this.maxBufferLength = 4096});

  /// Safety cap: if the buffer grows past this without ever finding a
  /// closing `$`, it is dropped. Guards against a corrupted link filling
  /// memory indefinitely.
  final int maxBufferLength;

  static final RegExp _framePattern = RegExp(r'^([VT])(\d+)=(.*)$');

  String _buffer = '';

  /// Feeds raw bytes from the connection's input stream (the protocol is
  /// pure ASCII) and returns any complete frames decoded as a result.
  List<VirtuinoUpdate> addBytes(List<int> bytes) {
    return addChunk(String.fromCharCodes(bytes));
  }

  /// Feeds a chunk of text and returns any complete frames decoded as a
  /// result. Exposed separately from [addBytes] so tests can work with
  /// plain strings.
  List<VirtuinoUpdate> addChunk(String chunk) {
    _buffer += chunk;
    final updates = <VirtuinoUpdate>[];

    while (true) {
      final start = _buffer.indexOf('!');
      if (start == -1) {
        _buffer = '';
        break;
      }
      final end = _buffer.indexOf(r'$', start);
      if (end == -1) {
        if (start > 0) {
          _buffer = _buffer.substring(start);
        }
        break;
      }
      final body = _buffer.substring(start + 1, end);
      _buffer = _buffer.substring(end + 1);
      final update = _parseFrame(body);
      if (update != null) {
        updates.add(update);
      }
    }

    if (_buffer.length > maxBufferLength) {
      _buffer = '';
    }

    return updates;
  }

  /// Indices >= this are the Arduino's special-cased text pins.
  static const _textPinStart = 61;

  VirtuinoUpdate? _parseFrame(String body) {
    final match = _framePattern.firstMatch(body);
    if (match == null) return null;

    final kind = match.group(1)!;
    final index = int.tryParse(match.group(2)!);
    final rawValue = match.group(3)!;
    if (index == null) return null;

    // The Arduino sketch's onReceived/onRequested only ever check
    // `variableType=='V'` — text pins 61-63 are NOT sent with a literal
    // `T` prefix, they are `V61`/`V62`/`V63` (indices past the 60-slot V[]
    // array bound), special-cased to return text1/text2/text3 instead of a
    // number. So `!V62=...$` carrying non-numeric text (e.g. the firmware
    // version) is the real wire format, not `!T62=...$` — the `T` kind is
    // kept here only defensively in case it's ever legitimately used.
    if (kind == 'V' && index >= _textPinStart) {
      return VirtuinoTUpdate(index, rawValue);
    }

    if (kind == 'V') {
      final value = double.tryParse(rawValue);
      if (value == null) return null;
      return VirtuinoVUpdate(index, value);
    }
    return VirtuinoTUpdate(index, rawValue);
  }
}
