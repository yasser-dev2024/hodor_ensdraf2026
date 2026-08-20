import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/school_day_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import '../../models/school_class.dart';
import '../reports/daily_report_screen.dart';
import 'scanner_screen.dart';

class ScanLandingScreen extends ConsumerStatefulWidget {
  const ScanLandingScreen({super.key});

  @override
  ConsumerState<ScanLandingScreen> createState() => _ScanLandingScreenState();
}

class _ScanLandingScreenState extends ConsumerState<ScanLandingScreen> {
  String? _classId;
  String? _classLabel;

  @override
  Widget build(BuildContext context) {
    ref.watch(dataRevisionProvider);
    final today = SchoolDayFormatter.dateOnly(DateTime.now());
    final todayKey = SchoolDayFormatter.key(today);
    final dayFuture = ref
        .read(attendanceRepositoryProvider)
        .dayOverview(todayKey);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Text(
            'تسجيل الحضور',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'امسح رمز الطالب ثم اختر حالته بلمسة واحدة.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 14),
          FutureBuilder<AttendanceDayOverview>(
            future: dayFuture,
            builder: (context, snapshot) {
              final day = snapshot.data;
              final closed = day?.isClosed ?? false;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: closed
                      ? const Color(0xFFFFECEB)
                      : const Color(0xFFE8F7F1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: closed
                        ? AppColors.absent.withValues(alpha: .35)
                        : AppColors.present.withValues(alpha: .35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      closed ? Icons.lock_rounded : Icons.today_rounded,
                      color: closed ? AppColors.absent : AppColors.present,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            SchoolDayFormatter.gregorianLong(today),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            '${SchoolDayFormatter.hijriLong(today)} — ${closed ? 'اليوم مغلق' : 'اليوم مفتوح للمسح'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: closed
                                  ? AppColors.absent
                                  : AppColors.present,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (closed)
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DailyReportScreen(date: today),
                          ),
                        ),
                        child: const Text('التقرير'),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.navy, AppColors.blue],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.blue.withValues(alpha: .25),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 70,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'جاهز للمسح السريع',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _classLabel == null
                      ? 'الوضع العام لجميع الطلاب'
                      : 'الوضع السريع: $_classLabel',
                  style: TextStyle(color: Colors.white.withValues(alpha: .8)),
                ),
                const SizedBox(height: 22),
                FutureBuilder<AttendanceDayOverview>(
                  future: dayFuture,
                  builder: (context, snapshot) {
                    final ready = snapshot.hasData;
                    final closed = snapshot.data?.isClosed ?? false;
                    final failed = snapshot.hasError;
                    return FilledButton.icon(
                      onPressed: !ready || closed
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ScannerScreen(
                                  attendanceDate: todayKey,
                                  classId: _classId,
                                  classLabel: _classLabel,
                                ),
                              ),
                            ),
                      icon: Icon(
                        failed
                            ? Icons.error_outline_rounded
                            : !ready
                            ? Icons.hourglass_top_rounded
                            : closed
                            ? Icons.lock_rounded
                            : Icons.camera_alt_rounded,
                      ),
                      label: Text(
                        failed
                            ? 'تعذر التحقق من يوم العمل'
                            : !ready
                            ? 'جاري التحقق من يوم العمل'
                            : closed
                            ? 'انتهى المسح لهذا اليوم'
                            : 'فتح الكاميرا وبدء التسجيل',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.navy,
                        disabledBackgroundColor: Colors.white70,
                        disabledForegroundColor: AppColors.absent,
                        minimumSize: const Size.fromHeight(62),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.flash_on_rounded, color: AppColors.excused),
                      SizedBox(width: 8),
                      Text(
                        'المسح السريع للفصل',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'اختر فصلًا لمتابعة عدد المسجلين والمتبقين أثناء المسح.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 14),
                  FutureBuilder<List<SchoolClass>>(
                    future: ref.read(classRepositoryProvider).getClasses(),
                    builder: (context, snapshot) {
                      final classes = snapshot.data ?? const <SchoolClass>[];
                      return DropdownButtonFormField<String?>(
                        value: _classId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'الفصل (اختياري)',
                          prefixIcon: Icon(Icons.meeting_room_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('جميع الطلاب'),
                          ),
                          ...classes.map(
                            (item) => DropdownMenuItem<String?>(
                              value: item.id,
                              child: Text(item.label),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          final match = classes
                              .where((item) => item.id == value)
                              .firstOrNull;
                          setState(() {
                            _classId = value;
                            _classLabel = match?.label;
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.teal),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'يتوقف الماسح فور قراءة الرمز، ويمنع تسجيل الطالب مرتين في اليوم. رمز QR لا يكشف السجل المدني.',
                      style: TextStyle(height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
