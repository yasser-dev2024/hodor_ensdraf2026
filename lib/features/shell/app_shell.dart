import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../dashboard/dashboard_screen.dart';
import '../more/more_screen.dart';
import '../reports/reports_screen.dart';
import '../scanner/scan_landing_screen.dart';
import '../students/students_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final pages = [
      DashboardScreen(onStartScan: () => setState(() => _index = 1)),
      const ScanLandingScreen(),
      const StudentsScreen(),
      const ReportsScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          if (value == 1 && !user.role.canScan) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('لا تملك صلاحية تسجيل الحضور.')),
            );
            return;
          }
          setState(() => _index = value);
        },
        destinations: const [
          NavigationDestination(
            key: ValueKey('nav_home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            key: ValueKey('nav_scan'),
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner_rounded),
            label: 'المسح',
          ),
          NavigationDestination(
            key: ValueKey('nav_students'),
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'الطلاب',
          ),
          NavigationDestination(
            key: ValueKey('nav_reports'),
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'التقارير',
          ),
          NavigationDestination(
            key: ValueKey('nav_more'),
            icon: Icon(Icons.more_horiz_rounded),
            label: 'المزيد',
          ),
        ],
      ),
    );
  }
}
