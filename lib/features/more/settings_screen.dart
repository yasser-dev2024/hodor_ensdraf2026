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
  bool _loading = true;
  bool _saving = false;
  String? _logoPath;

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
    super.dispose();
  }

  Future<void> _load() async {
    final values = await ref.read(settingsRepositoryProvider).getAll();
    _schoolName.text = values['school_name'] ?? '';
    _academicYear.text = values['academic_year'] ?? '';
    _semester.text = values['semester'] ?? '';
    _agentName.text = values['agent_name'] ?? '';
    _agentPhone.text = values['agent_phone'] ?? '';
    _contactPhone.text = values['contact_phone'] ?? '';
    _logoPath = values['school_logo_path'];
    if (mounted) setState(() => _loading = false);
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
      final repository = ref.read(settingsRepositoryProvider);
      await Future.wait([
        repository.set('school_name', _schoolName.text),
        repository.set('academic_year', _academicYear.text),
        repository.set('semester', _semester.text),
        repository.set('agent_name', _agentName.text),
        repository.set('agent_phone', _agentPhone.text),
        repository.set('contact_phone', _contactPhone.text),
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
