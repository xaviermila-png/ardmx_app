import 'dart:convert';

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

  // '!' and '$' are single-byte ASCII (0x21/0x24). UTF-8 continuation and
  // lead bytes are always >= 0x80, so these delimiters can never appear as
  // part of a multi-byte character — searching for them at the byte level
  // (below) is always safe, even mid-character.
  static const int _bangByte = 0x21;
  static const int _dollarByte = 0x24;

  // Buffered as raw bytes, not a decoded String: text values (channel/scene
  // names, descriptions) can contain multi-byte UTF-8 characters (e.g. "ç" =
  // 0xC3 0xA7), and a chunk boundary can legitimately fall in the middle of
  // one. Decoding byte-by-byte as each chunk arrives (the previous
  // approach, via String.fromCharCodes) treated every byte as its own
  // Latin-1 code point and corrupted any such character into two garbled
  // ones (confirmed on hardware: "ç" arrived as "Ã§"). Buffering raw bytes
  // and only UTF-8-decoding once a complete frame (a full `!...$` span) has
  // arrived avoids ever decoding a split sequence.
  final List<int> _buffer = [];

  /// Feeds raw bytes from the connection's input stream and returns any
  /// complete frames decoded as a result.
  List<VirtuinoUpdate> addBytes(List<int> bytes) {
    _buffer.addAll(bytes);
    final updates = <VirtuinoUpdate>[];

    while (true) {
      final start = _buffer.indexOf(_bangByte);
      if (start == -1) {
        _buffer.clear();
        break;
      }
      final end = _buffer.indexOf(_dollarByte, start);
      if (end == -1) {
        if (start > 0) {
          _buffer.removeRange(0, start);
        }
        break;
      }
      final bodyBytes = _buffer.sublist(start + 1, end);
      _buffer.removeRange(0, end + 1);
      final body = utf8.decode(bodyBytes, allowMalformed: true);
      final update = _parseFrame(body);
      if (update != null) {
        updates.add(update);
      }
    }

    if (_buffer.length > maxBufferLength) {
      _buffer.clear();
    }

    return updates;
  }

  /// Feeds a chunk of text and returns any complete frames decoded as a
  /// result. Exposed separately from [addBytes] so tests can work with
  /// plain strings; re-encodes to UTF-8 bytes so both entry points share the
  /// exact same buffering/decoding logic.
  List<VirtuinoUpdate> addChunk(String chunk) => addBytes(utf8.encode(chunk));

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
