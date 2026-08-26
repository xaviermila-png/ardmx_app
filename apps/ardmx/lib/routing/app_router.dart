import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/v_map.dart';
import '../features/ardmx_evo/ardmx_evo_cycle_programming_screen.dart';
import '../features/ardmx_evo/ardmx_evo_main_menu_screen.dart';
import '../features/ardmx_evo/ardmx_evo_parameters_screen.dart';
import '../features/ardmx_evo/ardmx_evo_scene_channels_screen.dart';
import '../features/ardmx_evo/ardmx_evo_system_config_screen.dart';
import '../features/ardmx_one/ardmx_one_config_screen.dart';
import '../features/ardmx_one/ardmx_one_screen.dart';
import '../features/ardmx_one/ardmx_one_system_config_screen.dart';
import '../features/ardmx_one_v2/ardmx_one_v2_cycle_programming_screen.dart';
import '../features/ardmx_one_v2/ardmx_one_v2_main_menu_screen.dart';
import '../features/ardmx_one_v2/ardmx_one_v2_parameters_screen.dart';
import '../features/ardmx_one_v2/ardmx_one_v2_scene_channels_screen.dart';
import '../features/ardmx_one_v2/ardmx_one_v2_system_config_screen.dart';
import '../features/credits/credits_screen.dart';
import '../features/debug/debug_screen.dart';
import '../features/rgb_wheel/rgb_wheel_screen.dart';
import '../features/simulacio/simulacio_screen.dart';
import '../features/splash/splash_screen.dart';
import '../state/providers.dart';

class AppRoutes {
  const AppRoutes._();

  static const splash = '/splash';
  static const ardmxOne = '/ardmx-one';
  static const ardmxOneConfig = '/ardmx-one-config';
  static const ardmxOneSystemConfig = '/ardmx-one-system-config';
  static const rgbWheel = '/rgb-wheel';
  static const ardmxEvoMainMenu = '/ardmx-evo-main-menu';
  static const ardmxEvoSceneChannels = '/ardmx-evo-scenes';
  static const ardmxEvoCycleProgramming = '/ardmx-evo-cycle-programming';
  static const ardmxEvoParameters = '/ardmx-evo-parameters';
  static const ardmxEvoSystemConfig = '/ardmx-evo-system-config';
  static const ardmxEvoSimulacio = '/ardmx-evo-simulacio';
  static const ardmxOneV2MainMenu = '/ardmx-one-v2-main-menu';
  static const ardmxOneV2SceneChannels = '/ardmx-one-v2-scenes';
  static const ardmxOneV2CycleProgramming = '/ardmx-one-v2-cycle-programming';
  static const ardmxOneV2Parameters = '/ardmx-one-v2-parameters';
  static const ardmxOneV2SystemConfig = '/ardmx-one-v2-system-config';
  static const ardmxOneV2Simulacio = '/ardmx-one-v2-simulacio';
  static const credits = '/credits';

  /// Offline navigation shortcut into a product's screen tree, reached via
  /// long-press on the Splash logo — not part of the production flow, and
  /// not in [screenForRoute] since it has no V[50] meaning of its own.
  static const debug = '/debug';

