import 'package:flutter/material.dart';

import 'desktop_tooltip.dart';

class DesktopMenuObserver extends NavigatorObserver {
  static const routeName = '/desktop-menu';
  static final _menus = <Route<dynamic>>{};

  static void dismissAll() {
    for (final route in _menus.toList().reversed) {
      route.navigator?.removeRoute(route);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == routeName || (route is PopupRoute && _menus.contains(previousRoute))) _menus.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _menus.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _menus.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _menus.remove(oldRoute);
    if (newRoute?.settings.name == routeName) _menus.add(newRoute!);
  }
}

Future<T?> showDesktopMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<PopupMenuEntry<T>> items,
}) {
  DesktopTooltip.dismissAll();
  DesktopMenuObserver.dismissAll();
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final anchor = overlay.globalToLocal(position);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(anchor & const Size(1, 1), Offset.zero & overlay.size),
    popUpAnimationStyle: AnimationStyle.noAnimation,
    routeSettings: const RouteSettings(name: DesktopMenuObserver.routeName),
    requestFocus: true,
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
    items: items,
  );
}
