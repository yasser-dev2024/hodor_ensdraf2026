import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class SchoolCalendarScreen extends ConsumerStatefulWidget {
  const SchoolCalendarScreen({super.key});
  @override
  ConsumerState<SchoolCalendarScreen> createState() =>
      _SchoolCalendarScreenState();
}

class _SchoolCalendarScreenState extends ConsumerState<SchoolCalendarScreen> {
  int _revision = 0;
  static const types = {
    'school': 'يوم دراسي',
    'holiday': 'إجازة',
    'exam': 'اختبارات',
    'excluded': 'يوم مستثنى',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('أيام الدراسة والتقويم')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.event_available_rounded),
      label: const Text('تحديد يوم'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      key: ValueKey(_revision),
      future: ref.read(settingsRepositoryProvider).getSchoolDays(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final days = snapshot.data!;
        if (days.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'حدد أيام الإجازات والاختبارات والاستثناءات لتحسين دقة الإحصائيات.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
          itemCount: days.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = days[index];
            final date = DateTime.parse(item['day'] as String);
            final type = item['type'] as String;
            return Card(
              child: ListTile(
                leading: Icon(
                  type == 'holiday'
                      ? Icons.beach_access_outlined
                      : type == 'exam'
                      ? Icons.edit_calendar_outlined
                      : Icons.event_available_outlined,
                  color: type == 'holiday' ? AppColors.absent : AppColors.blue,
                ),
                title: Text(
                  DateFormat('EEEE، d MMMM yyyy', 'ar').format(date),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${types[type] ?? type}${item['note'] == null ? '' : ' • ${item['note']}'}',
                ),
                trailing: IconButton(
                  onPressed: () async {
                    await ref
                        .read(settingsRepositoryProvider)
                        .deleteSchoolDay(item['day'] as String);
                    setState(() => _revision++);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> _add() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: DateTime.now(),
      locale: const Locale('ar', 'SA'),
    );
    if (date == null || !mounted) return;
    var type = 'holiday';
    final note = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(DateFormat('d MMMM yyyy', 'ar').format(date)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'نوع اليوم'),
                items: types.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => type = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختيارية)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setSchoolDay(
                      DateFormat('yyyy-MM-dd').format(date),
                      type,
                      note.text.trim().isEmpty ? null : note.text.trim(),
                    );
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    note.dispose();
    if (saved == true && mounted) setState(() => _revision++);
  }
}
