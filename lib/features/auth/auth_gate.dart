import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_user.dart';
import '../../repositories/auth_repository.dart';
import '../shell/app_shell.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  static const _storage = FlutterSecureStorage();
  static const _lastUserKey = 'last_authenticated_user_id';

  final _managerName = TextEditingController();
  final _setupPassword = TextEditingController();
  final _credential = TextEditingController();
  final _managerNameFocus = FocusNode(debugLabel: 'manager-name');
  final _setupPasswordFocus = FocusNode(debugLabel: 'setup-password');
  final _credentialFocus = FocusNode(debugLabel: 'login-password');

  bool _loading = true;
  bool _busy = false;
  bool _needsSetup = false;
  bool _enableBiometricAfterLogin = false;
  bool _biometricAvailable = false;
  bool _obscureCredential = true;
  bool _obscureSetupPassword = true;
  String? _error;
  String? _selectedUserId;
  String? _lastUserId;
  List<AppUser> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _managerName.dispose();
    _setupPassword.dispose();
    _credential.dispose();
    _managerNameFocus.dispose();
    _setupPasswordFocus.dispose();
    _credentialFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repository = ref.read(authRepositoryProvider);
      final needsSetup = await repository.needsInitialSetup();
      final users = needsSetup
          ? const <AppUser>[]
          : await repository.getUsers();
      if (!mounted) return;
      setState(() {
        _needsSetup = needsSetup;
        _users = users;
        _selectedUserId = users.firstOrNull?.id;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _busy) return;
        _showKeyboard(needsSetup ? _managerNameFocus : _credentialFocus);
      });
      if (!needsSetup) unawaited(_loadLoginPreferences(users));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _loadLoginPreferences(List<AppUser> users) async {
    var biometricAvailable = false;
    String? lastUserId;
    try {
      biometricAvailable = await LocalAuthentication()
          .isDeviceSupported()
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      biometricAvailable = false;
    }
    try {
      lastUserId = await _storage
          .read(key: _lastUserKey)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      lastUserId = null;
    }
    if (!mounted) return;
    setState(() {
      _biometricAvailable = biometricAvailable;
      _lastUserId = lastUserId;
      if (users.any((user) => user.id == lastUserId)) {
        _selectedUserId = lastUserId;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppUser?>(currentUserProvider, (previous, next) {
      if (previous != null && next == null) {
        unawaited(_resetAfterLogout());
      }
    });
    final currentUser = ref.watch(currentUserProvider);
    if (currentUser != null) return const AppShell();
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _AuthFrame(
      title: _needsSetup ? 'إعداد مدير النظام' : 'تسجيل الدخول',
      subtitle: _needsSetup
          ? 'أدخل اسم المستخدم وكلمة المرور فقط.'
          : 'اختر اسم المستخدم وأدخل كلمة المرور.',
      child: _needsSetup ? _buildSetupForm() : _buildLoginForm(),
    );
  }

  Future<void> _resetAfterLogout() async {
    _credential.clear();
    _setupPassword.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
      _enableBiometricAfterLogin = false;
      _obscureCredential = true;
      _obscureSetupPassword = true;
    });
    await _load();
  }

  Widget _buildSetupForm() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('setup_manager_name'),
            controller: _managerName,
            focusNode: _managerNameFocus,
            enabled: !_busy,
            autofocus: true,
            onTap: () => _showKeyboard(_managerNameFocus),
            onSubmitted: (_) => _showKeyboard(_setupPasswordFocus),
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('setup_password'),
            controller: _setupPassword,
            focusNode: _setupPasswordFocus,
            enabled: !_busy,
            onTap: () => _showKeyboard(_setupPasswordFocus),
            onSubmitted: _busy ? null : (_) => _setupManager(),
            obscureText: _obscureSetupPassword,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'كلمة مرور قوية',
              helperText: '8 محارف على الأقل: حرف ورقم',
              prefixIcon: const Icon(Icons.password_rounded),
              suffixIcon: IconButton(
                tooltip: _obscureSetupPassword
                    ? 'إظهار كلمة المرور'
                    : 'إخفاء كلمة المرور',
                onPressed: () => setState(
                  () => _obscureSetupPassword = !_obscureSetupPassword,
                ),
                icon: Icon(
                  _obscureSetupPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          _errorMessage(),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('setup_submit'),
            onPressed: _busy ? null : _setupManager,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.admin_panel_settings_rounded),
            label: const Text('حفظ المدير والدخول'),
          ),
        ],
      ),
    );
  }

  void _showKeyboard(FocusNode focusNode) {
    if (!focusNode.canRequestFocus || _busy) return;
    focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusNode.hasFocus) return;
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  Widget _buildLoginForm() {
    if (_users.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'لا يوجد مستخدم نشط. أعد تهيئة حساب المدير.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة الفحص'),
          ),
        ],
      );
    }
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedUserId,
            decoration: const InputDecoration(
              labelText: 'المستخدم',
              prefixIcon: Icon(Icons.account_circle_outlined),
            ),
            items: _users
                .map(
                  (user) => DropdownMenuItem(
                    value: user.id,
                    child: Text('${user.name} • ${user.role.label}'),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _selectedUserId = value;
                    _credential.clear();
                    _error = null;
                  }),
          ),
          const SizedBox(height: 13),
          TextField(
            key: const ValueKey('login_password'),
            controller: _credential,
            focusNode: _credentialFocus,
            enabled: !_busy,
            autofocus: true,
            onTap: () => _showKeyboard(_credentialFocus),
            obscureText: _obscureCredential,
            keyboardType: TextInputType.visiblePassword,
            autofillHints: const [AutofillHints.password],
            onSubmitted: _busy ? null : (_) => _login(),
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscureCredential = !_obscureCredential),
                icon: Icon(
                  _obscureCredential
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          if (_biometricAvailable)
            CheckboxListTile(
              value: _enableBiometricAfterLogin,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('تفعيل البصمة لهذا المستخدم بعد الدخول'),
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _enableBiometricAfterLogin = value ?? false,
                    ),
            ),
          _errorMessage(),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _login,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.login_rounded),
            label: const Text('دخول آمن'),
          ),
          if (_biometricAvailable && _lastUserId != null) ...[
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: _busy ? null : _biometricLogin,
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('الدخول بالبصمة'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorMessage() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Text(
        _error!,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.absent,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      ),
    );
  }

  Future<void> _setupManager() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .setupInitialManager(
            name: _managerName.text,
            password: _setupPassword.text,
          );
      if (!mounted) return;
      ref.read(currentUserProvider.notifier).state = user;
      unawaited(_rememberUser(user.id));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _login() async {
    final userId = _selectedUserId;
    if (userId == null || _credential.text.isEmpty) {
      setState(() => _error = 'اختر المستخدم وأدخل بيانات الدخول.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(authRepositoryProvider)
        .authenticate(
          userId: userId,
          secret: _credential.text,
          kind: CredentialKind.password,
        );
    if (!mounted) return;
    if (!result.isSuccess) {
      final lockText = result.lockedUntil == null
          ? ''
          : ' حاول بعد ${result.lockedUntil!.toLocal().hour.toString().padLeft(2, '0')}:${result.lockedUntil!.toLocal().minute.toString().padLeft(2, '0')}.';
      setState(() {
        _busy = false;
        _error = '${result.message ?? 'تعذر تسجيل الدخول.'}$lockText';
      });
      return;
    }
    final user = result.user!;
    if (!mounted) return;
    ref.read(currentUserProvider.notifier).state = user;
    unawaited(_saveLoginPreferences(user.id));
  }

  Future<void> _rememberUser(String userId) async {
    try {
      await _storage.write(key: _lastUserKey, value: userId);
    } catch (_) {
      // Remembering the last account is a convenience and must never block a
      // successful authenticated session.
    }
  }

  Future<void> _saveLoginPreferences(String userId) async {
    await _rememberUser(userId);
    if (!_biometricAvailable || !_enableBiometricAfterLogin) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .setBiometricEnabled(userId: userId, enabled: true);
    } catch (_) {
      // Manual authentication has already succeeded. A platform keystore
      // failure must not trap the user on the login screen.
    }
  }

  Future<void> _biometricLogin() async {
    final userId = _lastUserId;
    if (userId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .getBiometricUser(userId);
      if (user == null) {
        throw StateError(
          'البصمة غير مفعلة للحساب السابق. ادخل يدويًا وفعّلها أولًا.',
        );
      }
      final authenticated = await LocalAuthentication().authenticate(
        localizedReason: 'التحقق للدخول إلى نظام الحضور الصباحي',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!mounted) return;
      if (!authenticated) {
        setState(() {
          _busy = false;
          _error = 'لم يتم التحقق من البصمة.';
        });
        return;
      }
      ref.read(currentUserProvider.notifier).state = user;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(error);
      });
    }
  }

  static String _friendlyError(Object error) => '$error'
      .replaceFirst('FormatException: ', '')
      .replaceFirst('Bad state: ', '');
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
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.blue, AppColors.teal],
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 17),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.blueGrey, height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
