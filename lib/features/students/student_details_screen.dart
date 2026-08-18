import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import '../../models/student.dart';
import 'student_form_screen.dart';
import 'student_photo.dart';

class StudentDetailsScreen extends ConsumerStatefulWidget {
  const StudentDetailsScreen({required this.studentId, super.key});
  final String studentId;

  @override
  ConsumerState<StudentDetailsScreen> createState() =>
      _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends ConsumerState<StudentDetailsScreen> {
  late Future<Student?> _student;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _student = ref.read(studentRepositoryProvider).getById(widget.studentId);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    return Scaffold(
      appBar: AppBar(title: const Text('ملف الطالب')),
      body: FutureBuilder<Student?>(
        future: _student,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.connectionState == ConnectionState.done) {
              return const Center(child: Text('الطالب غير موجود.'));
            }
            return const Center(child: CircularProgressIndicator());
          }
          final student = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      StudentPhoto(
                        path: student.photoPath,
                        size: 160,
                        heroTag: 'student-${student.id}',
                        highlighted: true,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        student.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        student.classLabel.isEmpty
                            ? 'الصف والفصل غير محددين'
                            : student.classLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _InfoChip(
                            icon: Icons.badge_outlined,
                            text: 'السجل: ${student.maskedNationalId}',
                          ),
                          if (student.academicNumber?.isNotEmpty == true)
                            _InfoChip(
                              icon: Icons.numbers_rounded,
                              text: student.academicNumber!,
                            ),
                          if (student.stage.isNotEmpty)
                            _InfoChip(
                              icon: Icons.account_balance_outlined,
                              text: student.stage,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FutureBuilder<Map<AttendanceStatus, int>>(
                future: ref
                    .read(attendanceRepositoryProvider)
                    .studentStats(student.id),
                builder: (context, statSnapshot) {
                  final stats = statSnapshot.data ?? {};
                  final present = stats[AttendanceStatus.present] ?? 0;
                  final absent = stats[AttendanceStatus.absent] ?? 0;
                  final excused = stats[AttendanceStatus.excused] ?? 0;
                  final total = present + absent + excused;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(17),
                      child: Column(
                        children: [
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'ملخص السجل',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _Stat(
                                label: 'حضور',
                                value: present,
                                color: AppColors.present,
                              ),
                              _Stat(
                                label: 'غياب',
                                value: absent,
                                color: AppColors.absent,
                              ),
                              _Stat(
                                label: 'استئذان',
                                value: excused,
                                color: AppColors.excused,
                              ),
                              _Stat(
                                label: 'النسبة',
                                valueText: total == 0
                                    ? '—'
                                    : '${(present / total * 100).toStringAsFixed(0)}٪',
                                color: AppColors.blue,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFDCE5EA)),
                        ),
                        child: QrImageView(
                          data: student.barcodeToken,
                          version: QrVersions.auto,
                          size: 112,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'رمز الطالب الآمن',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.navy,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'لا يحتوي هذا الرمز على السجل المدني، بل على توكن داخلي عشوائي وفريد.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  if (user.role.canManage)
                    FilledButton.tonalIcon(
                      onPressed: () => _edit(student),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('تعديل'),
                    ),
                  if (user.role.canManage)
                    FilledButton.tonalIcon(
                      onPressed: student.gradeId == null
                          ? null
                          : () => _move(student),
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('نقل الطالب'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _print(student),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('طباعة الباركود'),
                  ),
                  if (user.role.canManage)
                    OutlinedButton.icon(
                      onPressed: () => _deactivate(student),
                      icon: const Icon(
                        Icons.person_off_outlined,
                        color: AppColors.absent,
                      ),
                      label: const Text(
                        'تعطيل الطالب',
                        style: TextStyle(color: AppColors.absent),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(Student student) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => StudentFormScreen(student: student)),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _move(Student student) async {
    final classes = await ref
        .read(classRepositoryProvider)
        .getClasses(gradeId: student.gradeId);
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(
              title: Text(
                'نقل الطالب إلى فصل آخر',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('تظهر فصول الصف نفسه فقط.'),
            ),
            for (final item in classes)
              RadioListTile<String>(
                value: item.id,
                groupValue: student.classId,
                onChanged: item.id == student.classId
                    ? null
                    : (value) => Navigator.pop(context, value),
                title: Text(item.label),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await ref
        .read(studentRepositoryProvider)
        .transfer(
          student.id,
          selected,
          userId: ref.read(currentUserProvider)!.id,
        );
    refreshData(ref);
    if (mounted) setState(_reload);
  }

  Future<void> _print(Student student) async {
    final schoolName =
        await ref.read(settingsRepositoryProvider).get('school_name') ?? '';
    final file = await ref.read(reportServiceProvider).generateBarcodeCards([
      student,
    ], schoolName: schoolName);
    await Printing.layoutPdf(
      name: 'بطاقة ${student.name}',
      onLayout: (_) => file.readAsBytes(),
    );
  }

  Future<void> _deactivate(Student student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعطيل الطالب'),
        content: Text(
          'سيتم تعطيل ${student.name} مع الاحتفاظ بسجلات الحضور السابقة. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تعطيل'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(studentRepositoryProvider)
        .softDelete(student.id, userId: ref.read(currentUserProvider)!.id);
    refreshData(ref);
    if (mounted) Navigator.of(context).pop();
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F5F8),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.blue),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    this.value = 0,
    this.valueText,
    required this.color,
  });
  final String label;
  final int value;
  final String? valueText;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          valueText ?? '$value',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}
