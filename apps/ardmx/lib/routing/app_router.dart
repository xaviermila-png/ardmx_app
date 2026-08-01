import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/v_map.dart';
import '../features/ardmx4_evo/ardmx4_evo_cycle_programming_screen.dart';
import '../features/ardmx4_evo/ardmx4_evo_main_menu_screen.dart';
import '../features/ardmx4_evo/ardmx4_evo_parameters_screen.dart';
import '../features/ardmx4_evo/ardmx4_evo_scene_channels_screen.dart';
import '../features/ardmx4_evo/ardmx4_evo_system_config_screen.dart';
import '../features/ardmx_one/ardmx_one_config_screen.dart';
import '../features/ardmx_one/ardmx_one_screen.dart';
import '../features/ardmx_one/ardmx_one_system_config_screen.dart';
import '../features/credits/credits_screen.dart';
import '../features/debug/debug_screen.dart';
import '../features/rgb_wheel/rgb_wheel_screen.dart';
import '../features/splash/splash_screen.dart';
import '../state/providers.dart';

class AppRoutes {
  const AppRoutes._();

  static const splash = '/splash';
  static const ardmxOne = '/ardmx-one';
  static const ardmxOneConfig = '/ardmx-one-config';
  static const ardmxOneSystemConfig = '/ardmx-one-system-config';
  static const rgbWheel = '/rgb-wheel';
  static const ardmx4EvoMainMenu = '/ardmx4-evo-main-menu';
  static const ardmx4EvoSceneChannels = '/ardmx4-evo-scenes';
  static const ardmx4EvoCycleProgramming = '/ardmx4-evo-cycle-programming';
  static const ardmx4EvoParameters = '/ardmx4-evo-parameters';
  static const ardmx4EvoSystemConfig = '/ardmx4-evo-system-config';
  static const credits = '/credits';

  /// Not part of the production 7-screen flow — a temporary screen (phase
  /// 2) for validating the Bluetooth/protocol stack against the real
  /// Arduino, reachable from a long-press on the Splash logo. Not in
  /// [screenForRoute] since it has no V[50] meaning.
  static const debug = '/debug';

  /// Route name -> the V[50] value that must be written when that route
  /// becomes current.
  static const Map<String, AppScreen> screenForRoute = {
    splash: AppScreen.initial,
    rgbWheel: AppScreen.rgbWheel,
    credits: AppScreen.credits,
    ardmx4EvoMainMenu: AppScreen.mainMenu,
    ardmx4EvoSceneChannels: AppScreen.sceneChannels,
    ardmx4EvoCycleProgramming: AppScreen.cycleProgramming,
    ardmx4EvoParameters: AppScreen.parameters,
    // The firmware has no dedicated V50 value for this screen (it doesn't
    // exist on the Mega, whose V50 enum this mirrors) — mapped to the same
    // value as Paràmetres so `ConfiguracioParametres()` (gated by V50==4)
    // keeps running while the user is here, since Reset/BT name/pessebre
    // live under this screen. Without an entry here at all, V50 would just
    // freeze at whatever the previous screen left it at instead — usually
    // Paràmetres anyway (the only way to reach this screen), but leaving it
    // implicit was fragile. See confirmReset()'s doc for the actual reset
    // race this screen's testing uncovered.
    ardmx4EvoSystemConfig: AppScreen.parameters,
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
      ardmx4EvoMainMenu =>
        (BuildContext context) => const Ardmx4EvoMainMenuScreen(),
      ardmx4EvoSceneChannels =>
        (BuildContext context) => const Ardmx4EvoSceneChannelsScreen(),
      ardmx4EvoCycleProgramming =>
        (BuildContext context) => const Ardmx4EvoCycleProgrammingScreen(),
      ardmx4EvoParameters =>
        (BuildContext context) => const Ardmx4EvoParametersScreen(),
      ardmx4EvoSystemConfig =>
        (BuildContext context) => const Ardmx4EvoSystemConfigScreen(),
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
