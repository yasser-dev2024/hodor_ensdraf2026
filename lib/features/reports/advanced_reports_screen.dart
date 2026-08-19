import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/period_report.dart';
import '../../models/school_class.dart';
import '../../models/student.dart';

class AdvancedReportsScreen extends ConsumerStatefulWidget {
  const AdvancedReportsScreen({super.key});

  @override
  ConsumerState<AdvancedReportsScreen> createState() =>
      _AdvancedReportsScreenState();
}

class _AdvancedReportsScreenState extends ConsumerState<AdvancedReportsScreen> {
  late DateTime _start;
  late DateTime _end;
  ReportScopeType _scopeType = ReportScopeType.school;
  String? _scopeId;
  String _reportType = 'monthly';
  bool _busy = false;
  late Future<_ReportFilters> _filters;
  late Future<PeriodReport> _report;
  late Future<AttendanceAnalytics> _analytics;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month);
    _end = DateTime(now.year, now.month, now.day);
    _filters = _loadFilters();
    _report = _loadReport();
    _analytics = _loadAnalytics();
  }

  Future<_ReportFilters> _loadFilters() async => _ReportFilters(
    grades: await ref.read(classRepositoryProvider).getGrades(),
    classes: await ref.read(classRepositoryProvider).getClasses(),
    students: await ref.read(studentRepositoryProvider).getAll(),
  );

  ReportScope _scope(_ReportFilters filters) {
    if (_scopeType == ReportScopeType.school) {
      return const ReportScope.school();
    }
    final options = filters.options(_scopeType);
    final selected = options.where((item) => item.id == _scopeId).firstOrNull;
    return ReportScope(
      type: _scopeType,
      id: selected?.id,
      label: selected?.label ?? _scopeType.label,
    );
  }

  Future<PeriodReport> _loadReport() async {
    final filters = await _filters;
    return ref
        .read(reportRepositoryProvider)
        .periodReport(startDate: _start, endDate: _end, scope: _scope(filters));
  }

  Future<AttendanceAnalytics> _loadAnalytics() => ref
      .read(reportRepositoryProvider)
      .analytics(startDate: _start, endDate: _end);

  void _refreshReport() => setState(() {
    _report = _loadReport();
    _analytics = _loadAnalytics();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('التقارير الشاملة والشهرية')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الفترة والنطاق',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PresetChip(
                        label: 'هذا الأسبوع',
                        onTap: () => _setPreset('weekly'),
                      ),
                      _PresetChip(
                        label: 'هذا الشهر',
                        onTap: () => _setPreset('monthly'),
                      ),
                      _PresetChip(
                        label: 'الفصل الدراسي',
                        onTap: () => _setPreset('term'),
                      ),
                      _PresetChip(label: 'فترة مخصصة', onTap: _pickRange),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${DateFormat('dd/MM/yyyy').format(_start)} — ${DateFormat('dd/MM/yyyy').format(_end)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ReportScopeType>(
                  value: _scopeType,
                  decoration: const InputDecoration(labelText: 'نوع النطاق'),
                  items: ReportScopeType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _scopeType = value;
                      _scopeId = null;
                    });
                  },
                ),
                if (_scopeType != ReportScopeType.school) ...[
                  const SizedBox(height: 10),
                  FutureBuilder<_ReportFilters>(
                    future: _filters,
                    builder: (context, snapshot) {
                      final options =
                          snapshot.data?.options(_scopeType) ?? const [];
                      return DropdownButtonFormField<String>(
                        key: ValueKey('$_scopeType-$_scopeId'),
                        value: _scopeId,
                        decoration: InputDecoration(
                          labelText: 'اختر ${_scopeType.label}',
                        ),
                        items: options
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _scopeId = value),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed:
                      _scopeType != ReportScopeType.school && _scopeId == null
                      ? null
                      : _refreshReport,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('إنشاء التقرير'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FutureBuilder<PeriodReport>(
          future: _report,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('تعذر إنشاء التقرير: ${snapshot.error}'),
                ),
              );
            }
            final report = snapshot.data!;
            return Column(
              children: [
                _SummaryCard(report: report),
                const SizedBox(height: 12),
                _ExportAction(
                  color: const Color(0xFFB3261E),
                  icon: Icons.picture_as_pdf_rounded,
                  title: 'تصدير التقرير بصيغة PDF',
                  subtitle: 'ملف عربي RTL جاهز للطباعة والمشاركة',
                  onTap: _busy ? null : () => _sharePdf(report),
                ),
                const SizedBox(height: 9),
                _ExportAction(
                  color: const Color(0xFF18794E),
                  icon: Icons.table_chart_rounded,
                  title: 'تصدير التقرير بصيغة Excel',
                  subtitle: 'جدول تفصيلي قابل للحفظ والمشاركة',
                  onTap: _busy ? null : () => _shareExcel(report),
                ),
                const SizedBox(height: 18),
                FutureBuilder<AttendanceAnalytics>(
                  future: _analytics,
                  builder: (context, analyticsSnapshot) {
                    if (analyticsSnapshot.connectionState !=
                        ConnectionState.done) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(22),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }
                    if (analyticsSnapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            'تعذر حساب قوائم الأفضل والأكثر: ${analyticsSnapshot.error}',
                          ),
                        ),
                      );
                    }
                    return _AnalyticsSection(
                      analytics: analyticsSnapshot.data!,
                    );
                  },
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'تفاصيل الطلاب (${report.students.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (report.students.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('لا يوجد طلاب في هذا النطاق.'),
                    ),
                  )
                else
                  for (final student in report.students)
                    Card(
                      child: ListTile(
                        title: Text(
                          student.studentName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${student.classLabel}\nمتوقع ${student.expectedDays} • حضور ${student.present} • غياب ${student.absent} • استئذان ${student.excused}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          '${(student.disciplineRate * 100).toStringAsFixed(1)}٪',
                          style: TextStyle(
                            color: student.disciplineRate >= .9
                                ? AppColors.present
                                : AppColors.absent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ],
    ),
  );

  void _setPreset(String type) {
    final now = DateTime.now();
    setState(() {
      _reportType = type;
      switch (type) {
        case 'weekly':
          _end = DateTime(now.year, now.month, now.day);
          _start = _end.subtract(Duration(days: now.weekday - 1));
        case 'monthly':
          _start = DateTime(now.year, now.month);
          _end = DateTime(now.year, now.month, now.day);
        case 'term':
          _start = now.month >= 7
              ? DateTime(now.year, 7, 1)
              : DateTime(now.year - 1, 7, 1);
          _end = DateTime(now.year, now.month, now.day);
      }
      _report = _loadReport();
      _analytics = _loadAnalytics();
    });
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      locale: const Locale('ar', 'SA'),
    );
    if (range == null || !mounted) return;
    setState(() {
      _start = range.start;
      _end = range.end;
      _reportType = 'custom';
      _report = _loadReport();
      _analytics = _loadAnalytics();
    });
  }

  Future<void> _sharePdf(PeriodReport report) => _run(() async {
    final school =
        await ref.read(settingsRepositoryProvider).get('school_name') ??
        'المدرسة';
    final file = await ref
        .read(reportServiceProvider)
        .generatePeriodPdf(
          report: report,
          analytics: await _analytics,
          schoolName: school,
          title: _reportType == 'monthly'
              ? 'التقرير الشهري للحضور والانضباط'
              : 'تقرير الحضور والانضباط للفترة',
        );
    final autoArchive =
        await ref.read(settingsRepositoryProvider).get('auto_archive_pdf') !=
        'false';
    if (autoArchive) {
      await ref
          .read(reportRepositoryProvider)
          .archiveFile(
            source: file,
            reportType: _reportType,
            periodStart: report.startDate,
            periodEnd: report.endDate,
            scope: report.scope,
            userId: ref.read(currentUserProvider)!.id,
          );
    }
    await SharePlus.instance.share(
      ShareParams(
        subject: 'تقرير ${report.scope.label}',
        files: [XFile(file.path)],
      ),
    );
    refreshData(ref);
  });

  Future<void> _shareExcel(PeriodReport report) => _run(() async {
    final file = await ref
        .read(reportServiceProvider)
        .exportPeriodExcel(report: report, analytics: await _analytics);
    await SharePlus.instance.share(
      ShareParams(
        subject: 'تقرير ${report.scope.label}',
        files: [XFile(file.path)],
      ),
    );
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر إكمال العملية: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ReportFilters {
  const _ReportFilters({
    required this.grades,
    required this.classes,
    required this.students,
  });
  final List<SchoolGrade> grades;
  final List<SchoolClass> classes;
  final List<Student> students;

  List<_ScopeOption> options(ReportScopeType type) => switch (type) {
    ReportScopeType.school => const [],
    ReportScopeType.grade =>
      grades.map((item) => _ScopeOption(item.id, item.name)).toList(),
    ReportScopeType.schoolClass =>
      classes.map((item) => _ScopeOption(item.id, item.label)).toList(),
    ReportScopeType.student =>
      students
          .map(
            (item) => _ScopeOption(
              item.id,
              '${item.name}${item.classLabel.isEmpty ? '' : ' — ${item.classLabel}'}',
            ),
          )
          .toList(),
  };
}

class _ScopeOption {
  const _ScopeOption(this.id, this.label);
  final String id;
  final String label;
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 7),
    child: ActionChip(label: Text(label), onPressed: onTap),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});
  final PeriodReport report;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.scope.label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _Metric('الطلاب', report.totalStudents, AppColors.navy),
              _Metric('أيام الدراسة', report.schoolDays, AppColors.blue),
              _Metric('حضور', report.present, AppColors.present),
              _Metric('غياب', report.absent, AppColors.absent),
              _Metric('استئذان', report.excused, AppColors.excused),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'نسبة الانضباط العامة ${(report.attendanceRate * 100).toStringAsFixed(1)}٪',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: color,
          fontSize: 20,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class _ExportAction extends StatelessWidget {
  const _ExportAction({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: onTap == null ? Colors.grey.shade200 : color.withValues(alpha: .09),
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: onTap == null
                ? Colors.grey.shade300
                : color.withValues(alpha: .35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: onTap == null ? Colors.grey.shade300 : color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: onTap == null ? Colors.grey : color,
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

class _AnalyticsSection extends StatelessWidget {
  const _AnalyticsSection({required this.analytics});

  final AttendanceAnalytics analytics;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Row(
        children: [
          Icon(Icons.emoji_events_rounded, color: AppColors.excused),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'لوحة الأفضل والأكثر — المدرسة كاملة',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      const Text(
        'تتغير النتائج حسب الأسبوع أو الشهر أو الفصل الدراسي أو الفترة المخصصة أعلاه.',
        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
      ),
      const SizedBox(height: 10),
      _AnalyticsHighlight(
        icon: Icons.percent_rounded,
        color: AppColors.blue,
        title: 'نسبة الحضور العامة',
        value: '${(analytics.report.attendanceRate * 100).toStringAsFixed(1)}٪',
      ),
      if (analytics.mostDisciplined.isNotEmpty)
        _AnalyticsHighlight(
          icon: Icons.workspace_premium_rounded,
          color: AppColors.present,
          title: 'أفضل طالب انضباطًا',
          value:
              '${analytics.mostDisciplined.first.studentName} — ${(analytics.mostDisciplined.first.disciplineRate * 100).toStringAsFixed(1)}٪',
        ),
      if (analytics.bestClass != null)
        _AnalyticsHighlight(
          icon: Icons.groups_rounded,
          color: const Color(0xFF6C4AB6),
          title: 'أفضل فصل انضباطًا',
          value:
              '${analytics.bestClass!.label} — ${(analytics.bestClass!.attendanceRate * 100).toStringAsFixed(1)}٪',
        ),
      if (analytics.mostAbsentClass != null)
        _AnalyticsHighlight(
          icon: Icons.group_off_outlined,
          color: AppColors.absent,
          title: 'أكثر فصل في الغياب',
          value:
              '${analytics.mostAbsentClass!.label} — ${analytics.mostAbsentClass!.absent} حالة',
        ),
      const SizedBox(height: 8),
      _RankingCard(
        title: 'أكثر الطلاب غيابًا',
        icon: Icons.person_off_outlined,
        color: AppColors.absent,
        emptyText: 'لا توجد حالات غياب في الفترة.',
        students: analytics.mostAbsent,
        value: (student) => '${student.absent} غياب',
      ),
      const SizedBox(height: 8),
      _RankingCard(
        title: 'أفضل الطلاب انضباطًا',
        icon: Icons.verified_rounded,
        color: AppColors.present,
        emptyText: 'لا توجد أيام دراسية محسوبة في الفترة.',
        students: analytics.mostDisciplined,
        value: (student) =>
            '${(student.disciplineRate * 100).toStringAsFixed(1)}٪',
      ),
      const SizedBox(height: 8),
      _RankingCard(
        title: 'أكثر الطلاب استئذانًا',
        icon: Icons.exit_to_app_rounded,
        color: AppColors.excused,
        emptyText: 'لا توجد حالات استئذان في الفترة.',
        students: analytics.mostExcused,
        value: (student) => '${student.excused} استئذان',
      ),
    ],
  );
}

class _AnalyticsHighlight extends StatelessWidget {
  const _AnalyticsHighlight({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    color: color.withValues(alpha: .07),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(value, style: TextStyle(color: color)),
    ),
  );
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.emptyText,
    required this.students,
    required this.value,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String emptyText;
  final List<StudentPeriodStat> students;
  final String Function(StudentPeriodStat) value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (students.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                emptyText,
                style: const TextStyle(color: Colors.blueGrey),
              ),
            )
          else
            for (var index = 0; index < students.length; index++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withValues(alpha: .12),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                title: Text(
                  students[index].studentName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(students[index].classLabel),
                trailing: Text(
                  value(students[index]),
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
        ],
      ),
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
