import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/school_day_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import '../../models/daily_preparation.dart';
import '../../models/period_report.dart';
import '../reports/daily_report_screen.dart';
import '../scanner/scanner_screen.dart';
import 'smart_preparation_section.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({required this.onStartScan, super.key});
  final VoidCallback onStartScan;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dataRevisionProvider);
    final user = ref.watch(currentUserProvider)!;
    final summaryFuture = ref.read(attendanceRepositoryProvider).summary();
    final preparationFuture = ref
        .read(dailyPreparationServiceProvider)
        .load(_now);
    final analyticsFuture = ref
        .read(reportRepositoryProvider)
        .analytics(startDate: DateTime(_now.year, _now.month), endDate: _now);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => refreshData(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.blue, AppColors.teal],
                    ),
                  ),
                  child: const Icon(Icons.school_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String?>(
                        future: ref
                            .read(settingsRepositoryProvider)
                            .get('school_name'),
                        builder: (context, snapshot) => Text(
                          snapshot.data?.isNotEmpty == true
                              ? snapshot.data!
                              : 'مدرستي',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy,
                              ),
                        ),
                      ),
                      Text(
                        'مرحبًا، ${user.name}',
                        style: TextStyle(color: Colors.blueGrey.shade600),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Column(
                      children: [
                        Text(
                          DateFormat('HH:mm').format(_now),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        Text(
                          DateFormat('d MMM', 'ar').format(_now),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FutureBuilder<DailyPreparationSnapshot>(
              future: preparationFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.excused,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'تعذر تحميل مؤشرات التحضير الذكية الآن. بيانات الحضور الأساسية لم تتأثر.',
                            ),
                          ),
                          IconButton(
                            tooltip: 'إعادة المحاولة',
                            onPressed: () => setState(() {}),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(22),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                return SmartPreparationSection(
                  snapshot: snapshot.data!,
                  now: _now,
                  onClassTap: _openClassPreparation,
                );
              },
            ),
            const SizedBox(height: 22),
            FutureBuilder<DailySummary>(
              future: summaryFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'تعذر تحميل إحصاءات اليوم. اسحب الشاشة لإعادة المحاولة؛ بياناتك لم تُحذف.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final summary = snapshot.data!;
                return Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth > 700
                            ? (constraints.maxWidth - 36) / 4
                            : (constraints.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _StatCard(
                              width: width,
                              label: 'إجمالي الطلاب',
                              value: summary.totalStudents,
                              icon: Icons.groups_rounded,
                              color: AppColors.blue,
                            ),
                            _StatCard(
                              width: width,
                              label: 'تم تسجيلهم',
                              value: summary.registered,
                              icon: Icons.fact_check_rounded,
                              color: AppColors.teal,
                            ),
                            _StatCard(
                              width: width,
                              label: 'لم يسجلوا',
                              value: summary.remaining,
                              icon: Icons.pending_actions_rounded,
                              color: AppColors.excused,
                            ),
                            _StatCard(
                              width: width,
                              label: 'الغائبون',
                              value: summary.absent,
                              icon: Icons.person_off_rounded,
                              color: AppColors.absent,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'نسبة الحضور اليوم',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '${(summary.attendanceRate * 100).toStringAsFixed(1)}٪',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.present,
                                    fontSize: 20,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: summary.attendanceRate,
                                minHeight: 12,
                                color: AppColors.present,
                                backgroundColor: const Color(0xFFE5EEF1),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _MiniStatus(
                                  color: AppColors.present,
                                  label: 'حاضر',
                                  value: summary.present,
                                ),
                                _MiniStatus(
                                  color: AppColors.absent,
                                  label: 'غائب',
                                  value: summary.absent,
                                ),
                                _MiniStatus(
                                  color: AppColors.excused,
                                  label: 'مستأذن',
                                  value: summary.excused,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (summary.remaining > 0) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5E4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF3D49B)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: AppColors.excused,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'لا يزال هناك ${summary.remaining} طالبًا دون حالة. يمكنك تسجيل الغياب والاستئذان فقط، ثم اعتماد البقية حاضرين عند إغلاق التحضير.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            FutureBuilder<AttendanceAnalytics>(
              future: analyticsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('تعذر تحميل الإحصاءات المتقدمة الآن.'),
                    ),
                  );
                }
                if (!snapshot.hasData) return const SizedBox.shrink();
                return _AnalyticsCard(analytics: snapshot.data!);
              },
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: user.role.canScan ? widget.onStartScan : null,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
              label: const Text('بدء تسجيل الحضور'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                textStyle: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DailyReportScreen(date: DateTime.now()),
                ),
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('إصدار التقرير اليومي'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openClassPreparation(ClassPreparationStatus item) async {
    final user = ref.read(currentUserProvider)!;
    if (!user.role.canScan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا تملك صلاحية تسجيل الحضور.')),
      );
      return;
    }
    final date = SchoolDayFormatter.dateOnly(_now);
    final dateKey = SchoolDayFormatter.key(date);
    try {
      final day = await ref
          .read(attendanceRepositoryProvider)
          .dayOverview(dateKey);
      if (!mounted) return;
      if (day.isClosed) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DailyReportScreen(date: date)),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ScannerScreen(
              attendanceDate: dateKey,
              classId: item.classId,
              classLabel: item.label,
            ),
          ),
        );
      }
      if (mounted) refreshData(ref);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر فتح الفصل: $error')));
      }
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final double width;
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({
    required this.color,
    required this.label,
    required this.value,
  });
  final Color color;
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
      Text(
        '$value',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    ],
  );
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.analytics});
  final AttendanceAnalytics analytics;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: const Icon(Icons.insights_rounded, color: AppColors.blue),
      title: const Text(
        'إحصاءات هذا الشهر',
        style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy),
      ),
      subtitle: Text(
        'الحضور العام ${(analytics.report.attendanceRate * 100).toStringAsFixed(1)}٪',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        if (analytics.bestClass != null)
          _AnalyticsLine(
            icon: Icons.emoji_events_outlined,
            label: 'أفضل فصل في الحضور',
            value:
                '${analytics.bestClass!.label} — ${(analytics.bestClass!.attendanceRate * 100).toStringAsFixed(1)}٪',
            color: AppColors.present,
          ),
        if (analytics.mostAbsentClass != null)
          _AnalyticsLine(
            icon: Icons.warning_amber_rounded,
            label: 'أكثر فصل في الغياب',
            value:
                '${analytics.mostAbsentClass!.label} — ${analytics.mostAbsentClass!.absent}',
            color: AppColors.absent,
          ),
        _RankingTile(
          title: 'أكثر الطلاب غيابًا',
          students: analytics.mostAbsent,
          value: (student) => '${student.absent}',
        ),
        _RankingTile(
          title: 'أكثر الطلاب انضباطًا',
          students: analytics.mostDisciplined,
          value: (student) =>
              '${(student.disciplineRate * 100).toStringAsFixed(1)}٪',
        ),
        _RankingTile(
          title: 'أكثر الطلاب استئذانًا',
          students: analytics.mostExcused,
          value: (student) => '${student.excused}',
        ),
      ],
    ),
  );
}

class _AnalyticsLine extends StatelessWidget {
  const _AnalyticsLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: color),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(value),
  );
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({
    required this.title,
    required this.students,
    required this.value,
  });
  final String title;
  final List<StudentPeriodStat> students;
  final String Function(StudentPeriodStat) value;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    children: students.isEmpty
        ? const [ListTile(title: Text('لا توجد بيانات كافية.'))]
        : [
            for (var index = 0; index < students.length; index++)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                title: Text(students[index].studentName),
                subtitle: Text(students[index].classLabel),
                trailing: Text(
                  value(students[index]),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
          ],
  );
}
