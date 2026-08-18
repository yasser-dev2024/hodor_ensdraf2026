import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/school_class.dart';
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
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ScannerScreen(
                        classId: _classId,
                        classLabel: _classLabel,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('فتح الكاميرا وبدء التسجيل'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.navy,
                    minimumSize: const Size.fromHeight(62),
                  ),
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
