import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/school_day_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../models/daily_preparation.dart';

class SmartPreparationSection extends StatelessWidget {
  const SmartPreparationSection({
    required this.snapshot,
    required this.now,
    required this.onClassTap,
    super.key,
  });

  final DailyPreparationSnapshot snapshot;
  final DateTime now;
  final ValueChanged<ClassPreparationStatus> onClassTap;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SmartMorningCard(snapshot: snapshot, now: now),
      const SizedBox(height: 14),
      _CompletionCard(snapshot: snapshot),
      const SizedBox(height: 14),
      _ClassRadar(snapshot: snapshot, onClassTap: onClassTap),
      if (snapshot.isComplete) ...[
        const SizedBox(height: 14),
        DailyFingerprintCard(snapshot: snapshot),
      ],
    ],
  );
}

class _SmartMorningCard extends StatelessWidget {
  const _SmartMorningCard({required this.snapshot, required this.now});

  final DailyPreparationSnapshot snapshot;
  final DateTime now;

  String get _greeting {
    if (now.hour < 12) return 'صباح الخير';
    if (now.hour < 18) return 'طاب يومك';
    return 'مساء الخير';
  }

  String get _status {
    if (snapshot.isComplete) return '✓ اكتمل تحضير اليوم';
    if (snapshot.totalClasses == 0) return 'أضف الفصول والطلاب لبدء التحضير';
    if (!snapshot.hasStarted) return 'النظام جاهز للتحضير ✓';
    if (snapshot.remainingClasses == 0) {
      return 'اكتملت الفصول — توجد بيانات تحتاج مراجعة';
    }
    return 'التحضير جارٍ — متبقي ${snapshot.remainingClasses} فصول';
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.navy, AppColors.blue, AppColors.teal],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: AppColors.blue.withValues(alpha: .18),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.wb_sunny_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('EEEE d MMMM y', 'ar').format(now)} — ${DateFormat('h:mm a', 'ar').format(now)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Text(
            _status,
            key: ValueKey(_status),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final children = [
              _MorningMetric(
                icon: Icons.meeting_room_outlined,
                label:
                    'الفصول المكتملة: ${snapshot.completedClasses} من ${snapshot.totalClasses}',
              ),
              _MorningMetric(
                icon: Icons.donut_large_rounded,
                label:
                    'نسبة الاكتمال: ${(snapshot.completionRate * 100).round()}٪',
              ),
            ];
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      children.first,
                      const SizedBox(height: 8),
                      children.last,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: children.first),
                      const SizedBox(width: 8),
                      Expanded(child: children.last),
                    ],
                  );
          },
        ),
      ],
    ),
  );
}

