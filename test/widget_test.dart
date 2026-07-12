// Basic smoke test for the app's routing table. A full widget-tree boot
// test isn't used here because SplashScreen kicks off real platform-channel
// calls (permission_handler, flutter_blue_classic) from initState, which
// aren't available in the widget-test environment.

import 'package:ardmx4_app/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onGenerateRoute builds a MaterialPageRoute for every known route', () {
    for (final name in AppRoutes.screenForRoute.keys) {
      final route = AppRoutes.onGenerateRoute(RouteSettings(name: name));
      expect(route, isA<MaterialPageRoute<dynamic>>());
      expect(route.settings.name, name);
    }
  });

  test('an unknown route name falls back to Splash instead of throwing', () {
    final route = AppRoutes.onGenerateRoute(
      const RouteSettings(name: '/does-not-exist'),
    );
    expect(route, isA<MaterialPageRoute<dynamic>>());
  });
}
