import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/startup_permission_service.dart';
import '../../services/usage_policy_service.dart';

enum _LaunchStage { loading, agreement, permissions, ready }

class LaunchGate extends ConsumerStatefulWidget {
  const LaunchGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends ConsumerState<LaunchGate>
    with WidgetsBindingObserver {
  _LaunchStage _stage = _LaunchStage.loading;
  List<StartupPermissionItem> _permissions = const [];
  bool _permissionsSkippedForSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _stage == _LaunchStage.permissions) {
      _evaluate();
    }
  }

  Future<void> _evaluate() async {
    if (mounted) setState(() => _stage = _LaunchStage.loading);
    final policyAccepted = await ref
        .read(usagePolicyServiceProvider)
        .isCurrentVersionAccepted();
    if (!mounted) return;
    if (!policyAccepted) {
      setState(() => _stage = _LaunchStage.agreement);
      return;
    }
    final permissions = await ref
        .read(startupPermissionServiceProvider)
        .statuses();
    if (!mounted) return;
    if (!_permissionsSkippedForSession &&
        permissions.any((permission) => !permission.isGranted)) {
      setState(() {
        _permissions = permissions;
        _stage = _LaunchStage.permissions;
      });
      return;
    }
    setState(() => _stage = _LaunchStage.ready);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _LaunchStage.loading => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _LaunchStage.agreement => UsageAgreementScreen(
        onAccepted: () async {
          await ref.read(usagePolicyServiceProvider).acceptCurrentVersion();
          await _evaluate();
        },
      ),
      _LaunchStage.permissions => StartupPermissionsScreen(
        permissions: _permissions,
        onRefresh: _evaluate,
        onContinue: () {
          setState(() {
            _permissionsSkippedForSession = true;
            _stage = _LaunchStage.ready;
          });
        },
      ),
      _LaunchStage.ready => widget.child,
    };
  }
}

class _LaunchFrame extends StatelessWidget {
  const _LaunchFrame({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
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
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x30153A5B),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Icon(icon, color: AppColors.teal, size: 30),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.blueGrey, height: 1.6),
                  ),
                  const SizedBox(height: 20),
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

class UsageAgreementScreen extends StatefulWidget {
  const UsageAgreementScreen({required this.onAccepted, super.key});

  final Future<void> Function() onAccepted;

  @override
  State<UsageAgreementScreen> createState() => _UsageAgreementScreenState();
}

class _UsageAgreementScreenState extends State<UsageAgreementScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return _LaunchFrame(
      icon: Icons.policy_outlined,
      title: 'إقرار الاستخدام وحفظ الحقوق',
      subtitle: 'يرجى قراءة الإقرار والموافقة عليه قبل فتح التطبيق.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'أتعهد باستخدام هذا التطبيق للأغراض النظامية والمصرح بها فقط، وعدم إساءة استخدامه أو استخدامه بما يخالف الأنظمة والتعليمات. كما أتعهد بعدم نشر التطبيق أو نسخه أو مشاركته أو توزيعه أو إتاحته للغير إلا بإذن صريح من صاحب التطبيق.',
            style: TextStyle(fontWeight: FontWeight.w800, height: 1.9),
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6DF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'جميع الحقوق الفكرية والبرمجية والتصميمية للتطبيق محفوظة لصاحب التطبيق، ولا يجوز نسخ التطبيق أو تعديل بنيته أو إعادة استخدام أجزائه أو محاولة تجاوز وسائل الحماية أو نسب العمل للغير دون إذن.',
              textAlign: TextAlign.start,
              style: TextStyle(
                color: Color(0xFF6E5220),
                fontWeight: FontWeight.w800,
                height: 1.9,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await widget.onAccepted();
                  },
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: const Text('أوافق وأتابع'),
          ),
          const SizedBox(height: 8),
          Text(
            'إصدار السياسة: ${UsagePolicy.version}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }
}

class StartupPermissionsScreen extends ConsumerStatefulWidget {
  const StartupPermissionsScreen({
    required this.permissions,
    required this.onRefresh,
    required this.onContinue,
    super.key,
  });

  final List<StartupPermissionItem> permissions;
  final Future<void> Function() onRefresh;
  final VoidCallback onContinue;

  @override
  ConsumerState<StartupPermissionsScreen> createState() =>
      _StartupPermissionsScreenState();
}

class _StartupPermissionsScreenState
    extends ConsumerState<StartupPermissionsScreen> {
  bool _busy = false;
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final hasPermanentDenial = widget.permissions.any(
      (permission) => permission.isPermanentlyDenied,
    );
    return _LaunchFrame(
      icon: Icons.admin_panel_settings_outlined,
      title: 'أذونات تشغيل التطبيق',
      subtitle:
          'يحتاج التطبيق إلى الأذونات التالية للمسح وإضافة صور الطلاب. لا يطلب وصولًا عامًا إلى ملفات الجهاز.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final permission in widget.permissions)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: permission.isGranted
                    ? const Color(0xFFE8F6EF)
                    : const Color(0xFFFFF5E4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    permission.isGranted
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    color: permission.isGranted
                        ? AppColors.present
                        : AppColors.excused,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          permission.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          permission.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _request,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.security_rounded),
            label: const Text('منح الأذونات والمتابعة'),
          ),
          if (hasPermanentDenial) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(startupPermissionServiceProvider).openSettings(),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('فتح إعدادات التطبيق'),
            ),
          ],
          if (_requested) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onContinue,
              child: const Text('المتابعة الآن مع تقييد وظائف الكاميرا'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    final permissions = await ref
        .read(startupPermissionServiceProvider)
        .requestAll();
    if (!mounted) return;
    final allGranted = permissions.every((permission) => permission.isGranted);
    if (allGranted) {
      await widget.onRefresh();
      return;
    }
    setState(() {
      _busy = false;
      _requested = true;
    });
  }
}
