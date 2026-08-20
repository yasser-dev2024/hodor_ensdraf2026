import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers.dart';
import '../../core/school_day_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import '../../models/student.dart';
import '../../services/data_protection_service.dart';
import '../students/student_photo.dart';

enum _ExistingAction { nextStudent, changeStatus, departure }

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({
    required this.attendanceDate,
    this.classId,
    this.classLabel,
    super.key,
  });
  final String attendanceDate;
  final String? classId;
  final String? classLabel;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  late final MobileScannerController _controller;
  Student? _student;
  bool _handling = false;
  bool _saving = false;
  String? _lastToken;
  DateTime? _lastScanAt;
  double _zoom = 0;
  bool _soundEnabled = true;
  bool _hapticEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: true,
    );
    unawaited(_loadFeedbackSettings());
  }

  Future<void> _loadFeedbackSettings() async {
    try {
      final settings = await ref.read(settingsRepositoryProvider).getAll();
      _soundEnabled = settings['scan_sound'] != 'false';
      _hapticEnabled = settings['scan_haptic'] != 'false';
    } catch (_) {
      _soundEnabled = true;
      _hapticEnabled = true;
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dataRevisionProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: _student == null ? 1 : 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    tapToFocus: true,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(30),
                      child: Text(
                        'تعذر تشغيل الكاميرا. تحقق من منح إذن الكاميرا.\n${error.errorCode.name}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  if (_student == null) const _ScannerFrame(),
                  Positioned(
                    top: 8,
                    right: 8,
                    left: 8,
                    child: Row(
                      children: [
                        _CameraButton(
                          icon: Icons.close_rounded,
                          onTap: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        _CameraButton(
                          icon: Icons.flash_on_rounded,
                          onTap: _toggleTorch,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 58,
                    right: 12,
                    left: 12,
                    child: _SessionDayPill(date: widget.attendanceDate),
                  ),
                  if (_student == null)
                    Positioned(
                      right: 24,
                      left: 24,
                      bottom: 12,
                      child: Column(
                        children: [
                          if (widget.classId != null)
                            _ProgressPill(
                              classId: widget.classId!,
                              classLabel: widget.classLabel ?? '',
                              attendanceDate: widget.attendanceDate,
                            ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                              overlayColor: Colors.white12,
                            ),
                            child: Slider(
                              value: _zoom,
                              onChanged: (value) {
                                setState(() => _zoom = value);
                                unawaited(
                                  _controller
                                      .setZoomScale(value)
                                      .catchError((Object _) {}),
                                );
                              },
                            ),
                          ),
                          const Text(
                            'ضع رمز الطالب داخل الإطار',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_student != null)
              Expanded(
                flex: 7,
                child: _StudentResult(
                  student: _student!,
                  showSensitiveId: ref
                      .read(currentUserProvider)!
                      .role
                      .canViewSensitiveStudentData,
                  saving: _saving,
                  onCancel: _resume,
                  onStatus: _recordStatus,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || _student != null) return;
    final token = capture.barcodes
        .map((code) => code.rawValue)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .firstOrNull;
    if (token == null) return;
    final now = DateTime.now();
    if (_lastToken == token &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastToken = token;
    _lastScanAt = now;
    _handling = true;
    try {
      final attendance = ref.read(attendanceRepositoryProvider);
      if (attendance.dayKey() != widget.attendanceDate) {
        await _stopForUnavailableDay(
          'بدأ يوم دراسي جديد. أُغلقت جلسة المسح السابقة لمنع اختلاط الأيام. افتح الماسح مرة أخرى ليعمل بتاريخ اليوم الجديد.',
        );
        return;
      }
      if (await attendance.isDayClosed(widget.attendanceDate)) {
        await _stopForUnavailableDay(
          'تم إغلاق الحصر والمسح ليوم ${SchoolDayFormatter.gregorianLong(SchoolDayFormatter.parseKey(widget.attendanceDate))}. يمكن للمدير إعادة فتحه من تقرير اليوم.',
        );
        return;
      }
      await _controller.stop();
      var student = await ref
          .read(studentRepositoryProvider)
          .getByBarcode(token);
      if (!mounted) return;
      if (student == null &&
          DataProtectionService.isLegacyBarcodeToken(token)) {
        student = await _recoverLegacyBarcode(token);
        if (!mounted) return;
        if (student == null) {
          await _restartScanner();
          return;
        }
      }
      if (student == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('رمز غير معروف أو الطالب غير نشط.'),
            backgroundColor: AppColors.absent,
          ),
        );
        await _restartScanner();
        return;
      }
      if (widget.classId != null && student.classId != widget.classId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${student.name} ليس ضمن ${widget.classLabel}.'),
            backgroundColor: AppColors.excused,
          ),
        );
        await _restartScanner();
        return;
      }
      if (_hapticEnabled) await HapticFeedback.mediumImpact();
      if (_soundEnabled) await SystemSound.play(SystemSoundType.click);
      final existing = await ref
          .read(attendanceRepositoryProvider)
          .getForStudent(student.id, date: widget.attendanceDate);
      if (!mounted) return;
      if (existing != null) {
        await _showExisting(student, existing);
        await _restartScanner();
        return;
      }
      setState(() {
        _student = student;
        _handling = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر معالجة الرمز. أُعيد تشغيل الماسح بأمان.'),
            backgroundColor: AppColors.absent,
          ),
        );
      }
      await _restartScanner();
    }
  }

  Future<Student?> _recoverLegacyBarcode(String token) async {
    final user = ref.read(currentUserProvider)!;
    if (!user.role.canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذا باركود قديم فقد ارتباطه بعد حذف البيانات. اطلب من المدير ربطه بالطالب مرة واحدة.',
          ),
          backgroundColor: AppColors.excused,
        ),
      );
      return null;
    }
    final nationalId = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: AppColors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('استرداد باركود قديم')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تعذر معرفة صاحب الرمز العشوائي بعد حذف قاعدة البيانات. أدخل السجل المدني الصحيح للطالب لربط البطاقة القديمة مرة واحدة.',
              style: TextStyle(height: 1.55),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nationalId,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]')),
              ],
              decoration: const InputDecoration(
                labelText: 'السجل المدني للطالب',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, nationalId.text),
            icon: const Icon(Icons.link_rounded),
            label: const Text('ربط ومتابعة'),
          ),
        ],
      ),
    );
    nationalId.dispose();
    if (value == null || !mounted) return null;
    try {
      final student = await ref
          .read(studentRepositoryProvider)
          .bindLegacyBarcode(token: token, nationalId: value, userId: user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم ربط البطاقة القديمة بالطالب ${student.name}.'),
            backgroundColor: AppColors.present,
          ),
        );
      }
      return student;
    } catch (error) {
      if (mounted) {
        final message = '$error'
            .replaceFirst('FormatException: ', '')
            .replaceFirst('Bad state: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.absent),
        );
      }
      return null;
    }
  }

  Future<void> _showExisting(Student student, AttendanceRecord record) async {
    final user = ref.read(currentUserProvider)!;
    final action = await showDialog<_ExistingAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.blue),
            SizedBox(width: 8),
            Text('مسجل مسبقًا'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StudentPhoto(path: student.photoPath, size: 105, highlighted: true),
            const SizedBox(height: 12),
            Text(
              student.name,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              '${record.status.label} - الساعة ${DateFormat('h:mm a', 'ar').format(record.recordedAt.toLocal())}',
              style: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _ExistingAction.nextStudent),
            child: const Text('الطالب التالي'),
          ),
          if (user.role.canEditAttendance)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _ExistingAction.departure),
              child: Text(
                record.departureAt == null
                    ? 'تسجيل الانصراف'
                    : 'تحديث الانصراف',
              ),
            ),
          if (user.role.canEditAttendance)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _ExistingAction.changeStatus),
              child: const Text('تعديل الحالة'),
            ),
        ],
      ),
    );
    if (action == _ExistingAction.departure && mounted) {
      final details = await _excuseDetails(departure: true);
      if (details != null) {
        await ref
            .read(attendanceRepositoryProvider)
            .recordDeparture(
              recordId: record.id,
              userId: user.id,
              reason: details.$1,
              note: details.$2,
              receiverName: details.$3,
            );
        refreshData(ref);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تسجيل انصراف ${student.name} الآن.'),
              backgroundColor: AppColors.excused,
            ),
          );
        }
      }
    } else if (action == _ExistingAction.changeStatus && mounted) {
      final status = await showModalBottomSheet<AttendanceStatus>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'اختر الحالة الجديدة',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 14),
                for (final value in AttendanceStatus.values)
                  ListTile(
                    onTap: () => Navigator.pop(context, value),
                    leading: Icon(
                      _statusIcon(value),
                      color: _statusColor(value),
                    ),
                    title: Text(value.label),
                  ),
              ],
            ),
          ),
        ),
      );
      if (status != null) {
        await ref
            .read(attendanceRepositoryProvider)
            .updateStatus(recordId: record.id, status: status, userId: user.id);
        refreshData(ref);
      }
    }
  }

  Future<void> _recordStatus(AttendanceStatus status) async {
    if (_saving || _student == null) return;
    String? reason;
    String? note;
    String? receiver;
    if (status == AttendanceStatus.excused) {
      final details = await _excuseDetails();
      if (details == null) return;
      reason = details.$1;
      note = details.$2;
      receiver = details.$3;
    }
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .record(
            student: _student!,
            status: status,
            userId: ref.read(currentUserProvider)!.id,
            reason: reason,
            note: note,
            receiverName: receiver,
            attendanceDate: widget.attendanceDate,
          );
      if (!mounted) return;
      if (result.wasExisting) {
        await _showExisting(_student!, result.record);
      } else {
        if (_hapticEnabled) await HapticFeedback.lightImpact();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 700),
            content: Text('تم تسجيل ${_student!.name}: ${status.label}'),
            backgroundColor: _statusColor(status),
          ),
        );
        refreshData(ref);
      }
      await _resume();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: AppColors.absent),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<(String?, String?, String?)?> _excuseDetails({
    bool departure = false,
  }) async {
    final reason = TextEditingController();
    final note = TextEditingController();
    final receiver = TextEditingController();
    final result = await showModalBottomSheet<(String?, String?, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              departure ? 'تفاصيل الانصراف' : 'تفاصيل الاستئذان',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'السبب (اختياري)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: receiver,
              decoration: const InputDecoration(
                labelText: 'الشخص المستلم (اختياري)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختيارية)'),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                reason.text,
                note.text,
                receiver.text,
              )),
              child: Text(departure ? 'تسجيل وقت الانصراف' : 'تسجيل مستأذن'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    note.dispose();
    receiver.dispose();
    return result;
  }

  Future<void> _resume() async {
    if (mounted) {
      setState(() {
        _student = null;
        _handling = false;
      });
    }
    await _startScannerSafely();
  }

  Future<void> _restartScanner() async {
    _handling = false;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await _startScannerSafely();
  }

  Future<void> _stopForUnavailableDay(String message) async {
    await _controller.stop().catchError((Object _) {});
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.event_busy_rounded, color: AppColors.absent),
        title: const Text('جلسة المسح غير متاحة'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('العودة'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _startScannerSafely() async {
    if (!mounted) return;
    try {
      await _controller.start();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر إعادة تشغيل الكاميرا. أغلق شاشة المسح وافتحها مجددًا.',
            ),
          ),
        );
      }
    }
  }

  void _toggleTorch() {
    unawaited(_controller.toggleTorch().catchError((Object _) {}));
  }

  static Color _statusColor(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => AppColors.present,
    AttendanceStatus.absent => AppColors.absent,
    AttendanceStatus.excused => AppColors.excused,
  };

  static IconData _statusIcon(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => Icons.check_circle_rounded,
    AttendanceStatus.absent => Icons.cancel_rounded,
    AttendanceStatus.excused => Icons.exit_to_app_rounded,
  };
}

