import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/school_day_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import '../../models/daily_preparation.dart';
import '../../models/period_report.dart';
import '../scanner/scanner_screen.dart';
import '../students/student_details_screen.dart';
import 'daily_review_sheet.dart';

class DailyReportScreen extends ConsumerStatefulWidget {
  const DailyReportScreen({required this.date, super.key});
  final DateTime date;

  @override
  ConsumerState<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends ConsumerState<DailyReportScreen> {
  bool _busy = false;
  late final String _dateKey;

  @override
  void initState() {
    super.initState();
    _dateKey = DateFormat('yyyy-MM-dd').format(widget.date);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dataRevisionProvider);
    final repository = ref.read(attendanceRepositoryProvider);
    final user = ref.watch(currentUserProvider)!;
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير اليومي')),
      body:
          FutureBuilder<
            (
              DailySummary,
              List<AttendanceRecord>,
              List<Map<String, Object?>>,
              AttendanceDayOverview,
            )
          >(
            future: _load(repository),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('تعذر تحميل التقرير. لم تُحذف أي بيانات.'),
                        TextButton.icon(
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final (summary, records, unregistered, day) = snapshot.data!;
              final isClosed = day.isClosed;
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Text(
                            SchoolDayFormatter.gregorianLong(widget.date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            SchoolDayFormatter.hijriLong(widget.date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.teal,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _DailyStat(
                                label: 'الإجمالي',
                                value: summary.totalStudents,
                                color: AppColors.navy,
                              ),
                              _DailyStat(
                                label: 'حاضر',
                                value: summary.present,
                                color: AppColors.present,
                              ),
                              _DailyStat(
                                label: 'غائب',
                                value: summary.absent,
                                color: AppColors.absent,
                              ),
                              _DailyStat(
                                label: 'مستأذن',
                                value: summary.excused,
                                color: AppColors.excused,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: summary.attendanceRate,
                              minHeight: 11,
                              color: AppColors.present,
                              backgroundColor: const Color(0xFFE6EDF0),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'نسبة الحضور ${(summary.attendanceRate * 100).toStringAsFixed(1)}٪',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  if (isClosed)
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5E4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF3D49B)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            color: AppColors.excused,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'هذا اليوم مغلق ومحمي من التعديل.${day.closedBy == null ? '' : '\nأغلق الحصر: ${day.closedBy}'}${day.closedAt == null ? '' : ' — ${DateFormat('h:mm a', 'ar').format(day.closedAt!.toLocal())}'}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isClosed) const SizedBox(height: 13),
                  if (unregistered.isNotEmpty)
                    Card(
                      child: ExpansionTile(
                        leading: const Icon(
                          Icons.pending_actions_rounded,
                          color: AppColors.excused,
                        ),
                        title: Text(
                          '${unregistered.length} طالبًا لم تسجل حالتهم',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: const Text(
                          'عند إغلاق التحضير يمكن اعتمادهم حاضرين تلقائيًا',
                        ),
                        children: unregistered
                            .map(
                              (row) => ListTile(
                                dense: true,
                                title: Text(row['name'] as String),
                                subtitle: Text(
                                  [
                                    row['grade_name'],
                                    row['class_name'],
                                  ].whereType<String>().join(' / '),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 13),
                  _DailyReportAction(
                    color: AppColors.blue,
                    icon: Icons.fact_check_outlined,
                    title: 'راجع لي اليوم',
                    subtitle:
                        'يفحص الاكتمال والتعارضات والبيانات الناقصة دون تعديل أي سجل',
                    onTap: _busy ? null : _reviewDay,
                  ),
                  const SizedBox(height: 9),
                  _DailyReportAction(
                    color: const Color(0xFFB3261E),
                    icon: Icons.picture_as_pdf_rounded,
                    title: 'مشاركة التقرير بصيغة PDF',
                    subtitle: 'واتساب أو البريد أو الطباعة أو أي تطبيق مشاركة',
                    onTap: _busy ? null : () => _sharePdf(summary, records),
                  ),
                  const SizedBox(height: 9),
                  _DailyReportAction(
                    color: const Color(0xFF18794E),
                    icon: Icons.table_chart_rounded,
                    title: 'مشاركة التقرير بصيغة Excel',
                    subtitle: 'ملف جدولي تفصيلي قابل للفتح والحفظ',
                    onTap: _busy ? null : () => _shareExcel(records),
                  ),
                  const SizedBox(height: 9),
                  _DailyReportAction(
                    color: const Color(0xFF128C4A),
                    icon: Icons.send_rounded,
                    title: 'إرسال التقرير إلى وكيل شؤون الطلاب',
                    subtitle: 'يستخدم وسيلة الإرسال الافتراضية من الإعدادات',
                    onTap: _busy ? null : () => _sendToAgent(summary, records),
                  ),
                  if (user.role.canManage && isClosed) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _reopenDay,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('إعادة فتح اليوم'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ] else if (user.role.canManage &&
                      DateUtils.isSameDay(widget.date, DateTime.now())) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _closeDay(unregistered.length),
                      icon: const Icon(Icons.lock_clock_outlined),
                      label: const Text('إغلاق حضور اليوم'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Text(
                    'السجلات',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (records.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(25),
                        child: Center(
                          child: Text('لم يتم تسجيل حالات في هذا اليوم.'),
                        ),
                      ),
                    )
                  else
                    ...records.map(
                      (record) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _color(
                                record.status,
                              ).withValues(alpha: .12),
                              child: Icon(
                                _icon(record.status),
                                color: _color(record.status),
                              ),
                            ),
                            title: Text(
                              record.studentName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${record.classLabel}  •  ${DateFormat('h:mm a', 'ar').format(record.recordedAt.toLocal())}\nالموظف: ${record.recordedBy}',
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              record.status.label,
                              style: TextStyle(
                                color: _color(record.status),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }

  Future<
    (
      DailySummary,
      List<AttendanceRecord>,
      List<Map<String, Object?>>,
      AttendanceDayOverview,
    )
  >
  _load(repository) async {
    final summary = await repository.summary(date: _dateKey) as DailySummary;
    final records =
        await repository.getDaily(date: _dateKey) as List<AttendanceRecord>;
    final unregistered =
        await repository.unregistered(date: _dateKey)
            as List<Map<String, Object?>>;
    final day = await repository.dayOverview(_dateKey) as AttendanceDayOverview;
    return (summary, records, unregistered, day);
  }

  Future<void> _reviewDay() async {
    await _run(() async {
      final result = await ref
          .read(dailyPreparationServiceProvider)
          .review(widget.date);
      if (!mounted) return;
      final selected = await showModalBottomSheet<DailyReviewIssue>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        builder: (sheetContext) => DailyReviewSheet(
          result: result,
          onIssueTap: (issue) => Navigator.pop(sheetContext, issue),
        ),
      );
      if (selected != null && mounted) {
        await _openReviewIssue(selected);
      }
    });
  }

  Future<void> _openReviewIssue(DailyReviewIssue issue) async {
    if (issue.studentId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StudentDetailsScreen(studentId: issue.studentId!),
        ),
      );
      if (mounted) refreshData(ref);
      return;
    }
    if (issue.classId == null) return;
    final user = ref.read(currentUserProvider)!;
    if (!user.role.canScan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا تملك صلاحية فتح مسار تحضير الفصل.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          attendanceDate: _dateKey,
          classId: issue.classId,
          classLabel: issue.classLabel,
        ),
      ),
    );
    if (mounted) refreshData(ref);
  }

  Future<void> _sharePdf(
    DailySummary summary,
    List<AttendanceRecord> records,
  ) async {
    await _run(() async {
      final school =
          await ref.read(settingsRepositoryProvider).get('school_name') ??
          'المدرسة';
      final file = await ref
          .read(reportServiceProvider)
          .generateDailyPdf(
            date: _dateKey,
            summary: summary,
            records: records,
            schoolName: school,
          );
      final autoArchive =
          await ref.read(settingsRepositoryProvider).get('auto_archive_pdf') !=
          'false';
      if (autoArchive) {
        await ref
            .read(reportRepositoryProvider)
            .archiveFile(
              source: file,
              reportType: 'daily',
              periodStart: widget.date,
              periodEnd: widget.date,
              scope: const ReportScope.school(),
              userId: ref.read(currentUserProvider)!.id,
            );
      }
      await SharePlus.instance.share(
        ShareParams(
          subject: 'تقرير الحضور الصباحي $_dateKey',
          text: 'تقرير الحضور الصباحي - $school',
          files: [XFile(file.path)],
        ),
      );
    });
  }

  Future<void> _shareExcel(List<AttendanceRecord> records) async {
    await _run(() async {
      final file = await ref
          .read(reportServiceProvider)
          .exportDailyExcel(date: _dateKey, records: records);
      await SharePlus.instance.share(
        ShareParams(
          subject: 'تقرير الحضور $_dateKey',
          files: [XFile(file.path)],
        ),
      );
    });
  }

  Future<void> _sendToAgent(
    DailySummary summary,
    List<AttendanceRecord> records,
  ) async {
    final settings = await ref.read(settingsRepositoryProvider).getAll();
    if (settings['agent_send_method'] == 'share') {
      await _sharePdf(summary, records);
      return;
    }
    final phone = (settings['agent_phone'] ?? '').replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('أضف رقم وكيل شؤون الطلاب من الإعدادات أولًا.'),
          ),
        );
      }
      return;
    }
    final template =
        settings['whatsapp_template'] ??
        'تقرير الغياب الصباحي\nالتاريخ: {date}\nإجمالي الطلاب: {total}\nالحاضرون: {present}\nالغائبون: {absent}\nالمستأذنون: {excused}\n\nيرجى إرفاق التقرير التفصيلي عند الحاجة.';
    final text = template
        .replaceAll('{date}', SchoolDayFormatter.dualInline(widget.date))
        .replaceAll('{total}', '${summary.totalStudents}')
        .replaceAll('{present}', '${summary.present}')
        .replaceAll('{absent}', '${summary.absent}')
        .replaceAll('{excused}', '${summary.excused}');
    final uri = Uri.https('wa.me', '/$phone', {'text': text});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب على هذا الجهاز.')),
      );
    }
  }

  Future<void> _closeDay(int remaining) async {
    final completeWithPresent =
        await ref
            .read(settingsRepositoryProvider)
            .get('mark_unregistered_present_on_close') !=
        'false';
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إغلاق الحضور الصباحي'),
        content: Text(
          remaining == 0
              ? 'سيتم حفظ لقطة نهائية للتقرير ومنع التعديل العادي.'
              : completeWithPresent
              ? 'تم تسجيل حالات الغياب والاستئذان، وسيُحتسب بقية الطلاب وعددهم $remaining حاضرين تلقائيًا ثم يُغلق يوم ${SchoolDayFormatter.gregorianLong(widget.date)}. هل تريد المتابعة؟'
              : 'لا يزال هناك $remaining طالبًا دون حالة. سيتم إغلاق اليوم دون استكمالهم لأن خيار احتساب البقية حاضرين معطل من الإعدادات. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إغلاق اليوم'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref
          .read(attendanceRepositoryProvider)
          .closeDay(
            userId: ref.read(currentUserProvider)!.id,
            date: _dateKey,
            markUnregisteredPresent: completeWithPresent,
          );
      refreshData(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completeWithPresent && remaining > 0
                  ? 'تم احتساب بقية الطلاب حاضرين وإغلاق يوم التحضير.'
                  : 'تم إغلاق التقرير وحفظ لقطة اليوم.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _reopenDay() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة فتح اليوم'),
        content: const Text(
          'سيُسمح بالتعديل مرة أخرى، وستُسجل العملية باسمك وتوقيتها في سجل التدقيق. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إعادة الفتح'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await ref
          .read(attendanceRepositoryProvider)
          .reopenDay(userId: ref.read(currentUserProvider)!.id, date: _dateKey);
      refreshData(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إعادة فتح اليوم وتسجيل العملية.')),
        );
      }
    });
  }

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

  static Color _color(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => AppColors.present,
    AttendanceStatus.absent => AppColors.absent,
    AttendanceStatus.excused => AppColors.excused,
  };
  static IconData _icon(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => Icons.check_rounded,
    AttendanceStatus.absent => Icons.close_rounded,
    AttendanceStatus.excused => Icons.exit_to_app_rounded,
  };
}

class _DailyReportAction extends StatelessWidget {
  const _DailyReportAction({
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
    color: onTap == null ? Colors.grey.shade200 : color.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: onTap == null
                ? Colors.grey.shade300
                : color.withValues(alpha: .3),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
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

class _DailyStat extends StatelessWidget {
  const _DailyStat({
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
