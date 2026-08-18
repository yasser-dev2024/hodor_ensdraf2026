import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../shell/app_shell.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  late Future<bool> _hasUsers;

  @override
  void initState() {
    super.initState();
    _hasUsers = ref.read(authRepositoryProvider).hasUsers();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user != null) return const AppShell();
    return FutureBuilder<bool>(
      future: _hasUsers,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == false) {
          return InitialSetupScreen(
            onCreated: () => setState(() => _hasUsers = Future.value(true)),
          );
        }
        return const LoginScreen();
      },
    );
  }
}

class _AuthFrame extends StatelessWidget {
  const _AuthFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0xFFD7E8EF)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x24153A5B),
                          blurRadius: 22,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(21),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blueGrey.shade600,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InitialSetupScreen extends ConsumerStatefulWidget {
  const InitialSetupScreen({required this.onCreated, super.key});
  final VoidCallback onCreated;

  @override
  ConsumerState<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends ConsumerState<InitialSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'إعداد النظام لأول مرة',
      subtitle:
          'أنشئ حساب المدير. لا توجد كلمة مرور افتراضية، وتُحفظ بيانات الدخول بصورة مشفّرة.',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'اسم المدير',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => value == null || value.trim().length < 2
                  ? 'أدخل اسمًا صحيحًا'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pin,
              obscureText: _obscure,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'رمز PIN قوي (6 أرقام أو أكثر)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => value == null || value.length < 6
                  ? 'أدخل 6 أرقام على الأقل'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'تأكيد رمز PIN',
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
              validator: (value) =>
                  value != _pin.text ? 'الرمزان غير متطابقين' : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('إنشاء حساب المدير'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .createInitialManager(name: _name.text, pin: _pin.text);
      await const FlutterSecureStorage().write(
        key: 'last_user_id',
        value: user.id,
      );
      ref.read(currentUserProvider.notifier).state = user;
      widget.onCreated();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _pin = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'الحضور الصباحي للطلاب',
      subtitle: 'سجّل الدخول للوصول إلى بيانات المدرسة وتسجيل الحالات.',
      child: Column(
        children: [
          TextField(
            controller: _pin,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _login(),
            decoration: const InputDecoration(
              labelText: 'رمز PIN',
              prefixIcon: Icon(Icons.password_rounded),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _login,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.login_rounded),
            label: const Text('تسجيل الدخول'),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _busy ? null : _biometricLogin,
            icon: const Icon(Icons.fingerprint_rounded),
            label: const Text('الدخول بالبصمة'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (_pin.text.isEmpty) return;
    setState(() => _busy = true);
    final user = await ref.read(authRepositoryProvider).login(_pin.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('رمز PIN غير صحيح.')));
      return;
    }
    await const FlutterSecureStorage().write(
      key: 'last_user_id',
      value: user.id,
    );
    ref.read(currentUserProvider.notifier).state = user;
  }

  Future<void> _biometricLogin() async {
    setState(() => _busy = true);
    try {
      final lastUserId = await const FlutterSecureStorage().read(
        key: 'last_user_id',
      );
      if (lastUserId == null) {
        throw StateError('سجّل الدخول برمز PIN مرة واحدة أولًا.');
      }
      final localAuth = LocalAuthentication();
      if (!await localAuth.isDeviceSupported()) {
        throw StateError('البصمة غير متاحة على هذا الجهاز.');
      }
      final authenticated = await localAuth.authenticate(
        localizedReason: 'التحقق للدخول إلى نظام الحضور',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!authenticated) return;
      final user = await ref
          .read(authRepositoryProvider)
          .getUserById(lastUserId);
      if (user == null) throw StateError('المستخدم السابق غير متاح.');
      ref.read(currentUserProvider.notifier).state = user;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