class _StudentResult extends StatelessWidget {
  const _StudentResult({
    required this.student,
    required this.showSensitiveId,
    required this.saving,
    required this.onCancel,
    required this.onStatus,
  });
  final Student student;
  final bool showSensitiveId;
  final bool saving;
  final Future<void> Function() onCancel;
  final Future<void> Function(AttendanceStatus) onStatus;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: const BoxDecoration(
      color: Color(0xFFF5F8FA),
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SingleChildScrollView(
      child: Column(
        children: [
          StudentPhoto(path: student.photoPath, size: 138, highlighted: true),
          const SizedBox(height: 10),
          Text(
            student.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            student.classLabel.isEmpty
                ? 'الصف والفصل غير محددين'
                : student.classLabel,
            style: const TextStyle(
              color: AppColors.blue,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'السجل: ${showSensitiveId ? student.nationalId : student.maskedNationalId}',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 15),
          if (saving)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          else
            Row(
              children: [
                _StatusButton(
                  label: 'حاضر',
                  icon: Icons.check_rounded,
                  color: AppColors.present,
                  onTap: () => onStatus(AttendanceStatus.present),
                ),
                const SizedBox(width: 8),
                _StatusButton(
                  label: 'غائب',
                  icon: Icons.close_rounded,
                  color: AppColors.absent,
                  onTap: () => onStatus(AttendanceStatus.absent),
                ),
                const SizedBox(width: 8),
                _StatusButton(
                  label: 'مستأذن',
                  icon: Icons.exit_to_app_rounded,
                  color: AppColors.excused,
                  onTap: () => onStatus(AttendanceStatus.excused),
                ),
              ],
            ),
          TextButton(
            onPressed: saving ? null : onCancel,
            child: const Text('إلغاء ومسح طالب آخر'),
          ),
        ],
      ),
    ),
  );
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, maxLines: 1),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 64),
      ),
    ),
  );
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: MediaQuery.sizeOf(context).width.clamp(220, 310).toDouble(),
      height: 210,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 3),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 18)],
      ),
    ),
  );
}

