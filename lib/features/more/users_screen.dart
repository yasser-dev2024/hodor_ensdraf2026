import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_user.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentUserProvider)!;
    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمون والصلاحيات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('إضافة مستخدم'),
      ),
      body: FutureBuilder<List<AppUser>>(
        key: ValueKey(_revision),
        future: ref.read(authRepositoryProvider).getUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _MessageState(
              icon: Icons.error_outline_rounded,
              title: 'تعذر تحميل المستخدمين',
              subtitle: _friendlyError(snapshot.error!),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: _roleColor(
                      user.role,
                    ).withValues(alpha: .12),
                    child: Icon(
                      _roleIcon(user.role),
                      color: _roleColor(user.role),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (user.id == current.id)
                        const Chip(
                          label: Text('الحالي'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  subtitle: Text(user.role.label),
                  trailing: PopupMenuButton<_UserAction>(
                    onSelected: (action) => switch (action) {
                      _UserAction.credentials => _resetCredentials(user),
                      _UserAction.deactivate => _deactivate(user),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _UserAction.credentials,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.password_rounded),
                          title: Text('تغيير بيانات الدخول'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _UserAction.deactivate,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.person_off_outlined,
                            color: AppColors.absent,
                          ),
                          title: Text('تعطيل المستخدم'),
                        ),
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

  Future<void> _add() async {
    final form = await showDialog<_UserFormValue>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _UserFormDialog(),
    );
    if (form == null || !mounted) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .createUser(
            name: form.name,
            password: form.password,
            role: form.role,
            actorId: ref.read(currentUserProvider)!.id,
          );
      if (!mounted) return;
      setState(() => _revision++);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت إضافة المستخدم.')));
    } catch (error) {
      if (mounted) _showError(_friendlyError(error));
    }
  }

  Future<void> _resetCredentials(AppUser user) async {
    final form = await showDialog<_CredentialFormValue>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CredentialDialog(userName: user.name),
    );
    if (form == null || !mounted) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .resetCredentials(
            userId: user.id,
            password: form.password,
            actorId: ref.read(currentUserProvider)!.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تحديث بيانات دخول ${user.name}.')),
      );
    } catch (error) {
      if (mounted) _showError(_friendlyError(error));
    }
  }

  Future<void> _deactivate(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعطيل المستخدم'),
        content: Text(
          'سيُمنع ${user.name} من تسجيل الدخول مع الاحتفاظ بسجل عملياته. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تعطيل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .deactivateUser(
            userId: user.id,
            actorId: ref.read(currentUserProvider)!.id,
          );
      if (mounted) setState(() => _revision++);
    } catch (error) {
      if (mounted) _showError(_friendlyError(error));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.absent),
    );
  }

  static String _friendlyError(Object error) => '$error'
      .replaceFirst('FormatException: ', '')
      .replaceFirst('Bad state: ', '');

  static Color _roleColor(UserRole role) => switch (role) {
    UserRole.manager => AppColors.navy,
    UserRole.attendanceOfficer => AppColors.teal,
    UserRole.studentAffairs => AppColors.excused,
  };

  static IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.manager => Icons.admin_panel_settings_rounded,
    UserRole.attendanceOfficer => Icons.qr_code_scanner_rounded,
    UserRole.studentAffairs => Icons.analytics_outlined,
  };
}

enum _UserAction { credentials, deactivate }

class _UserFormValue {
  const _UserFormValue({
    required this.name,
    required this.password,
    required this.role,
  });

  final String name;
  final String password;
  final UserRole role;
}

class _CredentialFormValue {
  const _CredentialFormValue({required this.password});

  final String password;
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog();

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.attendanceOfficer;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة مستخدم'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              ),
              const SizedBox(height: 9),
              DropdownButtonFormField<UserRole>(
                value: _role,
                decoration: const InputDecoration(labelText: 'الصلاحية'),
                items: UserRole.values
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              const SizedBox(height: 9),
              _secretField(_password, 'كلمة المرور'),
              const SizedBox(height: 6),
              const Text(
                '8 محارف على الأقل وتحتوي حرفًا ورقمًا.',
                style: TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('إضافة')),
      ],
    );
  }

  Widget _secretField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.visiblePassword,
        decoration: InputDecoration(labelText: label),
      );

  void _submit() {
    Navigator.pop(
      context,
      _UserFormValue(name: _name.text, password: _password.text, role: _role),
    );
  }
}

class _CredentialDialog extends StatefulWidget {
  const _CredentialDialog({required this.userName});

  final String userName;

  @override
  State<_CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<_CredentialDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('بيانات دخول ${widget.userName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_password, 'كلمة المرور الجديدة'),
            const SizedBox(height: 6),
            const Text(
              '8 محارف على الأقل وتحتوي حرفًا ورقمًا.',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    obscureText: true,
    keyboardType: TextInputType.visiblePassword,
    decoration: InputDecoration(labelText: label),
  );

  void _submit() {
    Navigator.pop(context, _CredentialFormValue(password: _password.text));
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.blue),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.blueGrey),
          ),
        ],
      ),
    ),
  );
}
