import 'package:flutter/material.dart';
import '../core/theme/zen_colors.dart';
import '../state/zen_state.dart';
import 'home/home_screen.dart';
import 'calendar/calendar_screen.dart';
import 'insights/insights_screen.dart';
import 'profile/profile_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  final ZenState _state = ZenState();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _state.init();
    _state.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;

    return Scaffold(
      backgroundColor: t.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            state: _state,
            onNavigateToCalendar: () => setState(() => _currentIndex = 1),
            onNavigateToInsights: () => setState(() => _currentIndex = 2),
            onNavigateToProfile: () => setState(() => _currentIndex = 3),
          ),
          CalendarScreen(
            state: _state,
            onBack: () => setState(() => _currentIndex = 0),
          ),
          InsightsScreen(
            state: _state,
            onBack: () => setState(() => _currentIndex = 0),
          ),
          ProfileScreen(
            state: _state,
            onBack: () => setState(() => _currentIndex = 0),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.line, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(index: 0, current: _currentIndex, icon: Icons.wb_sunny_outlined, activeIcon: Icons.wb_sunny_rounded, label: 'Today', onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(index: 1, current: _currentIndex, icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_month_rounded, label: 'Days', onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(index: 2, current: _currentIndex, icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart_rounded, label: 'Insights', onTap: (i) => setState(() => _currentIndex = i)),
                _NavItem(index: 3, current: _currentIndex, icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Me', onTap: (i) => setState(() => _currentIndex = i)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final int current;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final void Function(int) onTap;

  const _NavItem({
    required this.index,
    required this.current,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    final selected = index == current;
    final color = selected ? t.ink : t.inkFaint;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