class _CameraButton extends StatelessWidget {
  const _CameraButton({required this.icon, required this.onTap});
  final IconData icon;
  final FutureOr<void> Function() onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black54,
    shape: const CircleBorder(),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white),
    ),
  );
}

class _SessionDayPill extends StatelessWidget {
  const _SessionDayPill({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    final value = SchoolDayFormatter.parseKey(date);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          '${SchoolDayFormatter.gregorianLong(value)}\n${SchoolDayFormatter.hijriLong(value)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ProgressPill extends ConsumerWidget {
  const _ProgressPill({
    required this.classId,
    required this.classLabel,
    required this.attendanceDate,
  });
  final String classId;
  final String classLabel;
  final String attendanceDate;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(attendanceRepositoryProvider);
    return FutureBuilder<List<Object>>(
      future: Future.wait<Object>([
        repository.summary(date: attendanceDate, classId: classId),
        repository.unregistered(date: attendanceDate, classId: classId),
      ]),
      builder: (context, snapshot) {
        final summary = snapshot.hasData
            ? snapshot.data![0] as DailySummary
            : null;
        final remaining = snapshot.hasData
            ? snapshot.data![1] as List<Map<String, Object?>>
            : const <Map<String, Object?>>[];
        final visibleNames = remaining
            .take(2)
            .map((row) => row['name'] as String)
            .join('، ');
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: remaining.isEmpty
                ? null
                : () => _showRemaining(context, remaining),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summary == null
                        ? classLabel
                        : '$classLabel  •  تم تسجيل ${summary.registered} من ${summary.totalStudents}  •  المتبقي ${summary.remaining}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  if (visibleNames.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'المتبقون: $visibleNames${remaining.length > 2 ? '…' : ''}  (اضغط للكل)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRemaining(
    BuildContext context,
    List<Map<String, Object?>> students,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          children: [
            ListTile(
              title: Text(
                'الطلاب المتبقون (${students.length})',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(classLabel),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: students.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final student = students[index];
                  final label = [
                    student['grade_name'],
                    student['class_name'],
                  ].whereType<String>().join(' / ');
                  return ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(student['name'] as String),
                    subtitle: label.isEmpty ? null : Text(label),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
