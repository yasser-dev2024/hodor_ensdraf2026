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
        'student_transfer': 'نقل طالب',
        'attendance_create': 'تسجيل حضور',
        'attendance_update': 'تعديل حالة',
        'excel_import': 'استيراد ملف',
        'day_close': 'إغلاق تقرير اليوم',
        'backup_restore': 'استعادة نسخة احتياطية',
        'user_create': 'إضافة مستخدم',
        'class_create': 'إضافة فصل',
        'grade_create': 'إضافة صف',
      }[action] ??
      action;
}
