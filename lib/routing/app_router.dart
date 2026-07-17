import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/v_map.dart';
import '../features/ardmx_one/ardmx_one_screen.dart';
import '../features/credits/credits_screen.dart';
import '../features/cycle_programming/cycle_programming_screen.dart';
import '../features/debug/debug_screen.dart';
import '../features/main_menu/main_menu_screen.dart';
import '../features/parameters/parameters_screen.dart';
import '../features/rgb_wheel/rgb_wheel_screen.dart';
import '../features/scene_channels/scene_channels_screen.dart';
import '../features/splash/splash_screen.dart';
import '../state/providers.dart';

class AppRoutes {
  const AppRoutes._();

  static const splash = '/splash';
  static const mainMenu = '/main-menu';
  static const ardmxOne = '/ardmx-one';
  static const sceneChannels = '/scenes';
  static const rgbWheel = '/rgb-wheel';
  static const cycleProgramming = '/cycle-programming';
  static const parameters = '/parameters';
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
    cycleProgramming: AppScreen.cycleProgramming,
    mainMenu: AppScreen.mainMenu,
    parameters: AppScreen.parameters,
    sceneChannels: AppScreen.sceneChannels,
    rgbWheel: AppScreen.rgbWheel,
    credits: AppScreen.credits,
  };

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = switch (settings.name) {
      mainMenu => (BuildContext context) => const MainMenuScreen(),
      ardmxOne => (BuildContext context) => const ArdmxOneScreen(),
      sceneChannels => (BuildContext context) => const SceneChannelsScreen(),
      rgbWheel => (BuildContext context) => const RgbWheelScreen(),
      cycleProgramming => (BuildContext context) =>
          const CycleProgrammingScreen(),
      parameters => (BuildContext context) => const ParametersScreen(),
      credits => (BuildContext context) => const CreditsScreen(),
      debug => (BuildContext context) => const DebugScreen(),
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
