import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/school_class.dart';
import '../../models/student.dart';
import 'student_details_screen.dart';
import 'student_form_screen.dart';
import 'student_photo.dart';

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  String _query = '';
  String? _gradeId;
  String? _classId;
  bool _includeInactive = false;
  late Future<List<SchoolGrade>> _grades;
  late Future<List<SchoolClass>> _classes;

  @override
  void initState() {
    super.initState();
    _reloadFilters();
  }

  void _reloadFilters() {
    _grades = ref.read(classRepositoryProvider).getGrades();
    _classes = ref.read(classRepositoryProvider).getClasses();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dataRevisionProvider);
    final user = ref.watch(currentUserProvider)!;
    final future = ref
        .read(studentRepositoryProvider)
        .getAll(
          query: _query,
          gradeId: _gradeId,
          classId: _classId,
          includeInactive: _includeInactive,
        );
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'الطلاب',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'طباعة باركود طالب أو فصل أو صف أو الجميع',
                  onPressed: _printBarcodeCards,
                  icon: const Icon(Icons.print_outlined),
                ),
                const SizedBox(width: 8),
                if (user.role.canManage)
                  FilledButton.icon(
                    onPressed: () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const StudentFormScreen(),
                        ),
                      );
                      if (changed == true) refreshData(ref);
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('إضافة طالب'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'بحث بالاسم، السجل، الصف، الفصل أو الباركود',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: FutureBuilder<List<Object>>(
              future: Future.wait<Object>([_grades, _classes]),
              builder: (context, snapshot) {
                final grades = snapshot.hasData
                    ? snapshot.data![0] as List<SchoolGrade>
                    : <SchoolGrade>[];
                final allClasses = snapshot.hasData
                    ? snapshot.data![1] as List<SchoolClass>
                    : <SchoolClass>[];
                final classes = _gradeId == null
                    ? allClasses
                    : allClasses
                          .where((item) => item.gradeId == _gradeId)
                          .toList();
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('grade-$_gradeId'),
                        value: _gradeId,
                        decoration: const InputDecoration(
                          labelText: 'الصف',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('كل الصفوف'),
                          ),
                          for (final grade in grades)
                            DropdownMenuItem<String?>(
                              value: grade.id,
                              child: Text(
                                grade.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _gradeId = value;
                          _classId = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('class-$_gradeId-$_classId'),
                        value: _classId,
                        decoration: const InputDecoration(
                          labelText: 'الفصل',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('كل الفصول'),
                          ),
                          for (final schoolClass in classes)
                            DropdownMenuItem<String?>(
                              value: schoolClass.id,
                              child: Text(
                                schoolClass.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _classId = value),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (user.role.canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilterChip(
                  selected: _includeInactive,
                  avatar: const Icon(Icons.person_off_outlined, size: 18),
                  label: const Text('إظهار الطلاب غير النشطين'),
                  onSelected: (value) =>
                      setState(() => _includeInactive = value),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Student>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _LoadError(onRetry: () => setState(() {}));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final students = snapshot.data!;
                if (students.isEmpty) {
                  return const _EmptyStudents();
                }
                return RefreshIndicator(
                  onRefresh: () async => refreshData(ref),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    itemCount: students.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final student = students[index];
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    StudentDetailsScreen(studentId: student.id),
                              ),
                            );
                            refreshData(ref);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(13),
                            child: Row(
                              children: [
                                StudentPhoto(
                                  path: student.photoPath,
                                  size: 62,
                                  heroTag: 'student-${student.id}',
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        student.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                      if (student.status != 'active')
                                        const Padding(
                                          padding: EdgeInsets.only(top: 3),
                                          child: Text(
                                            'غير نشط — محفوظ في السجل',
                                            style: TextStyle(
                                              color: AppColors.absent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        student.classLabel.isEmpty
                                            ? 'لم يحدد الصف والفصل'
                                            : student.classLabel,
                                        style: TextStyle(
                                          color: Colors.blueGrey.shade600,
                                        ),
                                      ),
                                      Text(
                                        'السجل: ${student.maskedNationalId}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_left_rounded,
                                  color: Colors.blueGrey,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printBarcodeCards() async {
    final values = await Future.wait<Object>([_grades, _classes]);
    if (!mounted) return;
    final grades = values[0] as List<SchoolGrade>;
    final classes = values[1] as List<SchoolClass>;
    final choice = await showModalBottomSheet<_PrintChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            const ListTile(
              title: Text(
                'نطاق طباعة بطاقات الباركود',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('اختر طالبًا من ملفه، أو اطبع نطاقًا كاملًا هنا.'),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('جميع الطلاب'),
              onTap: () => Navigator.pop(
                context,
                const _PrintChoice(label: 'جميع الطلاب'),
              ),
            ),
            for (final grade in grades) ...[
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text('الصف: ${grade.name}'),
                onTap: () => Navigator.pop(
                  context,
                  _PrintChoice(label: grade.name, gradeId: grade.id),
                ),
              ),
              for (final schoolClass in classes.where(
                (item) => item.gradeId == grade.id,
              ))
                ListTile(
                  contentPadding: const EdgeInsetsDirectional.only(
                    start: 38,
                    end: 18,
                  ),
                  leading: const Icon(Icons.meeting_room_outlined),
                  title: Text('الفصل: ${schoolClass.label}'),
                  onTap: () => Navigator.pop(
                    context,
                    _PrintChoice(
                      label: schoolClass.label,
                      classId: schoolClass.id,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final students = await ref
        .read(studentRepositoryProvider)
        .getAll(gradeId: choice.gradeId, classId: choice.classId);
    if (!mounted) return;
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد طلاب في النطاق المختار.')),
      );
      return;
    }
    final schoolName =
        await ref.read(settingsRepositoryProvider).get('school_name') ?? '';
    final cardSize =
        await ref.read(settingsRepositoryProvider).get('barcode_card_size') ??
        'standard';
    final file = await ref
        .read(reportServiceProvider)
        .generateBarcodeCards(
          students,
          schoolName: schoolName,
          cardSize: cardSize,
        );
    await Printing.layoutPdf(
      name: 'بطاقات باركود - ${choice.label}',
      onLayout: (_) => file.readAsBytes(),
    );
  }
}

class _PrintChoice {
  const _PrintChoice({required this.label, this.gradeId, this.classId});
  final String label;
  final String? gradeId;
  final String? classId;
}

class _EmptyStudents extends StatelessWidget {
  const _EmptyStudents();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_2_outlined,
            size: 78,
            color: Colors.blueGrey.shade300,
          ),
          const SizedBox(height: 14),
          const Text(
            'لا يوجد طلاب حتى الآن',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'أضف طالبًا أو استورد ملف Excel من قسم المزيد.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.absent,
            size: 46,
          ),
          const SizedBox(height: 10),
          const Text('تعذر تحميل الطلاب. لم تُحذف أي بيانات.'),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}
