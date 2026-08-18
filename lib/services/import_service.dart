import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:excel2003/excel2003.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../models/import_models.dart';
import '../repositories/class_repository.dart';
import '../repositories/student_repository.dart';
import 'data_protection_service.dart';

class StudentImportService {
  StudentImportService({
    required AppDatabase database,
    required StudentRepository students,
    required ClassRepository classes,
  }) : _database = database,
       _students = students,
       _classes = classes;

  final AppDatabase _database;
  final StudentRepository _students;
  final ClassRepository _classes;

  static final Map<ImportField, List<String>> _aliases = {
    ImportField.studentName: [
      'اسم الطالب',
      'الاسم',
      'اسم',
      'اسم المتعلم',
      'الطالب',
      'student name',
      'name',
    ],
    ImportField.nationalId: [
      'السجل المدني',
      'رقم السجل المدني',
      'رقم الهوية',
      'الهوية',
      'رقم هوية',
      'national id',
      'id number',
    ],
    ImportField.stage: ['المرحلة', 'المرحلة الدراسية', 'stage'],
    ImportField.grade: ['الصف', 'الصف الدراسي', 'grade'],
    ImportField.schoolClass: ['الفصل', 'الشعبة', 'فصل', 'class', 'section'],
    ImportField.academicNumber: [
      'الرقم الأكاديمي',
      'رقم الطالب',
      'الرقم الطلابي',
      'student id',
      'academic number',
    ],
  };

