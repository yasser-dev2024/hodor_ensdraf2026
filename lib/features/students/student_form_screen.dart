import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/school_class.dart';
import '../../models/student.dart';
import 'student_photo.dart';

class StudentFormScreen extends ConsumerStatefulWidget {
  const StudentFormScreen({this.student, super.key});
  final Student? student;

  @override
  ConsumerState<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends ConsumerState<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final String _studentId;
  late final TextEditingController _name;
  late final TextEditingController _nationalId;
  late final TextEditingController _stage;
  late final TextEditingController _academicNumber;
  String? _classId;
  String? _selectedPhotoSource;
  bool _removePhoto = false;
  bool _busy = false;
  late Future<List<SchoolClass>> _classes;

  bool get _editing => widget.student != null;

  @override
  void initState() {
    super.initState();
    final student = widget.student;
    _studentId = student?.id ?? const Uuid().v4();
    _name = TextEditingController(text: student?.name ?? '');
    _nationalId = TextEditingController(text: student?.nationalId ?? '');
    _stage = TextEditingController(text: student?.stage ?? '');
    _academicNumber = TextEditingController(
      text: student?.academicNumber ?? '',
    );
    _classId = student?.classId;
    _classes = ref.read(classRepositoryProvider).getClasses();
  }

  @override
  void dispose() {
    _name.dispose();
    _nationalId.dispose();
    _stage.dispose();
    _academicNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedPhoto = _removePhoto
        ? null
        : (_selectedPhotoSource ?? widget.student?.photoPath);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'تعديل بيانات الطالب' : 'إضافة طالب'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      StudentPhoto(
                        path: displayedPhoto,
                        size: 142,
                        highlighted: true,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _choosePhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('إضافة صورة'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _choosePhoto(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('التقاط صورة'),
                          ),
                          if (displayedPhoto != null)
                            IconButton.filledTonal(
                              onPressed: () => setState(() {
                                _selectedPhotoSource = null;
                                _removePhoto = true;
                              }),
                              tooltip: 'إزالة الصورة',
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'تظهر هذه الصورة بشكل بارز فور مسح باركود الطالب.',
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
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
                    children: [
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'اسم الطالب *',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (value) =>
                            value == null || value.trim().length < 2
                            ? 'أدخل اسم الطالب'
                            : null,
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _nationalId,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9٠-٩]'),
                          ),
                          LengthLimitingTextInputFormatter(10),
                        ],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'السجل المدني *',
                          prefixIcon: Icon(Icons.badge_outlined),
                          helperText: 'يُشفّر داخل الجهاز ولا يُوضع في رمز QR.',
                        ),
                        validator: (value) {
                          final digits =
                              value?.replaceAll(RegExp(r'[^0-9٠-٩]'), '') ?? '';
                          return digits.length != 10
                              ? 'السجل المدني يجب أن يتكون من 10 أرقام'
                              : null;
                        },
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _academicNumber,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'الرقم الأكاديمي (اختياري)',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _stage,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'المرحلة',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                      ),
                      const SizedBox(height: 13),
                      FutureBuilder<List<SchoolClass>>(
                        future: _classes,
                        builder: (context, snapshot) {
                          final classes =
                              snapshot.data ?? const <SchoolClass>[];
                          return DropdownButtonFormField<String>(
                            value: classes.any((item) => item.id == _classId)
                                ? _classId
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'الصف / الفصل',
                              prefixIcon: Icon(Icons.meeting_room_outlined),
                            ),
                            items: classes
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.id,
                                    child: Text(item.label),
                                  ),
                                )
                                .toList(),
                            onChanged: snapshot.hasData
                                ? (value) => setState(() => _classId = value)
                                : null,
                            hint: Text(
                              classes.isEmpty
                                  ? 'أضف الصفوف والفصول من قسم المزيد'
                                  : 'اختر الصف والفصل',
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _editing ? 'حفظ التعديلات' : 'إضافة الطالب وإنشاء QR',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: AppColors.blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choosePhoto(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1200,
        maxHeight: 1200,
        requestFullMetadata: false,
      );
      if (image != null && mounted) {
        setState(() {
          _selectedPhotoSource = image.path;
          _removePhoto = false;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر اختيار الصورة: $error')));
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final user = ref.read(currentUserProvider)!;
    String? photoPath = _removePhoto ? null : widget.student?.photoPath;
    var copiedNewPhoto = false;
    try {
      if (_selectedPhotoSource != null) {
        photoPath = await ref
            .read(imageStorageProvider)
            .saveStudentPhoto(
              studentId: _studentId,
              sourcePath: _selectedPhotoSource!,
            );
        copiedNewPhoto = true;
      }
      final classes = await _classes;
      final selectedClass = classes
          .where((item) => item.id == _classId)
          .firstOrNull;
      if (_editing) {
        final old = widget.student!;
        final updated = Student(
          id: old.id,
          name: _name.text.trim(),
          nationalId: _nationalId.text,
          barcodeToken: old.barcodeToken,
          stage: _stage.text.trim(),
          gradeId: selectedClass?.gradeId,
          gradeName: selectedClass?.gradeName,
          classId: selectedClass?.id,
          className: selectedClass?.name,
          academicNumber: _academicNumber.text.trim(),
          photoPath: photoPath,
          status: old.status,
          transferStatus: old.transferStatus,
          createdAt: old.createdAt,
          updatedAt: DateTime.now().toUtc(),
          deletedAt: old.deletedAt,
        );
        await ref
            .read(studentRepositoryProvider)
            .update(updated, userId: user.id);
        if (_removePhoto) {
          await ref.read(imageStorageProvider).deletePhoto(old.photoPath);
        }
      } else {
        await ref
            .read(studentRepositoryProvider)
            .create(
              name: _name.text,
              nationalId: _nationalId.text,
              stage: _stage.text,
              gradeId: selectedClass?.gradeId,
              classId: selectedClass?.id,
              academicNumber: _academicNumber.text,
              photoPath: photoPath,
              forcedId: _studentId,
              userId: user.id,
            );
      }
      if (!mounted) return;
      refreshData(ref);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!_editing && copiedNewPhoto) {
        await ref.read(imageStorageProvider).deletePhoto(photoPath);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
