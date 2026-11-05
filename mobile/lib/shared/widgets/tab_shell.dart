import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/i18n.dart';
import 'common.dart';
import 'floating_nav.dart';

/// Lets screens inside a tab switch to another tab (e.g. a dashboard card opening "Bookings").
class TabSwitcher extends InheritedWidget {
  const TabSwitcher({super.key, required this.goTo, required super.child});

  final void Function(int tab) goTo;

  static void Function(int tab)? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabSwitcher>()?.goTo;

  @override
  bool updateShouldNotify(TabSwitcher oldWidget) => false;
}

/// Bottom-tab home for customers and merchants. Back goes to the previously opened tab; on the first tab it
/// asks before leaving the app.
class TabShell extends StatefulWidget {
  const TabShell({super.key, required this.pages, required this.items, this.onReady, this.aboveNav});

  final List<Widget> pages;
  final List<FloatingNavItem> items;

  /// Shown just above the bottom bar on every tab (the customer app's cart strip).
  final Widget? aboveNav;

  /// Called once after the first frame (update check, order alerts...).
  final void Function(BuildContext context)? onReady;

  @override
  State<TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<TabShell> {
  int _tab = 0;
  final List<int> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call(context);
    });
  }

  void _goTo(int tab) {
    if (tab == _tab) return;
    setState(() {
      _history.remove(tab);
      _history.add(_tab);
      _tab = tab;
    });
  }

  Future<void> _onBack() async {
    if (_history.isNotEmpty) {
      setState(() => _tab = _history.removeLast());
      return;
    }
    if (_tab != 0) {
      setState(() => _tab = 0);
      return;
    }
    HapticFeedback.mediumImpact();
    if (await confirm(context, tr('क्या आप ऐप बंद करना चाहते हैं?'), ok: tr('हाँ, बंद करें'))) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: TabSwitcher(
        goTo: _goTo,
        child: Scaffold(
          extendBody: true, // content scrolls under the floating bar
          body: IndexedStack(index: _tab, children: widget.pages),
          bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
            ?widget.aboveNav,
            FloatingNavBar(index: _tab, onTap: _goTo, items: widget.items),
          ]),
        ),
      ),
    );
  }
}
