import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/school_class.dart';

class ClassManagementScreen extends ConsumerStatefulWidget {
  const ClassManagementScreen({super.key});

  @override
  ConsumerState<ClassManagementScreen> createState() =>
      _ClassManagementScreenState();
}

class _ClassManagementScreenState extends ConsumerState<ClassManagementScreen> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(classRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الصفوف والفصول')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGrade,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة صف'),
      ),
      body: FutureBuilder<(List<SchoolGrade>, List<SchoolClass>)>(
        key: ValueKey(_revision),
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (grades, classes) = snapshot.data!;
          if (grades.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.meeting_room_outlined,
                      size: 76,
                      color: Colors.blueGrey,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'أضف الصف الأول ثم أضف فصوله.',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
            itemCount: grades.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex--;
              final items = [...grades];
              final moved = items.removeAt(oldIndex);
              items.insert(newIndex, moved);
              for (var i = 0; i < items.length; i++) {
                await repository.updateGradeOrder(items[i].id, i);
              }
              setState(() => _revision++);
            },
            itemBuilder: (context, index) {
              final grade = grades[index];
              final gradeClasses = classes
                  .where((item) => item.gradeId == grade.id)
                  .toList();
              return Padding(
                key: ValueKey(grade.id),
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE1F0F6),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(
                      grade.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    subtitle: Text('${gradeClasses.length} فصول'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'add') _addClass(grade);
                        if (value == 'rename') _renameGrade(grade);
                        if (value == 'delete') _deleteGrade(grade);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'add',
                          child: ListTile(
                            leading: Icon(Icons.add_rounded),
                            title: Text('إضافة فصل'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'rename',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('تعديل الاسم'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(
                              Icons.delete_outline,
                              color: AppColors.absent,
                            ),
                            title: Text('حذف الصف'),
                          ),
                        ),
                      ],
                    ),
                    children: [
                      if (gradeClasses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('لا توجد فصول في هذا الصف.'),
                        ),
                      for (final schoolClass in gradeClasses)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 28,
                          ),
                          leading: const Icon(
                            Icons.meeting_room_outlined,
                            color: AppColors.teal,
                          ),
                          title: Text(schoolClass.name),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'rename') _renameClass(schoolClass);
                              if (value == 'delete') _deleteClass(schoolClass);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('تعديل'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('حذف'),
                              ),
                            ],
                          ),
                        ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 28,
                        ),
                        leading: const Icon(
                          Icons.add_circle_outline_rounded,
                          color: AppColors.blue,
                        ),
                        title: const Text('إضافة فصل'),
                        onTap: () => _addClass(grade),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<(List<SchoolGrade>, List<SchoolClass>)> _load() async {
    final repository = ref.read(classRepositoryProvider);
    return (await repository.getGrades(), await repository.getClasses());
  }

  Future<String?> _nameDialog(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'الاسم'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addGrade() async {
    final name = await _nameDialog('إضافة صف');
    if (name == null) return;
    await _run(
      () => ref
          .read(classRepositoryProvider)
          .addGrade(name, userId: ref.read(currentUserProvider)!.id),
    );
  }

  Future<void> _addClass(SchoolGrade grade) async {
    final name = await _nameDialog('إضافة فصل إلى ${grade.name}');
    if (name == null) return;
    await _run(
      () => ref
          .read(classRepositoryProvider)
          .addClass(grade.id, name, userId: ref.read(currentUserProvider)!.id),
    );
  }

  Future<void> _renameGrade(SchoolGrade grade) async {
    final name = await _nameDialog('تعديل اسم الصف', initial: grade.name);
    if (name == null) return;
    await _run(
      () => ref
          .read(classRepositoryProvider)
          .renameGrade(
            grade.id,
            name,
            userId: ref.read(currentUserProvider)!.id,
          ),
    );
  }

  Future<void> _renameClass(SchoolClass schoolClass) async {
    final name = await _nameDialog(
      'تعديل اسم الفصل',
      initial: schoolClass.name,
    );
    if (name == null) return;
    await _run(
      () => ref
          .read(classRepositoryProvider)
          .renameClass(
            schoolClass.id,
            name,
            userId: ref.read(currentUserProvider)!.id,
          ),
    );
  }

  Future<void> _deleteGrade(SchoolGrade grade) async {
    final confirm = await _confirm(
      'حذف ${grade.name}',
      'لا يمكن حذف الصف إذا كان يحتوي على فصول أو طلاب مرتبطين.',
    );
    if (confirm) {
      await _run(
        () => ref
            .read(classRepositoryProvider)
            .deleteGrade(grade.id, userId: ref.read(currentUserProvider)!.id),
      );
    }
  }

  Future<void> _deleteClass(SchoolClass schoolClass) async {
    final confirm = await _confirm(
      'حذف ${schoolClass.label}',
      'لا يمكن حذف الفصل إذا كان مرتبطًا بطلاب أو سجلات.',
    );
    if (confirm) {
      await _run(
        () => ref
            .read(classRepositoryProvider)
            .deleteClass(
              schoolClass.id,
              userId: ref.read(currentUserProvider)!.id,
            ),
      );
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<Object?> Function() action) async {
    try {
      await action();
      refreshData(ref);
      if (mounted) setState(() => _revision++);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر تنفيذ العملية. قد تكون هناك بيانات مرتبطة.\n$error',
            ),
          ),
        );
      }
    }
  }
}
