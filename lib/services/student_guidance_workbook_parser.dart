import '../core/saudi_phone_formatter.dart';

class StudentGuidanceWorkbookParser {
  const StudentGuidanceWorkbookParser._();

  static const headers = <String>[
    'اسم الطالب',
    'السجل المدني',
    'الصف',
    'الفصل',
    'المرحلة',
    'جوال ولي الأمر',
  ];

  static List<List<String>>? parseSheets(
    Iterable<List<List<String>>> rawSheets,
  ) {
    final parsed = <List<String>>[];
    var recognizedSheets = 0;
    for (final rows in rawSheets) {
      final headerIndex = rows.take(40).toList().indexWhere(_isHeader);
      if (headerIndex < 0) continue;
      final header = rows[headerIndex];
      final phoneColumn = _column(header, 'الجوال');
      final classColumn = _column(header, 'الفصل');
      final gradeColumn = _column(header, 'رقمالصف');
      final nameColumn = _column(header, 'اسمالطالب');
      final nationalIdColumn = _column(header, 'رقمالطالب');
      if (phoneColumn == null ||
          nameColumn == null ||
          nationalIdColumn == null) {
        continue;
      }
      recognizedSheets++;
      for (var index = headerIndex + 1; index < rows.length; index++) {
        final row = rows[index];
        final name = _cell(
          row,
          nameColumn,
        ).replaceAll(RegExp(r'\s+'), ' ').trim();
        final nationalId = _digits(_cell(row, nationalIdColumn));
        final phone = SaudiPhoneFormatter.normalize(_cell(row, phoneColumn));
        if (name.isEmpty && nationalId.isEmpty && phone.isEmpty) continue;
        parsed.add(<String>[
          name,
          nationalId,
          _gradeName(gradeColumn == null ? '' : _cell(row, gradeColumn)),
          classColumn == null ? '' : _cell(row, classColumn),
          'المرحلة الابتدائية',
          phone,
        ]);
      }
    }
    if (recognizedSheets == 0 || parsed.isEmpty) return null;
    return <List<String>>[headers, ...parsed];
  }

  static bool _isHeader(List<String> row) {
    final normalized = row.map(_normalizeHeader).toSet();
    return normalized.containsAll(const {'الجوال', 'اسمالطالب', 'رقمالطالب'});
  }

  static int? _column(List<String> row, String header) {
    for (var index = 0; index < row.length; index++) {
      if (_normalizeHeader(row[index]) == header) return index;
    }
    return null;
  }

  static String _gradeName(String value) {
    final digits = _digits(value);
    final match = RegExp(r'^0?([1-6])30$').firstMatch(digits);
    final grade = match == null ? int.tryParse(digits) : int.parse(match[1]!);
    return switch (grade) {
      1 => 'الأول',
      2 => 'الثاني',
      3 => 'الثالث',
      4 => 'الرابع',
      5 => 'الخامس',
      6 => 'السادس',
      _ => value.trim(),
    };
  }

  static String _cell(List<String> row, int column) =>
      column < row.length ? row[column].trim() : '';

  static String _digits(String value) => value
      .replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '')
      .replaceAllMapped(
        RegExp('[٠-٩]'),
        (match) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(match.group(0)!)}',
      )
      .replaceAllMapped(
        RegExp('[۰-۹]'),
        (match) => '${'۰۱۲۳۴۵۶۷۸۹'.indexOf(match.group(0)!)}',
      );

  static String _normalizeHeader(String value) => value
      .trim()
      .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll(RegExp(r'[^0-9ء-ي]'), '');
}
