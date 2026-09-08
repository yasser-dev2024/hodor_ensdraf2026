enum ImportField {
  studentName('name', 'اسم الطالب'),
  nationalId('national_id', 'السجل المدني'),
  stage('stage', 'المرحلة'),
  grade('grade', 'الصف'),
  schoolClass('class', 'الفصل'),
  academicNumber('academic_number', 'الرقم الأكاديمي'),
  guardianPhone('guardian_phone', 'جوال ولي الأمر'),
  ignored('ignored', 'تجاهل العمود');

  const ImportField(this.key, this.label);
  final String key;
  final String label;
}

class ImportSheetData {
  const ImportSheetData({required this.name, required this.rows});
  final String name;
  final List<List<String>> rows;
}

class ImportWorkbook {
  const ImportWorkbook({
    required this.fileName,
    required this.sourceType,
    required this.sheets,
    this.guardianContactsOnly = false,
  });
  final String fileName;
  final String sourceType;
  final List<ImportSheetData> sheets;
  final bool guardianContactsOnly;
}

class ImportCandidate {
  const ImportCandidate({
    required this.sourceRow,
    required this.values,
    required this.errors,
    required this.duplicateInFile,
    required this.duplicateInDatabase,
  });
  final int sourceRow;
  final Map<ImportField, String> values;
  final List<String> errors;
  final bool duplicateInFile;
  final bool duplicateInDatabase;
  bool get canImport =>
      errors.isEmpty && !duplicateInFile && !duplicateInDatabase;
  bool get canUpdateGuardianPhone =>
      errors.isEmpty &&
      !duplicateInFile &&
      duplicateInDatabase &&
      (values[ImportField.guardianPhone]?.isNotEmpty ?? false);
  bool get canProcess => canImport || canUpdateGuardianPhone;
}

class ImportPreview {
  const ImportPreview({
    required this.workbook,
    required this.sheetIndex,
    required this.headerRowIndex,
    required this.columnMapping,
    required this.headers,
    required this.candidates,
    required this.unrecognizedColumns,
  });
  final ImportWorkbook workbook;
  final int sheetIndex;
  final int headerRowIndex;
  final Map<int, ImportField> columnMapping;
  final List<String> headers;
  final List<ImportCandidate> candidates;
  final List<String> unrecognizedColumns;

  int get validCount => candidates.where((row) => row.canImport).length;
  int get guardianUpdateCount =>
      candidates.where((row) => row.canUpdateGuardianPhone).length;
  int get processableCount =>
      workbook.guardianContactsOnly ? guardianUpdateCount : validCount;
  int get unmatchedContactCount => workbook.guardianContactsOnly
      ? candidates
            .where(
              (row) =>
                  row.errors.isEmpty &&
                  !row.duplicateInFile &&
                  !row.duplicateInDatabase,
            )
            .length
      : 0;
  int get duplicateCount => candidates
      .where((row) => row.duplicateInFile || row.duplicateInDatabase)
      .length;
  int get errorCount => candidates.where((row) => row.errors.isNotEmpty).length;
  int get totalRows => candidates.length;
}

class ImportResult {
  const ImportResult({
    required this.imported,
    required this.duplicates,
    required this.errors,
    this.updatedGuardianPhones = 0,
    this.unmatchedContacts = 0,
  });
  final int imported;
  final int duplicates;
  final int errors;
  final int updatedGuardianPhones;
  final int unmatchedContacts;
}
