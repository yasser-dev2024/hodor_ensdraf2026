import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _schoolName = TextEditingController();
  final _academicYear = TextEditingController();
  final _semester = TextEditingController();
  final _agentName = TextEditingController();
  final _agentPhone = TextEditingController();
  final _contactPhone = TextEditingController();
  final _whatsappTemplate = TextEditingController();
  final _backupReminderDays = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _logoPath;
  bool _scanSound = true;
  bool _scanHaptic = true;
  bool _markUnregisteredPresentOnClose = true;
  bool _autoArchivePdf = true;
  String _barcodeCardSize = 'standard';
  String _agentSendMethod = 'whatsapp';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _schoolName.dispose();
    _academicYear.dispose();
    _semester.dispose();
    _agentName.dispose();
    _agentPhone.dispose();
    _contactPhone.dispose();
    _whatsappTemplate.dispose();
    _backupReminderDays.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await ref.read(settingsRepositoryProvider).getAll();
      _schoolName.text = values['school_name'] ?? '';
      _academicYear.text = values['academic_year'] ?? '';
      _semester.text = values['semester'] ?? '';
      _agentName.text = values['agent_name'] ?? '';
      _agentPhone.text = values['agent_phone'] ?? '';
      _contactPhone.text = values['contact_phone'] ?? '';
      _whatsappTemplate.text =
          values['whatsapp_template'] ??
          'تقرير الغياب الصباحي\nالتاريخ: {date}\nإجمالي الطلاب: {total}\nالحاضرون: {present}\nالغائبون: {absent}\nالمستأذنون: {excused}\n\nيرجى إرفاق التقرير التفصيلي عند الحاجة.';
      _backupReminderDays.text = values['backup_reminder_days'] ?? '7';
      _scanSound = values['scan_sound'] != 'false';
      _scanHaptic = values['scan_haptic'] != 'false';
      _markUnregisteredPresentOnClose =
          values['mark_unregistered_present_on_close'] != 'false';
      _autoArchivePdf = values['auto_archive_pdf'] != 'false';
      _barcodeCardSize = values['barcode_card_size'] ?? 'standard';
      _agentSendMethod = values['agent_send_method'] ?? 'whatsapp';
      _logoPath = values['school_logo_path'];
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحميل الإعدادات. حاول مجددًا.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات المدرسة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: const Color(0xFFE1EFF5),
                          backgroundImage:
                              _logoPath != null && File(_logoPath!).existsSync()
                              ? FileImage(File(_logoPath!))
                              : null,
                          child:
                              _logoPath == null ||
                                  !File(_logoPath!).existsSync()
                              ? const Icon(
                                  Icons.school_rounded,
                                  size: 48,
                                  color: AppColors.blue,
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _pickLogo,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('إضافة شعار المدرسة'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _schoolName,
                          decoration: const InputDecoration(
                            labelText: 'اسم المدرسة',
                            prefixIcon: Icon(Icons.school_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _academicYear,
                                decoration: const InputDecoration(
                                  labelText: 'العام الدراسي',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _semester,
                                decoration: const InputDecoration(
                                  labelText: 'الفصل الدراسي',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'وكيل شؤون الطلاب والتواصل',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 13),
                        TextField(
                          controller: _agentName,
                          decoration: const InputDecoration(
                            labelText: 'اسم وكيل شؤون الطلاب',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _agentSendMethod,
                          decoration: const InputDecoration(
                            labelText: 'وسيلة الإرسال الافتراضية',
                            prefixIcon: Icon(Icons.ios_share_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'whatsapp',
                              child: Text('واتساب إلى الرقم المحفوظ'),
                            ),
                            DropdownMenuItem(
                              value: 'share',
                              child: Text('مشاركة PDF (بريد/واتساب/غيره)'),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _agentSendMethod = value ?? 'whatsapp',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _agentPhone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم واتساب مع مفتاح الدولة',
                            prefixIcon: Icon(Icons.send_outlined),
                            helperText: 'مثال: 9665XXXXXXXX',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _contactPhone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم تواصل إضافي',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(
                          Icons.qr_code_2_rounded,
                          color: AppColors.blue,
                        ),
                        title: Text(
                          'إعدادات المسح والباركود',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          'الرمز ثابت بعد إعادة التثبيت ولا يحتوي على السجل المدني الخام.',
                        ),
                      ),
                      SwitchListTile(
                        value: _scanSound,
                        onChanged: (value) =>
                            setState(() => _scanSound = value),
                        title: const Text('صوت نجاح المسح'),
                      ),
                      SwitchListTile(
                        value: _scanHaptic,
                        onChanged: (value) =>
                            setState(() => _scanHaptic = value),
                        title: const Text('اهتزاز نجاح المسح'),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: DropdownButtonFormField<String>(
                          value: _barcodeCardSize,
                          decoration: const InputDecoration(
                            labelText: 'حجم بطاقة الباركود',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'compact',
                              child: Text('صغيرة — عدد أكبر في الصفحة'),
                            ),
                            DropdownMenuItem(
                              value: 'standard',
                              child: Text('قياسية'),
                            ),
                            DropdownMenuItem(
                              value: 'large',
                              child: Text('كبيرة وواضحة'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _barcodeCardSize = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'إعدادات التقارير والنسخ الاحتياطي',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _autoArchivePdf,
                          onChanged: (value) =>
                              setState(() => _autoArchivePdf = value),
                          title: const Text('أرشفة PDF تلقائيًا عند إنشائه'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _markUnregisteredPresentOnClose,
                          onChanged: (value) => setState(
                            () => _markUnregisteredPresentOnClose = value,
                          ),
                          title: const Text(
                            'اعتبار غير المسجلين حاضرين عند إغلاق التحضير',
                          ),
                          subtitle: const Text(
                            'يسمح بتسجيل الغائبين والمستأذنين فقط، ثم يحتسب بقية الطلاب حاضرين توفيرًا للوقت.',
                          ),
                        ),
                        TextField(
                          controller: _whatsappTemplate,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'قالب رسالة واتساب',
                            helperText:
                                'الحقول: {date} {total} {present} {absent} {excused}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _backupReminderDays,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'التذكير بالنسخ الاحتياطي كل (يوم)',
                            prefixIcon: Icon(Icons.backup_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('حفظ الإعدادات'),
                ),
              ],
            ),
    );
  }

  Future<void> _pickLogo() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1000,
      maxHeight: 1000,
    );
    if (image == null) return;
    final docs = await getApplicationDocumentsDirectory();
    final extension = p.extension(image.path).isEmpty
        ? '.jpg'
        : p.extension(image.path);
    final target = await File(
      image.path,
    ).copy(p.join(docs.path, 'school_logo$extension'));
    _logoPath = target.path;
    await ref
        .read(settingsRepositoryProvider)
        .set('school_logo_path', target.path);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (_academicYear.text.trim().isEmpty) {
        throw const FormatException('أدخل العام الدراسي الحالي.');
      }
      final repository = ref.read(settingsRepositoryProvider);
      await ref
          .read(studentRepositoryProvider)
          .setCurrentAcademicYear(
            label: _academicYear.text,
            userId: ref.read(currentUserProvider)!.id,
          );
      await Future.wait([
        repository.set('school_name', _schoolName.text),
        repository.set('semester', _semester.text),
        repository.set('agent_name', _agentName.text),
        repository.set('agent_phone', _agentPhone.text),
        repository.set('agent_send_method', _agentSendMethod),
        repository.set('contact_phone', _contactPhone.text),
        repository.set('whatsapp_template', _whatsappTemplate.text),
        repository.set(
          'backup_reminder_days',
          '${int.tryParse(_backupReminderDays.text.trim())?.clamp(1, 365) ?? 7}',
        ),
        repository.set('scan_sound', '$_scanSound'),
        repository.set('scan_haptic', '$_scanHaptic'),
        repository.set(
          'mark_unregistered_present_on_close',
          '$_markUnregisteredPresentOnClose',
        ),
        repository.set('auto_archive_pdf', '$_autoArchivePdf'),
        repository.set('barcode_card_size', _barcodeCardSize),
      ]);
      refreshData(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الإعدادات.'),
            backgroundColor: AppColors.present,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر حفظ الإعدادات: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
