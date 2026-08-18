import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/import_models.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  ImportWorkbook? _workbook;
  ImportPreview? _preview;
  bool _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد الطلاب')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Icon(
                    Icons.upload_file_rounded,
                    size: 58,
                    color: AppColors.blue,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'استيراد ذكي من Excel',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'يدعم XLSX وXLS القديم. يكتشف صف العناوين حتى مع وجود شعار أو أسطر قبله.',
                    textAlign: TextAlign.center,
                    style: TextStyle(height: 1.55, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('اختيار ملف'),
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F5F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _status!,
                  style: const TextStyle(
                    color: AppColors.present,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (_workbook != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _workbook!.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      'النوع: ${_workbook!.sourceType.toUpperCase()}  •  عدد الأوراق: ${_workbook!.sheets.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                    if (_workbook!.sheets.length > 1) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _preview?.sheetIndex ?? 0,
                        decoration: const InputDecoration(
                          labelText: 'ورقة العمل',
                        ),
                        items: [
                          for (var i = 0; i < _workbook!.sheets.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(_workbook!.sheets[i].name),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) {
                                if (value != null) _analyze(sheetIndex: value);
                              },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (_preview != null) ...[
            const SizedBox(height: 14),
            _PreviewStats(preview: _preview!),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مطابقة الأعمدة',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تم اكتشاف صف العناوين في السطر ${_preview!.headerRowIndex + 1}. يمكنك تعديل أي مطابقة قبل الاستيراد.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const Divider(height: 24),
                    for (
                      var index = 0;
                      index < _preview!.headers.length;
                      index++
                    )
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _preview!.headers[index].isEmpty
                                    ? 'عمود ${index + 1}'
                                    : _preview!.headers[index],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                              color: Colors.blueGrey,
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 155,
                              child: DropdownButtonFormField<ImportField>(
                                value:
                                    _preview!.columnMapping[index] ??
                                    ImportField.ignored,
                                isDense: true,
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                                items: ImportField.values
                                    .map(
                                      (field) => DropdownMenuItem(
                                        value: field,
                                        child: Text(
                                          field.label,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _busy
                                    ? null
                                    : (field) => _changeMapping(
                                        index,
                                        field ?? ImportField.ignored,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_preview!.errorCount > 0 || _preview!.duplicateCount > 0) ...[
              const SizedBox(height: 14),
              Card(
                child: ExpansionTile(
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.excused,
                  ),
                  title: const Text(
                    'الصفوف المستبعدة',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${_preview!.duplicateCount} مكرر، ${_preview!.errorCount} به أخطاء',
                  ),
                  children: _preview!.candidates
                      .where((row) => !row.canImport)
                      .take(20)
                      .map(
                        (row) => ListTile(
                          dense: true,
                          title: Text(
                            'السطر ${row.sourceRow}: ${row.values[ImportField.studentName] ?? 'بدون اسم'}',
                          ),
                          subtitle: Text(
                            row.duplicateInFile
                                ? 'مكرر داخل الملف'
                                : row.duplicateInDatabase
                                ? 'مسجل مسبقًا في قاعدة البيانات'
                                : row.errors.join('، '),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy || _preview!.validCount == 0 ? null : _import,
              icon: const Icon(Icons.cloud_done_outlined),
              label: Text('استيراد ${_preview!.validCount} طالبًا'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await fp.FilePicker.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: const ['xlsx', 'xls'],
        withData: true,
      );
      if (result == null) return;
      final picked = result.files.single;
      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null) {
        throw const FormatException('تعذر الوصول إلى محتوى الملف.');
      }
      final workbook = await ref
          .read(importServiceProvider)
          .readFile(fileName: picked.name, bytes: bytes);
      _workbook = workbook;
      _preview = await ref.read(importServiceProvider).preview(workbook);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: AppColors.absent),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze({
    required int sheetIndex,
    Map<int, ImportField>? mapping,
  }) async {
    if (_workbook == null) return;
    setState(() => _busy = true);
    try {
      final preview = await ref
          .read(importServiceProvider)
          .preview(_workbook!, sheetIndex: sheetIndex, manualMapping: mapping);
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeMapping(int column, ImportField field) async {
    final current = _preview!;
    final mapping = Map<int, ImportField>.from(current.columnMapping);
    mapping.removeWhere(
      (key, value) =>
          value == field && key != column && field != ImportField.ignored,
    );
    if (field == ImportField.ignored) {
      mapping.remove(column);
    } else {
      mapping[column] = field;
    }
    await _analyze(sheetIndex: current.sheetIndex, mapping: mapping);
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(importServiceProvider)
          .import(_preview!, userId: ref.read(currentUserProvider)!.id);
      refreshData(ref);
      if (mounted) {
        setState(() {
          _status =
              'تمت إضافة ${result.imported} طالبًا. تم تجاهل ${result.duplicates} مكرر، وتعذر استيراد ${result.errors} صف.';
          _preview = null;
          _workbook = null;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر الاستيراد: $error'),
            backgroundColor: AppColors.absent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PreviewStats extends StatelessWidget {
  const _PreviewStats({required this.preview});
  final ImportPreview preview;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'معاينة الاستيراد',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              _ImportStat(
                label: 'الصفوف',
                value: preview.totalRows,
                color: AppColors.navy,
              ),
              _ImportStat(
                label: 'سيضاف',
                value: preview.validCount,
                color: AppColors.present,
              ),
              _ImportStat(
                label: 'مكرر',
                value: preview.duplicateCount,
                color: AppColors.excused,
              ),
              _ImportStat(
                label: 'أخطاء',
                value: preview.errorCount,
                color: AppColors.absent,
              ),
            ],
          ),
          if (preview.unrecognizedColumns
              .where((value) => value.isNotEmpty)
              .isNotEmpty) ...[
            const Divider(height: 25),
            Text(
              'أعمدة غير معروفة: ${preview.unrecognizedColumns.where((value) => value.isNotEmpty).join('، ')}',
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ImportStat extends StatelessWidget {
  const _ImportStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}
