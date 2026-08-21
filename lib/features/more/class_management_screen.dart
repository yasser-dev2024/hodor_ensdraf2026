import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/school_class.dart';
import '../../repositories/class_repository.dart';

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
                await repository.updateGradeOrder(
                  items[i].id,
                  i,
                  userId: ref.read(currentUserProvider)!.id,
                );
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
                      if (gradeClasses.isNotEmpty)
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: gradeClasses.length,
                          onReorder: (oldIndex, newIndex) async {
                            if (newIndex > oldIndex) newIndex--;
                            final items = [...gradeClasses];
                            final moved = items.removeAt(oldIndex);
                            items.insert(newIndex, moved);
                            for (var i = 0; i < items.length; i++) {
                              await repository.updateClassOrder(
                                items[i].id,
                                i,
                                userId: ref.read(currentUserProvider)!.id,
                              );
                            }
                            if (mounted) setState(() => _revision++);
                          },
                          itemBuilder: (context, classIndex) {
                            final schoolClass = gradeClasses[classIndex];
                            return ListTile(
                              key: ValueKey(schoolClass.id),
                              contentPadding: const EdgeInsetsDirectional.only(
                                start: 28,
                                end: 12,
                              ),
                              leading: ReorderableDragStartListener(
                                index: classIndex,
                                child: const Icon(
                                  Icons.drag_indicator_rounded,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              title: Text(schoolClass.name),
                              subtitle: const Text(
                                'اسحب المقبض لإعادة الترتيب',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') {
                                    _renameClass(schoolClass);
                                  }
                                  if (value == 'delete') {
                                    _deleteClass(schoolClass);
                                  }
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
                            );
                          },
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
    try {
      final repository = ref.read(classRepositoryProvider);
      final impact = await repository.gradeDeletionImpact(grade.id);
      if (!mounted) return;
      final confirm = await _confirmPermanentDeletion(
        title: 'حذف صف ${grade.name} نهائيًا',
        body:
            'سيُحذف الصف وجميع فصوله وطلابه وسجلاتهم التابعة من التطبيق. لا يمكن التراجع عن هذه العملية، ويمكن إنشاء الصف واستيراد طلابه لاحقًا كبيانات جديدة.',
        impact: impact,
      );
      if (confirm) {
        await _run(
          () => repository.deleteGrade(
            grade.id,
            userId: ref.read(currentUserProvider)!.id,
          ),
          successMessage: 'تم حذف صف ${grade.name} وجميع بياناته التابعة.',
        );
      }
    } catch (_) {
      _showSafeError();
    }
  }

  Future<void> _deleteClass(SchoolClass schoolClass) async {
    try {
      final repository = ref.read(classRepositoryProvider);
      final impact = await repository.classDeletionImpact(schoolClass.id);
      if (!mounted) return;
      final confirm = await _confirmPermanentDeletion(
        title: 'حذف ${schoolClass.label} نهائيًا',
        body:
            'سيُحذف الفصل وطلابه وسجلات الحضور والنقل والتخريج التابعة له. لا يمكن التراجع، ويمكن إعادة الفصل وطلابه لاحقًا عن طريق الإضافة أو الاستيراد.',
        impact: impact,
      );
      if (confirm) {
        await _run(
          () => repository.deleteClass(
            schoolClass.id,
            userId: ref.read(currentUserProvider)!.id,
          ),
          successMessage: 'تم حذف ${schoolClass.label} وجميع بياناته التابعة.',
        );
      }
    } catch (_) {
      _showSafeError();
    }
  }

  Future<bool> _confirmPermanentDeletion({
    required String title,
    required String body,
    required DeletionImpact impact,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          var acknowledged = false;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.absent,
                size: 48,
              ),
              title: Text(title, textAlign: TextAlign.center),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(body, style: const TextStyle(height: 1.55)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (impact.classes > 0)
                          _impactChip('الفصول', impact.classes),
                        _impactChip('الطلاب', impact.students),
                        _impactChip('سجلات الحضور', impact.attendanceRecords),
                        if (impact.transferRecords > 0)
                          _impactChip('سجلات النقل', impact.transferRecords),
                        if (impact.graduationRecords > 0)
                          _impactChip(
                            'سجلات التخريج',
                            impact.graduationRecords,
                          ),
                        if (impact.reportArchives > 0)
                          _impactChip(
                            'ملفات التقارير الخاصة',
                            impact.reportArchives,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: acknowledged,
                      onChanged: (value) =>
                          setDialogState(() => acknowledged = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'أفهم أن الحذف نهائي وسيزيل البيانات التابعة.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: acknowledged
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.absent,
                  ),
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('حذف نهائي'),
                ),
              ],
            ),
          );
        },
      ) ??
      false;

  Widget _impactChip(String label, int count) => Chip(
    label: Text('$label: $count'),
    side: BorderSide(color: AppColors.absent.withValues(alpha: .22)),
  );

  Future<void> _run(
    Future<Object?> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      refreshData(ref);
      if (mounted) {
        setState(() => _revision++);
        if (successMessage != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(successMessage)));
        }
      }
    } catch (_) {
      _showSafeError();
    }
  }

  void _showSafeError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تعذر تنفيذ العملية بأمان، ولم يُحذف أي جزء من البيانات.',
        ),
      ),
    );
  }
}
