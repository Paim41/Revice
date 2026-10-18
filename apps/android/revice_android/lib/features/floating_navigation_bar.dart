import 'package:flutter/material.dart';

/// Scaffold reserves this bar's space, so the last page item stays reachable.
class ReviceFloatingNavigationBar extends StatelessWidget {
  const ReviceFloatingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.reduceMotion = false,
  });
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final disableMotion =
        reduceMotion || MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111914),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFF29372D)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              height: 72,
              animationDuration: disableMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.devices_rounded),
                  label: 'Devices',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_rounded),
                  label: 'Insights',
                ),
                NavigationDestination(
                  icon: Icon(Icons.notifications_none_rounded),
                  label: 'Activity',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
