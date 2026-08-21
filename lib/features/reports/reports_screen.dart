import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/school_day_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import 'absence_report_screen.dart';
import 'advanced_reports_screen.dart';
import 'daily_report_screen.dart';
import 'report_archive_screen.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dataRevisionProvider);
    final repository = ref.read(attendanceRepositoryProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          Text(
            'التقارير والإحصائيات',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'تقارير يومية محفوظة وقابلة للتصدير والمشاركة.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 20),
          _ReportNavigationCard(
            color: AppColors.absent,
            icon: Icons.person_off_rounded,
            title: 'التقرير النهائي للطلاب الغائبين',
            subtitle: 'غياب فقط — لجميع الفصول أو فصل محدد — PDF وExcel',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    AbsenceReportScreen(initialDate: DateTime.now()),
              ),
            ),
          ),
          const SizedBox(height: 9),
          _ReportNavigationCard(
            color: AppColors.blue,
            icon: Icons.today_rounded,
            title: 'التقرير العام للحضور',
            subtitle: 'الحضور والغياب والاستئذان والتفاصيل والتصدير',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DailyReportScreen(date: DateTime.now()),
              ),
            ),
          ),
          const SizedBox(height: 9),
          _ReportNavigationCard(
            color: const Color(0xFF6C4AB6),
            icon: Icons.analytics_rounded,
            title: 'التقارير الأسبوعية والشهرية والفصلية',
            subtitle: 'فترات ونطاقات وإحصاءات أفضل طالب وأفضل فصل',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdvancedReportsScreen()),
            ),
          ),
          const SizedBox(height: 9),
          _ReportNavigationCard(
            color: AppColors.teal,
            icon: Icons.manage_search_rounded,
            title: 'تقرير يوم سابق',
            subtitle: 'اختر التاريخ وافتح السجل اليومي المحفوظ',
            onPressed: () => _openDate(context),
          ),
          const SizedBox(height: 9),
          _ReportNavigationCard(
            color: AppColors.excused,
            icon: Icons.archive_rounded,
            title: 'أرشيف ملفات التقارير',
            subtitle: 'ملفات PDF اليومية والأسبوعية والشهرية الدائمة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportArchiveScreen()),
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<DailySummary>(
            future: repository.summary(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('تعذر تحميل ملخص اليوم.'),
                  ),
                );
              }
              final summary =
                  snapshot.data ??
                  const DailySummary(
                    totalStudents: 0,
                    registered: 0,
                    present: 0,
                    absent: 0,
                    excused: 0,
                  );
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ملخص اليوم',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            SchoolDayFormatter.dualLong(DateTime.now()),
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _ReportStat(
                            label: 'حضور',
                            value: summary.present,
                            color: AppColors.present,
                          ),
                          _ReportStat(
                            label: 'غياب',
                            value: summary.absent,
                            color: AppColors.absent,
                          ),
                          _ReportStat(
                            label: 'استئذان',
                            value: summary.excused,
                            color: AppColors.excused,
                          ),
                          _ReportStat(
                            label: 'المتبقي',
                            value: summary.remaining,
                            color: AppColors.blue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                DailyReportScreen(date: DateTime.now()),
                          ),
                        ),
                        icon: const Icon(Icons.description_rounded),
                        label: const Text('فتح التقرير العام'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          const Text(
            'أرشيف التقارير',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<AttendanceDayOverview>>(
            future: repository.availableDays(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('تعذر تحميل أرشيف الأيام.'),
                  ),
                );
              }
              final days = snapshot.data ?? const <AttendanceDayOverview>[];
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (days.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('لا توجد تقارير محفوظة حتى الآن.'),
                    ),
                  ),
                );
              }
              return Column(
                children: days.map((day) {
                  final parsed = SchoolDayFormatter.parseKey(day.date);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F2F7),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.event_note_rounded,
                            color: AppColors.blue,
                          ),
                        ),
                        title: Text(
                          DateFormat('EEEE، d MMMM yyyy', 'ar').format(parsed),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${SchoolDayFormatter.hijriLong(parsed)}\n${day.isClosed ? 'مغلق' : 'مفتوح'} — ${day.recordCount} حالة${day.closedBy == null ? '' : ' — أغلقه ${day.closedBy}'}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DailyReportScreen(date: parsed),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<void> _openDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: DateTime.now(),
      locale: const Locale('ar', 'SA'),
    );
    if (date != null && context.mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => DailyReportScreen(date: date)));
    }
  }
}

class _ReportNavigationCard extends StatelessWidget {
  const _ReportNavigationCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left_rounded, color: color),
          ],
        ),
      ),
    ),
  );
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}
