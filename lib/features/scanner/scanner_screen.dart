import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/attendance_record.dart';
import '../../models/student.dart';
import '../students/student_photo.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({this.classId, this.classLabel, super.key});
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

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: true,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
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
                          onTap: _controller.toggleTorch,
                        ),
                      ],
                    ),
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
                                _controller.setZoomScale(value);
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
    await _controller.stop();
    final student = await ref
        .read(studentRepositoryProvider)
        .getByBarcode(token);
    if (!mounted) return;
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
    await HapticFeedback.mediumImpact();
    final existing = await ref
        .read(attendanceRepositoryProvider)
        .getForStudent(student.id);
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
  }

  Future<void> _showExisting(Student student, AttendanceRecord record) async {
    final user = ref.read(currentUserProvider)!;
    final change = await showDialog<bool>(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('الطالب التالي'),
          ),
          if (user.role.canEditAttendance)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تعديل الحالة'),
            ),
        ],
      ),
    );
    if (change == true && mounted) {
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
          );
      if (!mounted) return;
      if (result.wasExisting) {
        await _showExisting(_student!, result.record);
      } else {
        await HapticFeedback.lightImpact();
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

  Future<(String?, String?, String?)?> _excuseDetails() async {
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
            const Text(
              'تفاصيل الاستئذان',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
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
              child: const Text('تسجيل مستأذن'),
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
    await _controller.start();
  }

  Future<void> _restartScanner() async {
    _handling = false;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (mounted) await _controller.start();
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
    required this.saving,
    required this.onCancel,
    required this.onStatus,
  });
  final Student student;
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
            'السجل: ${student.maskedNationalId}',
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

class _ProgressPill extends ConsumerWidget {
  const _ProgressPill({required this.classId, required this.classLabel});
  final String classId;
  final String classLabel;
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<DailySummary>(
    future: ref.read(attendanceRepositoryProvider).summary(classId: classId),
    builder: (context, snapshot) {
      final summary = snapshot.data;
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          summary == null
              ? classLabel
              : '$classLabel  •  تم تسجيل ${summary.registered} من ${summary.totalStudents}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      );
    },
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
