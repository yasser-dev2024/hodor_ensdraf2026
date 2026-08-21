import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/school_day_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import '../../models/school_class.dart';
import '../../services/report_service.dart';

class AbsenceReportScreen extends ConsumerStatefulWidget {
  const AbsenceReportScreen({required this.initialDate, super.key});

  final DateTime initialDate;

  @override
  ConsumerState<AbsenceReportScreen> createState() =>
      _AbsenceReportScreenState();
}

class _AbsenceReportScreenState extends ConsumerState<AbsenceReportScreen> {
  static const _allClassesValue = '__all_classes__';

  late DateTime _date;
  String? _classId;
  bool _busy = false;
  late Future<_AbsenceReportData> _report;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _report = _load();
  }

  String get _dateKey => SchoolDayFormatter.key(_date);

  Future<_AbsenceReportData> _load() async {
    final classes = await ref.read(classRepositoryProvider).getClasses();
    final records = await ref
        .read(attendanceRepositoryProvider)
        .getDaily(date: _dateKey, classId: _classId);
    final absentees = ReportService.absentOnly(records);
    var scopeLabel = 'جميع الفصول';
    for (final schoolClass in classes) {
      if (schoolClass.id == _classId) {
        scopeLabel = schoolClass.label;
        break;
      }
    }
    return _AbsenceReportData(
      classes: classes,
      records: records,
      absentees: absentees,
      scopeLabel: scopeLabel,
    );
  }

  void _reload() {
    setState(() => _report = _load());
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dataRevisionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير النهائي للغياب')),
      body: FutureBuilder<_AbsenceReportData>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تعذر تحميل تقرير الغياب. لم يتم تعديل أو حذف أي بيانات.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _reload,
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
          final data = snapshot.requireData;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'خيارات التقرير الخاص',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 13),
                      InkWell(
                        onTap: _busy ? null : _chooseDate,
                        borderRadius: BorderRadius.circular(14),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'التاريخ',
                            prefixIcon: Icon(Icons.calendar_month_rounded),
                          ),
                          child: Text(
                            SchoolDayFormatter.dualLong(_date),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _classId ?? _allClassesValue,
                        decoration: const InputDecoration(
                          labelText: 'نطاق التقرير',
                          prefixIcon: Icon(Icons.groups_2_outlined),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: _allClassesValue,
                            child: Text('جميع الفصول'),
                          ),
                          for (final schoolClass in data.classes)
                            DropdownMenuItem(
                              value: schoolClass.id,
                              child: Text(schoolClass.label),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) {
                                _classId = value == _allClassesValue
                                    ? null
                                    : value;
                                _reload();
                              },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFF0B8B8)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: AppColors.absent,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${data.absentees.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الطلاب الغائبون فقط',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            data.scopeLabel,
                            style: const TextStyle(color: Colors.blueGrey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.verified_outlined, color: AppColors.present),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'هذا التقرير خاص بالغياب فقط، ولا يدرج الطلاب الحاضرين أو المستأذنين.',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _sharePdf(data),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('مشاركة PDF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.absent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _shareExcel(data),
                      icon: const Icon(Icons.table_chart_rounded),
                      label: const Text('مشاركة Excel'),
                    ),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 20),
              Text(
                'قائمة الغائبين (${data.absentees.length})',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 9),
              if (data.absentees.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'لا يوجد طلاب غائبون في التاريخ والنطاق المحددين.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                for (var index = 0; index < data.absentees.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.absent.withValues(
                            alpha: .12,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: AppColors.absent,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        title: Text(
                          data.absentees[index].studentName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(data.absentees[index].classLabel),
                        trailing: const Icon(
                          Icons.person_off_outlined,
                          color: AppColors.absent,
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

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _date,
      locale: const Locale('ar', 'SA'),
    );
    if (selected == null || !mounted) return;
    _date = selected;
    _reload();
  }

  Future<void> _sharePdf(_AbsenceReportData data) => _run(() async {
    final schoolName =
        await ref.read(settingsRepositoryProvider).get('school_name') ??
        'المدرسة';
    final file = await ref
        .read(reportServiceProvider)
        .generateDailyAbsencePdf(
          date: _dateKey,
          records: data.records,
          schoolName: schoolName,
          scopeLabel: data.scopeLabel,
          fileNameSuffix: _classId ?? 'all',
        );
    await SharePlus.instance.share(
      ShareParams(
        subject: 'التقرير النهائي للطلاب الغائبين $_dateKey',
        text: 'تقرير الغياب فقط — ${data.scopeLabel}',
        files: [XFile(file.path)],
      ),
    );
  });

  Future<void> _shareExcel(_AbsenceReportData data) => _run(() async {
    final file = await ref
        .read(reportServiceProvider)
        .exportDailyAbsenceExcel(
          date: _dateKey,
          records: data.records,
          scopeLabel: data.scopeLabel,
          fileNameSuffix: _classId ?? 'all',
        );
    await SharePlus.instance.share(
      ShareParams(
        subject: 'التقرير النهائي للطلاب الغائبين $_dateKey',
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
        ).showSnackBar(SnackBar(content: Text('تعذر إنشاء التقرير: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AbsenceReportData {
  const _AbsenceReportData({
    required this.classes,
    required this.records,
    required this.absentees,
    required this.scopeLabel,
  });

  final List<SchoolClass> classes;
  final List<AttendanceRecord> records;
  final List<AttendanceRecord> absentees;
  final String scopeLabel;
}