class _MorningMetric extends StatelessWidget {
  const _MorningMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.snapshot});

  final DailyPreparationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final percent = (snapshot.completionRate * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.checklist_rounded,
                    color: AppColors.teal,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'اكتمال تحضير المدرسة',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'تم تحضير ${snapshot.completedClasses} من ${snapshot.totalClasses} فصلًا — $percent٪',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$percent٪',
                  style: TextStyle(
                    color: snapshot.isComplete
                        ? AppColors.present
                        : AppColors.blue,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: snapshot.completionRate),
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 12,
                  color: snapshot.isComplete
                      ? AppColors.present
                      : AppColors.blue,
                  backgroundColor: const Color(0xFFE5EEF1),
                ),
              ),
            ),
            if (snapshot.isComplete) ...[
              const SizedBox(height: 13),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .92, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                builder: (context, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F7F1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.present.withValues(alpha: .28),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified_rounded, color: AppColors.present),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'اكتمل تحضير المدرسة لهذا اليوم',
                          style: TextStyle(
                            color: AppColors.present,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (snapshot.unassignedStudents > 0) ...[
              const SizedBox(height: 10),
              Text(
                'يوجد ${snapshot.unassignedStudents} طالب بلا صف أو فصل ويحتاج إلى مراجعة.',
                style: const TextStyle(
                  color: AppColors.absent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassRadar extends StatelessWidget {
  const _ClassRadar({required this.snapshot, required this.onClassTap});

  final DailyPreparationSnapshot snapshot;
  final ValueChanged<ClassPreparationStatus> onClassTap;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.radar_rounded, color: AppColors.blue),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'رادار الفصول',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'افتح الفصل، سجّل الغائبين والمستأذنين فقط، ثم اعتمده ليُحتسب الباقون حضورًا وينتقل الرادار للفصل التالي.',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          const SizedBox(height: 14),
          if (snapshot.classes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text('لا توجد فصول مضافة حتى الآن.')),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                final columns = constraints.maxWidth >= 720
                    ? 4
                    : constraints.maxWidth >= 500
                    ? 3
                    : 2;
                final width =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final item in snapshot.classes)
                      SizedBox(
                        width: width,
                        child: _ClassRadarTile(
                          item: item,
                          onTap: () => onClassTap(item),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    ),
  );
}

class _ClassRadarTile extends StatelessWidget {
  const _ClassRadarTile({required this.item, required this.onTap});

  final ClassPreparationStatus item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (item.state) {
      ClassPreparationState.complete => (
        AppColors.present,
        Icons.check_circle_rounded,
        'مكتمل',
      ),
      ClassPreparationState.incomplete => (
        AppColors.excused,
        Icons.hourglass_top_rounded,
        'لم يكتمل',
      ),
      ClassPreparationState.needsReview => (
        AppColors.absent,
        Icons.warning_amber_rounded,
        'يحتاج مراجعة',
      ),
    };
    return Tooltip(
      message: item.reviewReason ?? item.label,
      child: Material(
        key: ValueKey('class-radar-${item.classId}'),
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: .28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 19),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.isComplete
                      ? 'الغياب ${item.absentStudents} • الاستئذان ${item.excusedStudents}'
                      : 'الغياب ${item.absentStudents} • أغلق لاعتماد البقية',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DailyFingerprintCard extends StatefulWidget {
  const DailyFingerprintCard({required this.snapshot, super.key});

  final DailyPreparationSnapshot snapshot;

  @override
  State<DailyFingerprintCard> createState() => _DailyFingerprintCardState();
}

class _DailyFingerprintCardState extends State<DailyFingerprintCard> {
  final GlobalKey _captureKey = GlobalKey();
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          RepaintBoundary(
            key: const ValueKey('daily-fingerprint-capture'),
            child: RepaintBoundary(
              key: _captureKey,
              child: _FingerprintImage(snapshot: widget.snapshot),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 340;
              final buttons = [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _savePng,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('حفظ PNG'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _sharePng,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('مشاركة البطاقة'),
                ),
              ];
              return vertical
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        buttons.first,
                        const SizedBox(height: 8),
                        buttons.last,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: buttons.first),
                        const SizedBox(width: 8),
                        Expanded(child: buttons.last),
                      ],
                    );
            },
          ),
        ],
      ),
    ),
  );

  Future<Uint8List> _capture() async {
    final deviceRatio = MediaQuery.devicePixelRatioOf(context);
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('تعذر تجهيز بطاقة بصمة اليوم.');
    }
    final image = await boundary.toImage(
      pixelRatio: deviceRatio.clamp(2.0, 3.0),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('تعذر إنشاء صورة بصمة اليوم.');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _savePng() async => _run(() async {
    final bytes = await _capture();
    final day = SchoolDayFormatter.key(widget.snapshot.date);
    final path = await fp.FilePicker.saveFile(
      dialogTitle: 'حفظ بصمة اليوم',
      fileName: 'بصمة-اليوم-$day.png',
      type: fp.FileType.custom,
      allowedExtensions: const ['png'],
      bytes: bytes,
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ بطاقة بصمة اليوم بصيغة PNG.')),
      );
    }
  });

  Future<void> _sharePng() async => _run(() async {
    final bytes = await _capture();
    final day = SchoolDayFormatter.key(widget.snapshot.date);
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, 'daily-fingerprint-$day.png'));
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        subject: 'بصمة اليوم $day',
        text: 'بصمة اكتمال التحضير ليوم $day',
        files: [XFile(file.path, mimeType: 'image/png')],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر إكمال العملية: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _FingerprintImage extends StatelessWidget {
  const _FingerprintImage({required this.snapshot});

  final DailyPreparationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final completedAt = snapshot.completedAt?.toLocal();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE7EC)),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.blue, AppColors.teal],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'بصمة اليوم',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            DateFormat('EEEE d MMMM y', 'ar').format(snapshot.date),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.teal,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 17),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 8.0;
              final width = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  _FingerprintStat(
                    width: width,
                    label: 'إجمالي الطلاب',
                    value: '${snapshot.summary.totalStudents}',
                    color: AppColors.navy,
                  ),
                  _FingerprintStat(
                    width: width,
                    label: 'الحاضرون',
                    value: '${snapshot.summary.present}',
                    color: AppColors.present,
                  ),
                  _FingerprintStat(
                    width: width,
                    label: 'الغائبون',
                    value: '${snapshot.summary.absent}',
                    color: AppColors.absent,
                  ),
                  _FingerprintStat(
                    width: width,
                    label: 'نسبة الحضور',
                    value:
                        '${(snapshot.summary.attendanceRate * 100).toStringAsFixed(1)}٪',
                    color: AppColors.blue,
                  ),
                ],
              );
            },
          ),
          if (snapshot.summary.excused > 0) ...[
            const SizedBox(height: 8),
            Text(
              'المستأذنون: ${snapshot.summary.excused}',
              style: const TextStyle(
                color: AppColors.excused,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F7F1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              children: [
                Text(
                  'الفصول: ${snapshot.completedClasses}/${snapshot.totalClasses}',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  completedAt == null
                      ? 'اكتمل التحضير ✓'
                      : 'اكتمل التحضير: ${DateFormat('h:mm a', 'ar').format(completedAt)} ✓',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.present,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FingerprintStat extends StatelessWidget {
  const _FingerprintStat({
    required this.width,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      children: [
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
}
