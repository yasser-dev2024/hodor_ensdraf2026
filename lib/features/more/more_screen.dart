import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'audit_log_screen.dart';
import 'backup_screen.dart';
import 'class_management_screen.dart';
import 'import_screen.dart';
import 'school_calendar_screen.dart';
import 'settings_screen.dart';
import 'users_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          Text(
            'المزيد',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${user.name} • ${user.role.label}',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 20),
          if (user.role.canManage) ...[
            const _SectionTitle('إدارة البيانات'),
            _MoreTile(
              icon: Icons.upload_file_rounded,
              color: AppColors.blue,
              title: 'استيراد الطلاب',
              subtitle: 'Excel XLSX / XLS وPDF النصي',
              onTap: () => _open(context, const ImportScreen()),
            ),
            _MoreTile(
              icon: Icons.account_tree_outlined,
              color: AppColors.teal,
              title: 'الصفوف والفصول',
              subtitle: 'إضافة وتعديل وترتيب الفصول',
              onTap: () => _open(context, const ClassManagementScreen()),
            ),
            _MoreTile(
              icon: Icons.calendar_month_outlined,
              color: AppColors.excused,
              title: 'أيام الدراسة والتقويم',
              subtitle: 'الإجازات والاختبارات والأيام المستثناة',
              onTap: () => _open(context, const SchoolCalendarScreen()),
            ),
            const SizedBox(height: 17),
            const _SectionTitle('الأمان والإدارة'),
            _MoreTile(
              icon: Icons.manage_accounts_outlined,
              color: AppColors.blue,
              title: 'المستخدمون والصلاحيات',
              subtitle: 'مدير، مسؤول حضور، وكيل طلاب',
              onTap: () => _open(context, const UsersScreen()),
            ),
            _MoreTile(
              icon: Icons.history_rounded,
              color: AppColors.navy,
              title: 'سجل التعديلات',
              subtitle: 'توثيق العمليات الحساسة ومن نفذها',
              onTap: () => _open(context, const AuditLogScreen()),
            ),
            _MoreTile(
              icon: Icons.security_update_good_outlined,
              color: AppColors.present,
              title: 'النسخ الاحتياطي',
              subtitle: 'نسخة مشفرة واستعادة مع فحص السلامة',
              onTap: () => _open(context, const BackupScreen()),
            ),
            const SizedBox(height: 17),
          ],
          const _SectionTitle('الإعدادات'),
          _MoreTile(
            icon: Icons.settings_outlined,
            color: AppColors.blue,
            title: 'إعدادات المدرسة',
            subtitle: 'الاسم والشعار والعام وبيانات التواصل',
            onTap: user.role.canManage
                ? () => _open(context, const SettingsScreen())
                : null,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: AppColors.absent,
              ),
              title: const Text(
                'تسجيل الخروج',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.absent,
                ),
              ),
              onTap: () => ref.read(currentUserProvider.notifier).state = null,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'الإصدار 1.0.0 • يعمل محليًا بدون إنترنت',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }

  static void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        color: AppColors.navy,
        fontSize: 15,
      ),
    ),
  );
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      child: ListTile(
        enabled: onTap != null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: onTap,
      ),
    ),
  );
}
