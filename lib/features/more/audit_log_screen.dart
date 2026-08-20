import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('سجل التعديلات')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: ref.read(databaseProvider).db.rawQuery('''
        SELECT a.*, u.name AS user_name FROM audit_logs a
        LEFT JOIN users u ON u.id = a.user_id
        ORDER BY a.occurred_at DESC LIMIT 1000
      '''),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('لا توجد عمليات مسجلة.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = snapshot.data![index];
            final date = DateTime.parse(row['occurred_at'] as String).toLocal();
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE7F2F6),
                  child: Icon(Icons.history_rounded, color: AppColors.blue),
                ),
                title: Text(
                  _label(row['action'] as String),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${row['user_name'] ?? 'النظام'} • ${DateFormat('yyyy/MM/dd - HH:mm').format(date)}',
                ),
                trailing: Text(
                  row['entity_type'] as String? ?? '',
                  style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                ),
                onTap: () => _showDetails(context, row),
              ),
            );
          },
        );
      },
    ),
  );

  static String _label(String action) =>
      const {
        'student_create': 'إضافة طالب',
        'student_update': 'تعديل طالب',
        'student_deactivate': 'تعطيل طالب',
        'student_reactivate': 'إعادة تفعيل طالب',
        'student_batch_deactivate': 'تعطيل دفعة طلاب',
        'student_transfer': 'نقل طالب',
        'grade_promotion': 'ترحيل سنوي لصف كامل',
        'student_graduate': 'تخريج طالب',
        'grade_graduation': 'تخريج صف كامل',
        'academic_year_set': 'تحديد العام الدراسي الحالي',
        'academic_year_rollover': 'إغلاق عام وبدء عام دراسي جديد',
        'attendance_create': 'تسجيل حضور',
        'attendance_update': 'تعديل حالة',
        'attendance_departure': 'تسجيل انصراف طالب',
        'attendance_bulk_present': 'اعتماد الحضور الجماعي عند الإغلاق',
        'excel_import': 'استيراد ملف',
        'student_import': 'استيراد ملف طلاب',
        'day_close': 'إغلاق تقرير اليوم',
        'day_reopen': 'إعادة فتح تقرير اليوم',
        'report_archive_create': 'أرشفة تقرير',
        'backup_restore': 'استعادة نسخة احتياطية',
        'user_create': 'إضافة مستخدم',
        'user_credentials_reset': 'إعادة تعيين بيانات دخول مستخدم',
        'user_deactivate': 'تعطيل مستخدم',
        'login_success': 'تسجيل دخول ناجح',
        'login_failure': 'محاولة دخول فاشلة',
        'class_create': 'إضافة فصل',
        'class_update': 'تعديل فصل',
        'class_delete': 'حذف فصل',
        'class_reorder': 'إعادة ترتيب فصل',
        'grade_create': 'إضافة صف',
        'grade_update': 'تعديل صف',
        'grade_delete': 'حذف صف',
        'grade_reorder': 'إعادة ترتيب صف',
      }[action] ??
      action;

  static Future<void> _showDetails(
    BuildContext context,
    Map<String, Object?> row,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_label(row['action'] as String)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('المعرف: ${row['entity_id'] ?? '—'}'),
            const SizedBox(height: 12),
            const Text(
              'القيمة السابقة',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            SelectableText('${row['old_value'] ?? '—'}'),
            const SizedBox(height: 12),
            const Text(
              'القيمة الجديدة',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            SelectableText('${row['new_value'] ?? '—'}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
