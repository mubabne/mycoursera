import 'package:flutter/material.dart';

import 'courses_page.dart';
import 'progress_page.dart';
import 'today_page.dart';
import 'tutor_page.dart';

/// Navigation: a side rail on wide screens (web), a bottom bar on narrow ones (phone).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.today_outlined, Icons.today, 'Today'),
    (Icons.school_outlined, Icons.school, 'Courses'),
    (Icons.chat_bubble_outline, Icons.chat_bubble, 'Tutor'),
    (Icons.insights_outlined, Icons.insights, 'Progress'),
  ];

  Widget _page() => switch (_index) {
        0 => const TodayPage(),
        1 => const CoursesPage(),
        2 => const TutorPage(),
        _ => const ProgressPage(),
      };

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    // A new key per tab makes each page reload its data when you switch to it.
    final page = KeyedSubtree(key: ValueKey(_index), child: _page());
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -0.85,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 16),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.school_rounded, color: Theme.of(context).colorScheme.onPrimary),
                    ),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            ),
          );
        }
        return Scaffold(
          body: page,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
            ],
          ),
        );
      },
    );
  }
}
