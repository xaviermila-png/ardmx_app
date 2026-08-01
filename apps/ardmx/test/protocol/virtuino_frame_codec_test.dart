import 'dart:convert';

import 'package:ardmx/core/protocol/virtuino_frame_codec.dart';
import 'package:ardmx/core/protocol/virtuino_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VirtuinoFrameCodec', () {
    test('decodes a single complete frame in one chunk', () {
      final codec = VirtuinoFrameCodec();
      final updates = codec.addChunk('!V14=23.78\$');

      expect(updates, hasLength(1));
      final update = updates.single as VirtuinoVUpdate;
      expect(update.index, 14);
      expect(update.value, 23.78);
    });

    test('decodes a frame split across two chunks', () {
      final codec = VirtuinoFrameCodec();

      final first = codec.addChunk('!V14=23.7');
      expect(first, isEmpty);

      final second = codec.addChunk('8\$');
      expect(second, hasLength(1));
      final update = second.single as VirtuinoVUpdate;
      expect(update.index, 14);
      expect(update.value, 23.78);
    });

    test('decodes multiple frames concatenated in a single chunk', () {
      final codec = VirtuinoFrameCodec();
      final updates = codec.addChunk('!V14=23.78\$!T61=Playing\$!V16=20\$');

      expect(updates, hasLength(3));
      expect((updates[0] as VirtuinoVUpdate).index, 14);
      expect((updates[1] as VirtuinoTUpdate).text, 'Playing');
      expect((updates[2] as VirtuinoVUpdate).value, 20.0);
    });

    test('handles a frame split mid-way through a multi-frame chunk', () {
      final codec = VirtuinoFrameCodec();

      final first = codec.addChunk('!V14=23.78\$!T61=Play');
      expect(first, hasLength(1));
      expect((first.single as VirtuinoVUpdate).index, 14);

      final second = codec.addChunk('ing\$');
      expect(second, hasLength(1));
      expect((second.single as VirtuinoTUpdate).text, 'Playing');
    });

    test('ignores noise before the first frame start', () {
      final codec = VirtuinoFrameCodec();
      final updates = codec.addChunk('garbage!V9=3\$');

      expect(updates, hasLength(1));
      expect((updates.single as VirtuinoVUpdate).index, 9);
    });

    test('drops a malformed frame body without throwing', () {
      final codec = VirtuinoFrameCodec();
      final updates = codec.addChunk('!not-a-frame\$!V9=3\$');

      expect(updates, hasLength(1));
      expect((updates.single as VirtuinoVUpdate).index, 9);
    });

    test('resets the buffer once it exceeds the safety cap', () {
      final codec = VirtuinoFrameCodec(maxBufferLength: 10);
      final updates = codec.addChunk('!V1=${'1' * 20}'); // no closing $

      expect(updates, isEmpty);
      // A frame sent after the cap reset should still decode correctly.
      final recovered = codec.addChunk('!V2=5\$');
      expect(recovered, hasLength(1));
      expect((recovered.single as VirtuinoVUpdate).index, 2);
    });

    test(
      'treats V-prefixed frames at text-pin indices (61-63) as text, '
      'not numbers — the Arduino sketch only ever uses the V prefix, never '
      'a literal T, even for the text pins',
      () {
        final codec = VirtuinoFrameCodec();
        final updates = codec.addChunk('!V62=V4.15\$');

        expect(updates, hasLength(1));
        final update = updates.single as VirtuinoTUpdate;
        expect(update.index, 62);
        expect(update.text, 'V4.15');
      },
    );

    test('decodes bytes via addBytes using ASCII codes', () {
      final codec = VirtuinoFrameCodec();
      final updates = codec.addBytes('!V11=3\$'.codeUnits);

      expect(updates, hasLength(1));
      expect((updates.single as VirtuinoVUpdate).index, 11);
      expect((updates.single as VirtuinoVUpdate).value, 3.0);
    });

    test('decodes multi-byte UTF-8 characters (e.g. Catalan "ç")', () {
      final codec = VirtuinoFrameCodec();
      final updates = codec.addBytes(utf8.encode('!V68=Pessebre de Begues\$'));

      expect(updates, hasLength(1));
      expect(
        (updates.single as VirtuinoTUpdate).text,
        'Pessebre de Begues',
      );
    });

    test(
      'decodes a multi-byte UTF-8 character split across two chunks '
      '(confirmed on hardware to corrupt "ç" into "Ã§" before this fix)',
      () {
        final codec = VirtuinoFrameCodec();
        // "ç" is 0xC3 0xA7 in UTF-8 — split the two bytes across chunks.
        final bytes = utf8.encode('!V69=començant\$');
        final splitPoint = bytes.indexOf(0xC3) + 1;

        final first = codec.addBytes(bytes.sublist(0, splitPoint));
        expect(first, isEmpty);

        final second = codec.addBytes(bytes.sublist(splitPoint));
        expect(second, hasLength(1));
        expect((second.single as VirtuinoTUpdate).text, 'començant');
      },
    );
  });
}
