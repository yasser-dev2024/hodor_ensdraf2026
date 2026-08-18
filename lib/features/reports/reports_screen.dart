import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import 'daily_report_screen.dart';

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
          FutureBuilder<DailySummary>(
            future: repository.summary(),
            builder: (context, snapshot) {
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
                            DateFormat(
                              'd MMMM yyyy',
                              'ar',
                            ).format(DateTime.now()),
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
                        label: const Text('فتح تقرير اليوم'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDate: DateTime.now(),
                locale: const Locale('ar', 'SA'),
              );
              if (date != null && context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DailyReportScreen(date: date),
                  ),
                );
              }
            },
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('اختيار تاريخ'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
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
          FutureBuilder<List<String>>(
            future: repository.availableDates(),
            builder: (context, snapshot) {
              final dates = snapshot.data ?? const <String>[];
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (dates.isEmpty) {
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
                children: dates.map((date) {
                  final parsed = DateTime.parse(date);
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
                        subtitle: const Text('تقرير الحضور الصباحي'),
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