  Future<ImportWorkbook> readFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final extension = fileName.split('.').last.toLowerCase();
    try {
      if (extension == 'xlsx') return _readXlsx(fileName, bytes);
      if (extension == 'xls') return _readXls(fileName, bytes);
      throw const FormatException(
        'نوع الملف غير مدعوم. استخدم ملف Excel بصيغة XLSX أو XLS.',
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'تعذر قراءة الملف. يرجى التأكد من أن الملف صالح وغير محمي بكلمة مرور.',
      );
    }
  }

  ImportWorkbook _readXlsx(String fileName, Uint8List bytes) {
    final book = Excel.decodeBytes(bytes);
    final sheets = <ImportSheetData>[];
    for (final entry in book.tables.entries) {
      final table = entry.value;
      final rows = table.rows
          .map((row) => row.map((cell) => _cleanCell(cell?.value)).toList())
          .toList();
      sheets.add(ImportSheetData(name: entry.key, rows: rows));
    }
    if (sheets.isEmpty) {
      throw const FormatException(
        'ملف Excel لا يحتوي على أوراق قابلة للقراءة.',
      );
    }
    return ImportWorkbook(
      fileName: fileName,
      sourceType: 'xlsx',
      sheets: sheets,
    );
  }

  ImportWorkbook _readXls(String fileName, Uint8List bytes) {
    final reader = XlsReader.fromBytes(bytes)..open();
    final sheets = <ImportSheetData>[];
    for (var index = 0; index < reader.sheetCount; index++) {
      final sheet = reader.sheet(index);
      final rows = <List<String>>[];
      for (var row = sheet.firstRow; row < sheet.lastRow; row++) {
        final values = <String>[];
        for (var column = sheet.firstCol; column < sheet.lastCol; column++) {
          values.add(_cleanCell(sheet.cell(row, column)));
        }
        rows.add(values);
      }
      sheets.add(ImportSheetData(name: sheet.name, rows: rows));
    }
    if (sheets.isEmpty) {
      throw const FormatException('ملف XLS لا يحتوي على أوراق قابلة للقراءة.');
    }
    return ImportWorkbook(
      fileName: fileName,
      sourceType: 'xls',
      sheets: sheets,
    );
  }

  Future<ImportPreview> preview(
    ImportWorkbook workbook, {
    int sheetIndex = 0,
    Map<int, ImportField>? manualMapping,
  }) async {
    if (sheetIndex < 0 || sheetIndex >= workbook.sheets.length) {
      throw RangeError.index(sheetIndex, workbook.sheets);
    }
    final sheet = workbook.sheets[sheetIndex];
    final savedMappings = await _loadSavedMappings();
    final headerIndex = _detectHeaderRow(sheet.rows, savedMappings);
    if (headerIndex < 0) {
      throw const FormatException(
        'تعذر تحديد صف العناوين. تأكد من وجود عمودي اسم الطالب والسجل المدني.',
      );
    }
    final headers = sheet.rows[headerIndex];
    final mapping = manualMapping ?? _mapHeaders(headers, savedMappings);
    final seenIds = <String>{};
    final candidates = <ImportCandidate>[];
    for (
      var rowIndex = headerIndex + 1;
      rowIndex < sheet.rows.length;
      rowIndex++
    ) {
      final row = sheet.rows[rowIndex];
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final values = <ImportField, String>{};
      for (final entry in mapping.entries) {
        if (entry.value == ImportField.ignored) continue;
        values[entry.value] = entry.key < row.length
            ? row[entry.key].trim()
            : '';
      }
      final name = values[ImportField.studentName] ?? '';
      final nationalId = values[ImportField.nationalId] ?? '';
      final normalizedId = DataProtectionService.normalizeNationalId(
        nationalId,
      );
      final errors = <String>[];
      if (name.length < 2) errors.add('اسم الطالب مفقود أو قصير');
      if (normalizedId.length < 4) errors.add('السجل المدني مفقود أو غير صالح');
      final duplicateInFile =
          normalizedId.isNotEmpty && !seenIds.add(normalizedId);
      final duplicateInDatabase =
          normalizedId.length >= 4 &&
          await _students.nationalIdExists(normalizedId);
      candidates.add(
        ImportCandidate(
          sourceRow: rowIndex + 1,
          values: values,
          errors: errors,
          duplicateInFile: duplicateInFile,
          duplicateInDatabase: duplicateInDatabase,
        ),
      );
    }
    return ImportPreview(
      workbook: workbook,
      sheetIndex: sheetIndex,
      headerRowIndex: headerIndex,
      columnMapping: mapping,
      headers: headers,
      candidates: candidates,
      unrecognizedColumns: [
        for (var i = 0; i < headers.length; i++)
          if (!mapping.containsKey(i)) headers[i],
      ],
    );
  }

  Future<ImportResult> import(
    ImportPreview preview, {
    required String userId,
  }) async {
    var imported = 0;
    var duplicates = 0;
    var errors = 0;
    await _saveMappings(preview.headers, preview.columnMapping);
    for (final candidate in preview.candidates) {
      if (candidate.duplicateInFile || candidate.duplicateInDatabase) {
        duplicates++;
        continue;
      }
      if (candidate.errors.isNotEmpty) {
        errors++;
        continue;
      }
      try {
        final values = candidate.values;
        final gradeName = values[ImportField.grade]?.trim() ?? '';
        final className = values[ImportField.schoolClass]?.trim() ?? '';
        String? gradeId;
        String? classId;
        if (gradeName.isNotEmpty && className.isNotEmpty) {
          final schoolClass = await _classes.ensureClass(
            gradeName,
            className,
            userId: userId,
          );
          gradeId = schoolClass.gradeId;
          classId = schoolClass.id;
        } else if (gradeName.isNotEmpty) {
          gradeId = (await _classes.ensureGrade(gradeName, userId: userId)).id;
        }
        await _students.create(
          name: values[ImportField.studentName]!,
          nationalId: values[ImportField.nationalId]!,
          stage: values[ImportField.stage] ?? '',
          gradeId: gradeId,
          classId: classId,
          academicNumber: values[ImportField.academicNumber],
          userId: userId,
        );
        imported++;
      } on DuplicateStudentException {
        duplicates++;
      } catch (_) {
        errors++;
      }
    }
    await _database.db.insert('audit_logs', {
      'action': 'excel_import',
      'entity_type': 'import',
      'user_id': userId,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'new_value':
          '{"file":"${preview.workbook.fileName.replaceAll('"', '')}","imported":$imported,"duplicates":$duplicates,"errors":$errors}',
    });
    return ImportResult(
      imported: imported,
      duplicates: duplicates,
      errors: errors,
    );
  }

  int _detectHeaderRow(
    List<List<String>> rows,
    Map<String, ImportField> saved,
  ) {
    var bestIndex = -1;
    var bestScore = 0;
    for (var index = 0; index < rows.length && index < 40; index++) {
      final mapped = _mapHeaders(rows[index], saved).values.toSet();
      var score = mapped.length;
      if (mapped.contains(ImportField.studentName)) score += 4;
      if (mapped.contains(ImportField.nationalId)) score += 4;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    return bestScore >= 5 ? bestIndex : -1;
  }

  Map<int, ImportField> _mapHeaders(
    List<String> headers,
    Map<String, ImportField> saved,
  ) {
    final result = <int, ImportField>{};
    final used = <ImportField>{};
    for (var index = 0; index < headers.length; index++) {
      final normalized = normalizeHeader(headers[index]);
      ImportField? match = saved[normalized];
      match ??= _aliases.entries
          .where(
            (entry) => entry.value.any(
              (alias) => normalizeHeader(alias) == normalized,
            ),
          )
          .map((entry) => entry.key)
          .firstOrNull;
      if (match != null && !used.contains(match)) {
        result[index] = match;
        used.add(match);
      }
    }
    return result;
  }

  Future<Map<String, ImportField>> _loadSavedMappings() async {
    final rows = await _database.db.query('saved_mappings');
    return {
      for (final row in rows)
        row['normalized_header'] as String: ImportField.values.firstWhere(
          (field) => field.key == row['target_field'],
          orElse: () => ImportField.ignored,
        ),
    };
  }

  Future<void> _saveMappings(
    List<String> headers,
    Map<int, ImportField> mapping,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.db.transaction((txn) async {
      for (final entry in mapping.entries) {
        if (entry.key >= headers.length || entry.value == ImportField.ignored) {
          continue;
        }
        await txn.insert('saved_mappings', {
          'normalized_header': normalizeHeader(headers[entry.key]),
          'target_field': entry.value.key,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static String normalizeHeader(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
      .replaceAll(RegExp(r'[^a-z0-9ء-ي]'), '');

  static String _cleanCell(Object? value) {
    if (value == null) return '';
    var text = value.toString().trim();
    text = text.replaceAll(RegExp(r'\.0$'), '');
    return text;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
