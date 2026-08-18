import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    ref.watch(dataRevisionProvider);
    final user = ref.watch(currentUserProvider)!;
    final future = ref.read(studentRepositoryProvider).getAll(query: _query);
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
                hintText: 'بحث بالاسم أو آخر أرقام السجل أو الرقم الأكاديمي',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Student>>(
              future: future,
              builder: (context, snapshot) {
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
