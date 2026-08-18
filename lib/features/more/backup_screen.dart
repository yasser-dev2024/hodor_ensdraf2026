import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.enhanced_encryption_outlined,
                    color: AppColors.teal,
                    size: 32,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نسخة مشفّرة بالكامل',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'تتضمن قاعدة البيانات وصور الطلاب ومفتاح تشفير البيانات. لا يمكن فتحها دون كلمة المرور التي تختارها.',
                          style: TextStyle(height: 1.55),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _BackupAction(
            icon: Icons.backup_rounded,
            title: 'إنشاء نسخة احتياطية',
            subtitle: 'احفظها في مكان آمن أو شاركها إلى مساحة تخزين موثوقة.',
            button: 'إنشاء ومشاركة',
            onTap: _busy ? null : _create,
          ),
          const SizedBox(height: 13),
          _BackupAction(
            icon: Icons.restore_rounded,
            title: 'استعادة نسخة احتياطية',
            subtitle:
                'يتم فحص سلامة الملف والإصدار وإنشاء نسخة أمان من البيانات الحالية قبل الاستعادة.',
            button: 'اختيار نسخة واستعادتها',
            destructive: true,
            onTap: _busy ? null : _restore,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(26),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text('جارٍ تنفيذ العملية بأمان...'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _askPassword({required bool confirm}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirm ? 'كلمة مرور النسخة الجديدة' : 'كلمة مرور النسخة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: '8 أحرف على الأقل'),
            ),
            if (confirm) ...[
              const SizedBox(height: 10),
              TextField(
                controller: second,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (first.text.length < 8) return;
              if (confirm && first.text != second.text) return;
              Navigator.pop(context, first.text);
            },
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _create() async {
    final password = await _askPassword(confirm: true);
    if (password == null) return;
    setState(() => _busy = true);
    try {
      final file = await ref
          .read(backupServiceProvider)
          .createBackup(password: password);
      await SharePlus.instance.share(
        ShareParams(subject: 'نسخة احتياطية للحضور', files: [XFile(file.path)]),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر إنشاء النسخة: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: const ['msab'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    final password = await _askPassword(confirm: false);
    if (password == null) return;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: const Text(
          'سيتم استبدال البيانات الحالية بعد إنشاء نسخة أمان تلقائية والتحقق من الملف. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      final safety = await ref
          .read(backupServiceProvider)
          .restoreBackup(backupPath: path, password: password);
      refreshData(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت الاستعادة بنجاح. حُفظت نسخة البيانات السابقة في:\n${safety.path}',
            ),
            backgroundColor: AppColors.present,
            duration: const Duration(seconds: 7),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم تتم الاستعادة: $error'),
            backgroundColor: AppColors.absent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _BackupAction extends StatelessWidget {
  const _BackupAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback? onTap;
  final bool destructive;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 38,
            color: destructive ? AppColors.excused : AppColors.blue,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(height: 1.5, color: Colors.blueGrey),
          ),
          const SizedBox(height: 15),
          FilledButton.tonal(onPressed: onTap, child: Text(button)),
        ],
      ),
    ),
  );
}
