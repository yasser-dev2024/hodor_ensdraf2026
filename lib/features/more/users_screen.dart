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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المستخدمون والصلاحيات')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.person_add_alt_rounded),
      label: const Text('مستخدم جديد'),
    ),
    body: FutureBuilder<List<AppUser>>(
      key: ValueKey(_revision),
      future: ref.read(authRepositoryProvider).getUsers(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            final user = snapshot.data![index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE4F1F5),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppColors.blue,
                  ),
                ),
                title: Text(
                  user.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(user.role.label),
                trailing: _RoleBadge(role: user.role),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> _add() async {
    final name = TextEditingController();
    final pin = TextEditingController();
    UserRole role = UserRole.attendanceOfficer;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة مستخدم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIN قوي (6 أرقام أو أكثر)',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<UserRole>(
                value: role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: UserRole.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => role = value);
                },
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
                try {
                  await ref
                      .read(authRepositoryProvider)
                      .createUser(
                        name: name.text,
                        pin: pin.text,
                        role: role,
                        actorId: ref.read(currentUserProvider)!.id,
                      );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$error')));
                  }
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    pin.dispose();
    if (created == true && mounted) setState(() => _revision++);
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final UserRole role;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF4F7),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      role == UserRole.manager
          ? 'كامل'
          : role == UserRole.attendanceOfficer
          ? 'مسح'
          : 'تقارير',
      style: const TextStyle(
        fontSize: 11,
        color: AppColors.blue,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
