import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'data/app_database.dart';
import 'services/data_protection_service.dart';

typedef BootstrapInitializer = Future<BootstrapServices> Function();

class BootstrapServices {
  const BootstrapServices({
    required this.database,
    required this.dataProtection,
  });

  final AppDatabase database;
  final DataProtectionService dataProtection;
}

Future<BootstrapServices> initializeAttendanceApp() async {
  AppDatabase? database;
  try {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await initializeDateFormatting('ar');
    database = await AppDatabase.open();
    final dataProtection = await DataProtectionService.create();
    return BootstrapServices(
      database: database,
      dataProtection: dataProtection,
    );
  } catch (_) {
    await database?.close();
    rethrow;
  }
}

class AttendanceBootstrap extends StatefulWidget {
  const AttendanceBootstrap({
    this.initialize = initializeAttendanceApp,
    super.key,
  });

  final BootstrapInitializer initialize;

  @override
  State<AttendanceBootstrap> createState() => _AttendanceBootstrapState();
}

class _AttendanceBootstrapState extends State<AttendanceBootstrap> {
  late Future<BootstrapServices> _initialization;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _initialization = widget.initialize();
  }

  void _retry() {
    setState(_start);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BootstrapServices>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final services = snapshot.requireData;
          return ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(services.database),
              dataProtectionProvider.overrideWithValue(services.dataProtection),
            ],
            child: const AttendanceApp(),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar', 'SA'),
          theme: AppTheme.light,
          home: snapshot.hasError
              ? _BootstrapFailure(onRetry: _retry)
              : const _BootstrapLoading(),
        );
      },
    );
  }
}

class _BootstrapLoading extends StatelessWidget {
  const _BootstrapLoading();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'جارٍ تهيئة بيانات المدرسة…',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapFailure extends StatelessWidget {
  const _BootstrapFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: AppColors.absent,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'تعذر تشغيل التطبيق',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'لم تكتمل تهيئة بيانات التطبيق. لم يتم حذف أي بيانات. حاول مرة أخرى، وإذا استمرت المشكلة فتأكد من توفر مساحة كافية على الجهاز.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blueGrey, height: 1.7),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget buildSafeErrorWidget(FlutterErrorDetails details) {
  return const Directionality(
    textDirection: TextDirection.rtl,
    child: Material(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 46,
                  color: AppColors.excused,
                ),
                SizedBox(height: 12),
                Text(
                  'تعذر عرض هذه الصفحة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'أغلق التطبيق وافتحه مجددًا. بياناتك محفوظة ولم يتم حذفها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