  /// Route name -> the V[50] value that must be written when that route
  /// becomes current.
  static const Map<String, AppScreen> screenForRoute = {
    splash: AppScreen.initial,
    rgbWheel: AppScreen.rgbWheel,
    credits: AppScreen.credits,
    ardmxEvoMainMenu: AppScreen.mainMenu,
    ardmxEvoSceneChannels: AppScreen.sceneChannels,
    ardmxEvoCycleProgramming: AppScreen.cycleProgramming,
    ardmxEvoParameters: AppScreen.parameters,
    // The firmware has no dedicated V50 value for this screen (it doesn't
    // exist on the Mega, whose V50 enum this mirrors) — mapped to the same
    // value as Paràmetres so `ConfiguracioParametres()` (gated by V50==4)
    // keeps running while the user is here, since Reset/BT name/pessebre
    // live under this screen. Without an entry here at all, V50 would just
    // freeze at whatever the previous screen left it at instead — usually
    // Paràmetres anyway (the only way to reach this screen), but leaving it
    // implicit was fragile. See confirmReset()'s doc for the actual reset
    // race this screen's testing uncovered.
    ardmxEvoSystemConfig: AppScreen.parameters,
    // Reuses Cicle's own V50 value — SimulacioScreen needs exactly the
    // same firmware-side gate Cicle() already runs under (Play/Pausa,
    // V12/V13, only get processed while V50==cycleProgramming) and has no
    // reactive behaviour of its own that would need a dedicated value.
    ardmxEvoSimulacio: AppScreen.cycleProgramming,
    ardmxOneV2MainMenu: AppScreen.mainMenu,
    ardmxOneV2SceneChannels: AppScreen.sceneChannels,
    ardmxOneV2CycleProgramming: AppScreen.cycleProgramming,
    ardmxOneV2Parameters: AppScreen.parameters,
    // Same reasoning as ardmxEvoSystemConfig above — no dedicated V50 value
    // of its own, mapped to Paràmetres so ConfiguracioParametres()-style
    // reactive polling keeps running (V41/V42 reset, Nom Bluetooth) while
    // this screen is open.
    ardmxOneV2SystemConfig: AppScreen.parameters,
    // Same reasoning as ardmxEvoSimulacio above.
    ardmxOneV2Simulacio: AppScreen.cycleProgramming,
  };

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = switch (settings.name) {
      ardmxOne => (BuildContext context) => const ArdmxOneScreen(),
      ardmxOneConfig => (BuildContext context) => const ArdmxOneConfigScreen(),
      ardmxOneSystemConfig =>
        (BuildContext context) => const ArdmxOneSystemConfigScreen(),
      rgbWheel => (BuildContext context) => const RgbWheelScreen(),
      credits => (BuildContext context) => const CreditsScreen(),
      debug => (BuildContext context) => const DebugScreen(),
      ardmxEvoMainMenu =>
        (BuildContext context) => const ArdmxEvoMainMenuScreen(),
      ardmxEvoSceneChannels =>
        (BuildContext context) => const ArdmxEvoSceneChannelsScreen(),
      ardmxEvoCycleProgramming =>
        (BuildContext context) => const ArdmxEvoCycleProgrammingScreen(),
      ardmxEvoParameters =>
        (BuildContext context) => const ArdmxEvoParametersScreen(),
      ardmxEvoSystemConfig =>
        (BuildContext context) => const ArdmxEvoSystemConfigScreen(),
      // V08 (One v2) vs VIndex.activeChannelsCount (EVO) — same distinction
      // ExportImportSection makes for the same reason (the One v2's own
      // channel-count index, unrelated to the EVO's V39/V40).
      ardmxEvoSimulacio => (BuildContext context) =>
          const SimulacioScreen(channelCountVIndex: VIndex.activeChannelsCount),
      ardmxOneV2MainMenu =>
        (BuildContext context) => const ArdmxOneV2MainMenuScreen(),
      ardmxOneV2SceneChannels =>
        (BuildContext context) => const ArdmxOneV2SceneChannelsScreen(),
      ardmxOneV2CycleProgramming =>
        (BuildContext context) => const ArdmxOneV2CycleProgrammingScreen(),
      ardmxOneV2Parameters =>
        (BuildContext context) => const ArdmxOneV2ParametersScreen(),
      ardmxOneV2SystemConfig =>
        (BuildContext context) => const ArdmxOneV2SystemConfigScreen(),
      ardmxOneV2Simulacio => (BuildContext context) =>
          const SimulacioScreen(channelCountVIndex: 8),
      _ => (BuildContext context) => const SplashScreen(),
    };
    return MaterialPageRoute(builder: builder, settings: settings);
  }
}

/// Mirrors Flutter's own navigation onto V[50]. The [Navigator] remains the
/// single source of truth for which screen is displayed — V50 is never read
/// back to drive navigation, only written as a side effect, because it
/// actively triggers Arduino-side behavior (`Escenes()`, `Cicle()`, ...),
/// not a passive mirror. Writes are fire-and-forget: if there is no
/// connection, [BluetoothConnectionService.send] silently drops them rather
/// than queueing, and there is no ack to wait for.
class ScreenMirrorObserver extends NavigatorObserver {
  ScreenMirrorObserver(this._ref);

  final WidgetRef _ref;
  AppScreen? _lastScreen;

  void _mirror(Route<dynamic>? route) {
    final name = route?.settings.name;
    final screen = name == null ? null : AppRoutes.screenForRoute[name];
    if (screen == null) return;
    _lastScreen = screen;
    // didPush/didPop/didReplace can fire synchronously while the Navigator
    // is still building its widget tree (e.g. during initial restoreState),
    // and Riverpod forbids mutating provider state mid-build. Defer the
    // actual write to just after the current frame finishes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ref.read(appStateProvider.notifier).setScreen(screen);
    });
  }

  /// Re-asserts the current route's V50 after a (re)connection, so the
  /// Arduino always learns the true current screen even if navigation
  /// happened while offline.
  void resyncCurrent() {
    final screen = _lastScreen;
    if (screen != null) {
      _ref.read(appStateProvider.notifier).setScreen(screen);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _mirror(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _mirror(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _mirror(newRoute);
}
