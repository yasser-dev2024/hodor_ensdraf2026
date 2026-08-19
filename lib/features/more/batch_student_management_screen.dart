import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/school_class.dart';

class BatchStudentManagementScreen extends ConsumerStatefulWidget {
  const BatchStudentManagementScreen({super.key});

  @override
  ConsumerState<BatchStudentManagementScreen> createState() =>
      _BatchStudentManagementScreenState();
}

class _BatchStudentManagementScreenState
    extends ConsumerState<BatchStudentManagementScreen> {
  late Future<_BatchData> _data;
  String? _sourceGradeId;
  String? _targetGradeId;
  String? _deleteGradeId;
  String? _deleteStage;
  Map<String, String> _classMapping = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_BatchData> _load() async => _BatchData(
    grades: await ref.read(classRepositoryProvider).getGrades(),
    classes: await ref.read(classRepositoryProvider).getClasses(),
    stages: await ref.read(studentRepositoryProvider).getActiveStages(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الترحيل السنوي وإدارة الدفعات')),
    body: FutureBuilder<_BatchData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            message: 'تعذر تحميل بيانات الصفوف: ${snapshot.error}',
            onRetry: () => setState(() => _data = _load()),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            _InfoBanner(
              icon: Icons.shield_outlined,
              color: AppColors.present,
              text:
                  'كل عملية تتم داخل معاملة واحدة: إما تنجح كاملة أو لا يتغير أي طالب. يحتفظ التطبيق بسجل النقل والحضور السابق.',
            ),
            const SizedBox(height: 14),
            _sectionTitle('الترحيل السنوي', Icons.upgrade_rounded),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'مثال: ترحيل طلاب رابع إلى خامس دون استيرادهم مرة أخرى.',
                      style: TextStyle(height: 1.5, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _sourceGradeId,
                      decoration: const InputDecoration(
                        labelText: 'الصف الحالي',
                        prefixIcon: Icon(Icons.login_rounded),
                      ),
                      items: data.grades
                          .map(
                            (grade) => DropdownMenuItem(
                              value: grade.id,
                              child: Text(grade.name),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _sourceGradeId = value;
                              if (_targetGradeId == value) {
                                _targetGradeId = null;
                              }
                              _rebuildAutomaticMapping(data);
                            }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _targetGradeId,
                      decoration: const InputDecoration(
                        labelText: 'الصف الجديد',
                        prefixIcon: Icon(Icons.logout_rounded),
                      ),
                      items: data.grades
                          .where((grade) => grade.id != _sourceGradeId)
                          .map(
                            (grade) => DropdownMenuItem(
                              value: grade.id,
                              child: Text(grade.name),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _targetGradeId = value;
                              _rebuildAutomaticMapping(data);
                            }),
                    ),
                    if (_sourceGradeId != null && _targetGradeId != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'ربط الفصول',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'حدد الفصل الجديد لكل فصل حالي. يحاول التطبيق مطابقة الأسماء تلقائيًا.',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 10),
                      for (final sourceClass in data.classes.where(
                        (item) => item.gradeId == _sourceGradeId,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              '${sourceClass.id}-$_targetGradeId-${_classMapping[sourceClass.id]}',
                            ),
                            value: _classMapping[sourceClass.id],
                            decoration: InputDecoration(
                              labelText: '${sourceClass.label} ←',
                            ),
                            items: data.classes
                                .where((item) => item.gradeId == _targetGradeId)
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.id,
                                    child: Text(item.label),
                                  ),
                                )
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    if (value == null) {
                                      _classMapping.remove(sourceClass.id);
                                    } else {
                                      _classMapping[sourceClass.id] = value;
                                    }
                                  }),
                          ),
                        ),
                      FutureBuilder<int>(
                        future: ref
                            .read(studentRepositoryProvider)
                            .activeCount(gradeId: _sourceGradeId),
                        builder: (context, countSnapshot) => Text(
                          'الطلاب النشطون المراد ترحيلهم: ${countSnapshot.data ?? '…'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _promote(data),
                        icon: const Icon(Icons.upgrade_rounded),
                        label: const Text('ترحيل جميع الطلاب الآن'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('تعطيل دفعة كاملة', Icons.person_off_outlined),
            const SizedBox(height: 8),
            _InfoBanner(
              icon: Icons.history_rounded,
              color: AppColors.excused,
              text:
                  'التعطيل حذف آمن (Soft Delete): لا يمحو الطالب ولا تقاريره القديمة، ويمكن إعادة تفعيله لاحقًا.',
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _deleteGradeId,
                      decoration: const InputDecoration(
                        labelText: 'تعطيل صف دراسي كامل',
                        prefixIcon: Icon(Icons.school_outlined),
                      ),
                      items: data.grades
                          .map(
                            (grade) => DropdownMenuItem(
                              value: grade.id,
                              child: Text(grade.name),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _deleteGradeId = value),
                    ),
                    if (_deleteGradeId != null) ...[
                      const SizedBox(height: 10),
                      _BatchCount(gradeId: _deleteGradeId),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _deactivateGrade(data),
                        icon: const Icon(Icons.person_off_outlined),
                        label: const Text('تعطيل جميع طلاب الصف المحدد'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.absent,
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ],
                    if (data.stages.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(),
                      ),
                      DropdownButtonFormField<String>(
                        value: _deleteStage,
                        decoration: const InputDecoration(
                          labelText: 'تعطيل مرحلة كاملة',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                        items: data.stages
                            .map(
                              (stage) => DropdownMenuItem(
                                value: stage,
                                child: Text(stage),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _deleteStage = value),
                      ),
                      if (_deleteStage != null) ...[
                        const SizedBox(height: 10),
                        _BatchCount(stage: _deleteStage),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _deactivateStage(),
                          icon: const Icon(Icons.person_off_outlined),
                          label: const Text('تعطيل جميع طلاب المرحلة المحددة'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.absent,
                            minimumSize: const Size.fromHeight(52),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, color: AppColors.blue),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
          color: AppColors.navy,
        ),
      ),
    ],
  );

  void _rebuildAutomaticMapping(_BatchData data) {
    _classMapping = {};
    if (_sourceGradeId == null || _targetGradeId == null) return;
    final targets = data.classes
        .where((item) => item.gradeId == _targetGradeId)
        .toList();
    for (final source in data.classes.where(
      (item) => item.gradeId == _sourceGradeId,
    )) {
      final normalized = source.name.trim().toLowerCase();
      final matches = targets.where(
        (target) => target.name.trim().toLowerCase() == normalized,
      );
      if (matches.isNotEmpty) {
        _classMapping[source.id] = matches.first.id;
      }
    }
  }

  Future<void> _promote(_BatchData data) async {
    final sourceId = _sourceGradeId;
    final targetId = _targetGradeId;
    if (sourceId == null || targetId == null) return;
    final sourceClasses = data.classes
        .where((item) => item.gradeId == sourceId)
        .toList();
    if (sourceClasses.any((item) => !_classMapping.containsKey(item.id))) {
      _showError('حدد الفصل الجديد لكل فصل في الصف الحالي.');
      return;
    }
    final sourceName = data.grades.firstWhere((g) => g.id == sourceId).name;
    final targetName = data.grades.firstWhere((g) => g.id == targetId).name;
    final confirmed = await _confirm(
      title: 'ترحيل $sourceName إلى $targetName',
      body:
          'سيتم نقل جميع الطلاب النشطين وتسجيل حركة مستقلة لكل طالب. لا يمكن تنفيذ نصف العملية؛ إما تنجح كاملة أو تُلغى كاملة.',
      confirmLabel: 'تنفيذ الترحيل',
    );
    if (!confirmed) return;
    await _run(() async {
      final result = await ref
          .read(studentRepositoryProvider)
          .promoteGrade(
            sourceGradeId: sourceId,
            targetGradeId: targetId,
            classMapping: _classMapping,
            userId: ref.read(currentUserProvider)!.id,
          );
      refreshData(ref);
      if (mounted) {
        await _showSuccess(
          'تم ترحيل ${result.promoted} طالبًا مع حفظ سجل النقل.',
        );
        setState(() {
          _sourceGradeId = null;
          _targetGradeId = null;
          _classMapping = {};
        });
      }
    });
  }

  Future<void> _deactivateGrade(_BatchData data) async {
    final gradeId = _deleteGradeId;
    if (gradeId == null) return;
    final label = data.grades.firstWhere((g) => g.id == gradeId).name;
    final confirmed = await _confirm(
      title: 'تعطيل صف $label كاملًا',
      body:
          'لن تُحذف تقارير أو سجلات سابقة. سيتوقف ظهور الطلاب في المسح والقوائم النشطة فقط.',
      confirmLabel: 'تعطيل الصف كاملًا',
    );
    if (!confirmed) return;
    await _deactivate(gradeId: gradeId);
  }

  Future<void> _deactivateStage() async {
    final stage = _deleteStage;
    if (stage == null) return;
    final confirmed = await _confirm(
      title: 'تعطيل مرحلة $stage كاملة',
      body:
          'لن تُحذف تقارير أو سجلات سابقة. سيتوقف ظهور الطلاب في المسح والقوائم النشطة فقط.',
      confirmLabel: 'تعطيل المرحلة كاملة',
    );
    if (!confirmed) return;
    await _deactivate(stage: stage);
  }

  Future<void> _deactivate({String? gradeId, String? stage}) => _run(() async {
    final count = await ref
        .read(studentRepositoryProvider)
        .deactivateBatch(
          gradeId: gradeId,
          stage: stage,
          userId: ref.read(currentUserProvider)!.id,
        );
    refreshData(ref);
    if (mounted) {
      await _showSuccess('تم تعطيل $count طالبًا دون حذف سجلاتهم السابقة.');
      setState(() {
        _deleteGradeId = null;
        _deleteStage = null;
        _data = _load();
      });
    }
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _showError('تعذر تنفيذ العملية، ولم تُحفظ عملية جزئية: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async =>
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
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showSuccess(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(
        Icons.check_circle_rounded,
        color: AppColors.present,
        size: 44,
      ),
      title: const Text('اكتملت العملية'),
      content: Text(message, textAlign: TextAlign.center),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('حسنًا'),
        ),
      ],
    ),
  );

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class _BatchData {
  const _BatchData({
    required this.grades,
    required this.classes,
    required this.stages,
  });

  final List<SchoolGrade> grades;
  final List<SchoolClass> classes;
  final List<String> stages;
}

class _BatchCount extends ConsumerWidget {
  const _BatchCount({this.gradeId, this.stage});

  final String? gradeId;
  final String? stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<int>(
    future: ref
        .read(studentRepositoryProvider)
        .activeCount(gradeId: gradeId, stage: stage),
    builder: (context, snapshot) => Text(
      'عدد الطلاب النشطين: ${snapshot.data ?? '…'}',
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 52, color: AppColors.absent),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}
