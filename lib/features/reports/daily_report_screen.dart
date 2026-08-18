import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';

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
            (DailySummary, List<AttendanceRecord>, List<Map<String, Object?>>)
          >(
            future: _load(repository),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final (summary, records, unregistered) = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Text(
                            DateFormat(
                              'EEEE، d MMMM yyyy',
                              'ar',
                            ).format(widget.date),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: AppColors.navy,
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
                          'لا يتم تحويلهم إلى غياب تلقائيًا',
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
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () => _sharePdf(summary, records),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF ومشاركة'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _shareExcel(records),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Excel'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _whatsApp(summary),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('إرسال عبر واتساب'),
                      ),
                      if (user.role.canManage &&
                          DateUtils.isSameDay(widget.date, DateTime.now()))
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _closeDay(unregistered.length),
                          icon: const Icon(Icons.lock_clock_outlined),
                          label: const Text('إغلاق حضور اليوم'),
                        ),
                    ],
                  ),
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
                              '${record.classLabel}  •  ${DateFormat('h:mm a', 'ar').format(record.recordedAt.toLocal())}',
                            ),
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

  Future<(DailySummary, List<AttendanceRecord>, List<Map<String, Object?>>)>
  _load(repository) async {
    final summary = await repository.summary(date: _dateKey) as DailySummary;
    final records =
        await repository.getDaily(date: _dateKey) as List<AttendanceRecord>;
    final unregistered =
        await repository.unregistered(date: _dateKey)
            as List<Map<String, Object?>>;
    return (summary, records, unregistered);
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

  Future<void> _whatsApp(DailySummary summary) async {
    final settings = await ref.read(settingsRepositoryProvider).getAll();
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
    final text =
        'تقرير الغياب الصباحي\nالتاريخ: $_dateKey\nإجمالي الطلاب: ${summary.totalStudents}\nالحاضرون: ${summary.present}\nالغائبون: ${summary.absent}\nالمستأذنون: ${summary.excused}\n\nيرجى إرفاق التقرير التفصيلي عند الحاجة.';
    final uri = Uri.https('wa.me', '/$phone', {'text': text});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب على هذا الجهاز.')),
      );
    }
  }

  Future<void> _closeDay(int remaining) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إغلاق الحضور الصباحي'),
        content: Text(
          remaining == 0
              ? 'سيتم حفظ لقطة نهائية للتقرير ومنع التعديل العادي.'
              : 'لا يزال هناك $remaining طالبًا دون حالة. سيتم حفظ التقرير كما هو ولن يُعتبروا غائبين تلقائيًا. هل تريد الإغلاق؟',
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
          .closeDay(userId: ref.read(currentUserProvider)!.id, date: _dateKey);
      refreshData(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إغلاق التقرير وحفظ لقطة اليوم.')),
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
