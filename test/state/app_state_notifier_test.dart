import 'dart:async';

import 'package:ardmx4_app/core/constants/v_map.dart';
import 'package:ardmx4_app/core/protocol/virtuino_protocol.dart';
import 'package:ardmx4_app/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<List<int>> inputController;
  late List<String> sent;
  late ProviderContainer container;

  setUp(() {
    inputController = StreamController<List<int>>.broadcast();
    sent = [];
    container = ProviderContainer(
      overrides: [
        protocolProvider.overrideWith((ref) {
          final protocol = VirtuinoProtocol(
            input: inputController.stream,
            output: sent.add,
          );
          ref.onDispose(protocol.dispose);
          return protocol;
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(inputController.close);
  });

  test('applies an incoming V update to state', () async {
    container.read(appStateProvider); // subscribe
    inputController.add('!V16=20\$'.codeUnits);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appStateProvider).volume, 20);
  });

  test('applies an incoming T update to state', () async {
    container.read(appStateProvider);
    inputController.add('!T61=Playing\$'.codeUnits);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appStateProvider).t61, 'Playing');
  });

  test('setVolume writes to the protocol and applies optimistically', () {
    container.read(appStateProvider);
    container.read(appStateProvider.notifier).setVolume(15);

    expect(sent, ['!V${VIndex.volume}=15\$']);
    expect(container.read(appStateProvider).volume, 15);
  });

  test('setChannelColors batches a single write for all three channels', () {
    container.read(appStateProvider);
    container
        .read(appStateProvider.notifier)
        .setChannelColors(channel1: 255, channel2: 128, channel3: 0);

    expect(sent, hasLength(1));
    expect(sent.single, contains('V01=255'));
    expect(sent.single, contains('V02=128'));
    expect(sent.single, contains('V03=0'));
    expect(container.read(appStateProvider).channel1Value, 255);
    expect(container.read(appStateProvider).channel2Value, 128);
    expect(container.read(appStateProvider).channel3Value, 0);
  });

  test('setScreen writes the AppScreen.vValue and updates selectedScreen', () {
    container.read(appStateProvider);
    container
        .read(appStateProvider.notifier)
        .setScreen(AppScreen.sceneChannels);

    expect(sent, ['!V${VIndex.activeScreen}=5\$']);
    expect(container.read(appStateProvider).selectedScreen, 5);
  });
}
