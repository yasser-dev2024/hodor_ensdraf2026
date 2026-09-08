import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/school_day_formatter.dart';
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

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _activeAttendanceDaySetting = 'active_attendance_day';

  int _index = 0;
  Timer? _dayRolloverTimer;
  late String _observedDay;
  bool _checkingDayRollover = false;

  @override
  void initState() {
    super.initState();
    _observedDay = SchoolDayFormatter.key();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_checkDayRollover(force: true));
    });
    _scheduleDayRollover();
  }

  @override
  void dispose() {
    _dayRolloverTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkDayRollover());
      _scheduleDayRollover();
    }
  }

  void _scheduleDayRollover() {
    _dayRolloverTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    _dayRolloverTimer = Timer(nextDay.difference(now), () async {
      await _checkDayRollover();
      if (mounted) _scheduleDayRollover();
    });
  }

  Future<void> _checkDayRollover({bool force = false}) async {
    if (_checkingDayRollover || !mounted) return;
    final today = SchoolDayFormatter.key();
    final dayChanged = today != _observedDay;
    if (!force && !dayChanged) return;
    _checkingDayRollover = true;
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;
      final settings = ref.read(settingsRepositoryProvider);
      final previouslyActiveDate = await settings.get(
        _activeAttendanceDaySetting,
      );
      final markUnregisteredPresent =
          await settings.get('mark_unregistered_present_on_close') != 'false';
      final closedDates = await ref
          .read(attendanceRepositoryProvider)
          .autoClosePreviousOpenDays(
            userId: user.id,
            markUnregisteredPresent: markUnregisteredPresent,
            previouslyActiveDate: previouslyActiveDate,
          );
      if (!mounted) return;
      await settings.set(
        _activeAttendanceDaySetting,
        user.role.canEditAttendance ? today : '',
      );
      if (!mounted) return;
      _observedDay = today;
      if (dayChanged || closedDates.isNotEmpty) refreshData(ref);
      if (closedDates.isNotEmpty) {
        final message = closedDates.length == 1
            ? 'تم إغلاق يوم ${closedDates.single} تلقائيًا وبدء يوم جديد.'
            : 'تم إغلاق ${closedDates.length} أيام سابقة تلقائيًا وبدء اليوم الجديد.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر إغلاق اليوم السابق تلقائيًا. لم تُفقد أي بيانات: $error',
            ),
          ),
        );
      }
    } finally {
      _checkingDayRollover = false;
    }
  }

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
