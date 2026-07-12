import 'dart:async';

import 'virtuino_frame_codec.dart';
import 'virtuino_update.dart';

/// Encodes/decodes the `!Vxx=value$` wire protocol and exposes it as a
/// stream of updates plus a handful of write helpers.
///
/// There is deliberately no request/response correlation: the protocol has
/// no sequence IDs and the Arduino sketch cannot change, so every incoming
/// frame (solicited or not) is treated uniformly as a broadcast state
/// update — this matches how the Arduino actually behaves (it pushes
/// updates like V14 continuously during playback, independent of what the
/// app asked for). [requestV]/[requestAll] are only meant to pull an
/// initial snapshot right after connecting; the reply arrives on [updates]
/// like any other push.
class VirtuinoProtocol {
  VirtuinoProtocol({required Stream<List<int>> input, required this.output}) {
    _subscription = input.listen(_onBytes);
  }

  /// Sends a raw, already-encoded string (e.g. `!V16=20$`) to the
  /// connection. No-ops silently if there is no active connection — callers
  /// never need to check connection state before writing.
  final void Function(String raw) output;

  final VirtuinoFrameCodec _codec = VirtuinoFrameCodec();
  final StreamController<VirtuinoUpdate> _updatesController =
      StreamController<VirtuinoUpdate>.broadcast();
  late final StreamSubscription<List<int>> _subscription;

  Stream<VirtuinoUpdate> get updates => _updatesController.stream;

  void _onBytes(List<int> bytes) {
    for (final update in _codec.addBytes(bytes)) {
      _updatesController.add(update);
    }
  }

  void send(String raw) => output(raw);

  void writeV(int index, num value) => send(_encodeV(index, value));

  /// Concatenates several writes into a single send, e.g.
  /// `!V11=3$!V16=20$` — used whenever a screen commits several related
  /// values together to minimize write count/latency over SPP.
  void writeBatch(Map<int, num> values) {
    if (values.isEmpty) return;
    send(values.entries.map((e) => _encodeV(e.key, e.value)).join());
  }

  void requestV(int index) => send('!V$index=?\$');

  /// Text pins (T61-T63) are not pushed proactively by the Arduino the way
  /// V-values are — they only reply once explicitly asked with `?`, so
  /// anything reading them (e.g. the T62 firmware version) must call this.
  ///
  /// Despite the "T" naming (matching the Virtuino app-side convention),
  /// the Arduino sketch's onRequested only ever checks `variableType=='V'`
  /// — text pins are requested as `!V61=?$`/`!V62=?$`/`!V63=?$`, indices
  /// past the 60-slot V[] array bound that the sketch special-cases to
  /// return text instead of a number. A literal `!T62=?$` is silently
  /// ignored by the Arduino (confirmed on real hardware).
  void requestT(int index) => send('!V$index=?\$');

  void requestAll(List<int> indices) {
    if (indices.isEmpty) return;
    send(indices.map((i) => '!V$i=?\$').join());
  }

  String _encodeV(int index, num value) =>
      '!V$index=${_formatValue(value)}\$';

  String _formatValue(num value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _updatesController.close();
  }
}
