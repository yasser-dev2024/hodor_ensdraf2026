class OfficialStudentPdfParser {
  const OfficialStudentPdfParser._();

  static const headers = <String>[
    'اسم الطالب',
    'السجل المدني',
    'الصف',
    'الفصل',
  ];

  static const guardianContactHeaders = <String>[
    'اسم الطالب',
    'السجل المدني',
    'الصف',
    'الفصل',
    'المرحلة',
    'جوال ولي الأمر',
  ];

  static const _gradePattern = r'(?:الأول|الثاني|الثالث|الرابع|الخامس|السادس)';

  static final RegExp _registryRecordEnd = RegExp(r'الدراسة(?=\n|$)');

  static final RegExp _studentDataRecord = RegExp(
    r'([0-9]{10})\s+(?:رقم\s+الهوية|رخصة\s+(?:اقامه|إقامة)|رقم\s+جواز(?:\s+سفر)?)\s+'
    r'([\u0621-\u064a]+)\s+([\u0621-\u064a][\u0621-\u064a\s.\-]+?)\s+'
    r'([0-9]{1,3})(?=\n|$)',
    multiLine: true,
  );

  static final RegExp _englishNationalId = RegExp(
    r'[A-Z](?:[A-Z .\-\n]){2,}?([0-9]{10})',
  );

  static List<List<String>>? parsePages(Iterable<String> rawPages) {
    final pages = rawPages
        .map(normalizeExtractedText)
        .where((page) => page.trim().isNotEmpty)
        .toList();
    if (pages.isEmpty) return null;

    final rosterRows = _parseOfficialRosterPages(pages);
    if (rosterRows.isNotEmpty) {
      return <List<String>>[headers, ...rosterRows];
    }

    final studentDataRows = _parseStudentDataListPages(pages);
    if (studentDataRows.isNotEmpty) {
      return <List<String>>[headers, ...studentDataRows];
    }

    final registryRows = _parseOfficialRegistryPages(pages);
    if (registryRows.isNotEmpty) {
      return <List<String>>[headers, ...registryRows];
    }
    return null;
  }

  /// Reads guardian mobile numbers from the two PDF layouts used by the
  /// school's exports. The returned rows are intentionally contact-only and
  /// are matched to existing students by national ID by the import service.
  static List<List<String>>? parseGuardianContactPages(
    Iterable<String> rawPages,
  ) {
    final pages = rawPages
        .map(normalizeExtractedText)
        .where((page) => page.trim().isNotEmpty)
        .toList();
    if (pages.isEmpty) return null;

    final rows = <List<String>>[];
    final seenNationalIds = <String>{};
    _parseMorningAttendanceGuardianContacts(pages, rows, seenNationalIds);
    _parseOfficialRosterGuardianContacts(pages, rows, seenNationalIds);
    if (rows.isEmpty) return null;
    return <List<String>>[guardianContactHeaders, ...rows];
  }

  static void _parseMorningAttendanceGuardianContacts(
    List<String> pages,
    List<List<String>> rows,
    Set<String> seenNationalIds,
  ) {
    final spacedRecord = RegExp(
      '^((?:9665[0-9]{8}|05[0-9]{8}))\\s+'
      'الصف\\s+($_gradePattern)(?:\\s+الابتدائي)?\\s+'
      '([0-9]{1,2})\\s+([0-9]{10})\\s+'
      '([\\u0621-\\u064a][\\u0621-\\u064a\\s.\\-]+?)\\s+'
      '[0-9]{1,3}\$',
      multiLine: true,
    );
    for (final page in pages) {
      if (!page.contains('برنامج التحضير الصباحي') ||
          !page.contains('رقم الجوال') ||
          !page.contains('رقم الهوية')) {
        continue;
      }
      for (final match in spacedRecord.allMatches(page)) {
        final nationalId = match.group(4)!;
        if (!seenNationalIds.add(nationalId)) continue;
        rows.add(<String>[
          match.group(5)!.replaceAll(RegExp(r'\s+'), ' ').trim(),
          nationalId,
          _normalizeGrade(match.group(2)!),
          match.group(3)!,
          'المرحلة الابتدائية',
          match.group(1)!,
        ]);
      }
      for (final line in page.split('\n')) {
        final parsed = _parseCompactMorningAttendanceContact(line);
        if (parsed == null || !seenNationalIds.add(parsed[1])) continue;
        rows.add(parsed);
      }
    }
  }

  static List<String>? _parseCompactMorningAttendanceContact(String line) {
    final match = RegExp(
      '^(.*?)((?:9665[0-9]{8}|05[0-9]{8}|5[0-9]{8}))'
      'الصف\\s+($_gradePattern)(?:\\s+الابتدائي)?\\s+'
      '([0-9]{10})([0-9]{1,2})(.*)\$',
    ).firstMatch(line.trim());
    if (match == null) return null;

    final beforePhone = match
        .group(1)!
        .replaceFirst(RegExp(r'[0-9]{1,3}\s*$'), '')
        .trim();
    final afterIdentity = match
        .group(6)!
        .replaceFirst(RegExp(r'[0-9]{1,3}\s*$'), '')
        .replaceFirst(RegExp(r'^[^ء-ي]+'), '')
        .trim();
    final name = '$afterIdentity$beforePhone'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.length < 2) return null;

    var phone = match.group(2)!;
    if (phone.length == 9) phone = '966$phone';
    return <String>[
      name,
      match.group(4)!,
      _normalizeGrade(match.group(3)!),
      match.group(5)!,
      'المرحلة الابتدائية',
      phone,
    ];
  }

  static void _parseOfficialRosterGuardianContacts(
    List<String> pages,
    List<List<String>> rows,
    Set<String> seenNationalIds,
  ) {
    final isGuardianRoster = pages.any(
      (page) => page.contains('رقم جوال') && page.contains('كشف الطلاب'),
    );
    if (!isGuardianRoster) return;

    final rosterRows = _parseOfficialRosterPages(pages);
    final guardianPhones = _extractOfficialGuardianPhones(pages);
    if (rosterRows.isNotEmpty && rosterRows.length == guardianPhones.length) {
      for (var index = 0; index < rosterRows.length; index++) {
        final rosterRow = rosterRows[index];
        final nationalId = rosterRow[1];
        if (!seenNationalIds.add(nationalId)) continue;
        rows.add(<String>[
          rosterRow[0],
          nationalId,
          rosterRow[2],
          rosterRow[3],
          rosterRow[2].isEmpty ? '' : 'المرحلة الابتدائية',
          guardianPhones[index],
        ]);
      }
      return;
    }

    String? currentGrade;
    String? currentClass;
    for (final page in pages) {
      final lines = page
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      final pageGrade =
          _valueFollowingLabel(
            lines,
            'الصف',
            RegExp('^$_gradePattern(?:\\s+الابتدائي)?\$'),
          ) ??
          _gradeBesideLabel(lines.join('\n'));
      final pageClass =
          _valueFollowingLabel(lines, 'الفصل', RegExp(r'^[0-9]{1,2}$')) ??
          _classBesideLabel(lines.join('\n'));
      if (pageGrade != null) currentGrade = _normalizeGrade(pageGrade);
      if (pageClass != null) currentClass = pageClass;

      var recordStart = 0;
      for (var index = 0; index < lines.length; index++) {
        final statusEnd = _rosterStatusEnd(lines, index);
        if (statusEnd == null) continue;

        var serialIndex = statusEnd;
        final nameLines = <String>[];
        while (serialIndex < lines.length) {
          final line = lines[serialIndex];
          final serialMatch = RegExp(
            r'^(.*?)(?:\s+)?([0-9]{1,3})$',
          ).firstMatch(line);
          if (serialMatch != null) {
            final namePart = serialMatch.group(1)!.trim();
            if (RegExp(r'[ء-ي]').hasMatch(namePart)) nameLines.add(namePart);
            break;
          }
          if (RegExp(r'[ء-ي]').hasMatch(line)) nameLines.add(line);
          serialIndex++;
        }
        if (serialIndex >= lines.length) break;

        final nationalId = _nationalIdBeforeStatus(lines, index, recordStart);
        final guardianPhone = _guardianPhoneBeforeStatus(
          lines,
          index,
          recordStart,
        );
        final name = nameLines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (nationalId != null &&
            guardianPhone != null &&
            name.length >= 2 &&
            seenNationalIds.add(nationalId)) {
          rows.add(<String>[
            name,
            nationalId,
            currentGrade ?? '',
            currentClass ?? '',
            currentGrade == null ? '' : 'المرحلة الابتدائية',
            guardianPhone,
          ]);
        }
        recordStart = serialIndex + 1;
        index = serialIndex;
      }
    }
  }

  static List<String> _extractOfficialGuardianPhones(List<String> pages) {
    final phones = <String>[];
    String? pendingPrefix;
    for (final page in pages) {
      for (final line in page.split('\n').map((line) => line.trim())) {
        final complete = RegExp(r'^(9665[0-9]{8})(?=\s|$)').firstMatch(line);
        if (complete != null) {
          phones.add(complete.group(1)!);
          pendingPrefix = null;
          continue;
        }
        final prefix = RegExp(r'^(9665[0-9]{5})(?=\s|$)').firstMatch(line);
        if (prefix != null) {
          pendingPrefix = prefix.group(1)!;
          continue;
        }
        if (pendingPrefix == null) continue;
        final suffix = RegExp(r'^([0-9]{3})(?=\s|$)').firstMatch(line);
        if (suffix == null) continue;
        phones.add('$pendingPrefix${suffix.group(1)}');
        pendingPrefix = null;
      }
    }
    return phones;
  }

  static String? _guardianPhoneBeforeStatus(
    List<String> lines,
    int statusIndex,
    int recordStart,
  ) {
    String? prefix;
    for (var index = recordStart; index <= statusIndex; index++) {
      final line = lines[index];
      final complete = RegExp(
        r'(?:^|\s)((?:9665[0-9]{8}|05[0-9]{8}))(?=\s|$)',
      ).firstMatch(line);
      if (complete != null) return complete.group(1);

      prefix ??= RegExp(
        r'(?:^|\s)(9665[0-9]{5})(?=\s|$)',
      ).firstMatch(line)?.group(1);
      if (prefix == null) continue;

      final suffix = RegExp(r'^([0-9]{3})(?=\s|$)').firstMatch(line);
      if (suffix != null && line.substring(suffix.end).trim().isNotEmpty) {
        return '$prefix${suffix.group(1)}';
      }
    }
    return null;
  }

  /// Converts the multi-sheet "كشف الطلاب" Excel export into the same
  /// four-column table used by the regular importer. Ministry exports split a
  /// class over several sheets, so parsing a single selected sheet silently
  /// omits most of the students.
  static List<List<String>>? parseWorkbookSheets(
    Iterable<List<List<String>>> rawSheets,
  ) {
    final parsed = <List<String>>[];
    var recognizedSheets = 0;
    for (final rows in rawSheets) {
      if (rows.isEmpty) continue;
      final headerIndex = rows.indexWhere(_looksLikeRosterHeader);
      if (headerIndex < 0) continue;

      final header = rows[headerIndex];
      final nameColumn = _findColumn(header, const {'اسمالطالب'});
      final nationalIdColumn = _findColumn(header, const {
        'رقمرخصةالاقامة',
        'رقمرخصةالإقامة',
        'السجلالمدني',
        'رقمالهوية',
      });
      final classColumn = _findColumn(header, const {'الفصل'});
      if (nameColumn == null || nationalIdColumn == null) continue;

      final grade = _gradeFromWorkbookRows(rows.take(headerIndex));
      final stage = _stageFromWorkbookRows(rows.take(headerIndex));
      final fallbackClass = _classFromWorkbookRows(rows.take(headerIndex));
      final sheetRows = <List<String>>[];
      for (var index = headerIndex + 1; index < rows.length; index++) {
        final row = rows[index];
        final name = _cell(row, nameColumn).replaceAll(RegExp(r'\s+'), ' ');
        final nationalId = _normalizeDigits(
          _cell(row, nationalIdColumn),
        ).replaceAll(RegExp(r'\D'), '');
        if (name.length < 2 || nationalId.length != 10) continue;
        final schoolClass = classColumn == null
            ? fallbackClass
            : _cell(row, classColumn).trim();
        sheetRows.add(<String>[
          name.trim(),
          nationalId,
          grade,
          schoolClass.isEmpty ? fallbackClass : schoolClass,
          stage,
        ]);
      }
      if (sheetRows.isNotEmpty) {
        recognizedSheets++;
        parsed.addAll(sheetRows);
      }
    }
    if (recognizedSheets == 0 || parsed.isEmpty) return null;

    return <List<String>>[
      const <String>['اسم الطالب', 'السجل المدني', 'الصف', 'الفصل', 'المرحلة'],
      ...parsed,
    ];
  }

  /// Normalizes the two Arabic encodings encountered in official Ministry
  /// exports: Arabic presentation forms and Arial CID glyph numbers emitted
  /// when a PDF has no usable ToUnicode map.
  static String normalizeExtractedText(String input) {
    final cleaned = input
        .replaceAll('\u0000', '')
        .replaceAll('\ufeff', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final malformedCidText = _looksLikeMalformedArialCidText(cleaned);
    final normalizedLines = <String>[];
    for (final line in cleaned.split('\n')) {
      var normalized = line;
      if (malformedCidText && _containsArabicCidGlyph(normalized)) {
        normalized = _decodeReversedArabicCidLine(normalized);
      }
      normalized = _normalizeArabicPresentationForms(
        normalized,
      ).replaceAll('هللا', 'الله');
      normalized = _normalizeDigits(normalized)
          .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'), '')
          .replaceAll(RegExp(r'[\u0001-\u0008\u000b\u000c\u000e-\u001f]'), ' ')
          .replaceAll(RegExp(r'[ \t\u00a0]+'), ' ')
          .trim();
      normalizedLines.add(normalized);
    }
    return normalizedLines.join('\n').trim();
  }

  static List<List<String>> _parseOfficialRosterPages(List<String> pages) {
    final rows = <List<String>>[];
    final seenNationalIds = <String>{};
    String? currentGrade;
    String? currentClass;

    for (final page in pages) {
      final lines = page
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;

      final pageGrade =
          _valueFollowingLabel(
            lines,
            'الصف',
            RegExp('^$_gradePattern(?:\\s+الابتدائي)?\$'),
          ) ??
          _gradeBesideLabel(lines.join('\n'));
      final pageClass =
          _valueFollowingLabel(lines, 'الفصل', RegExp(r'^[0-9]{1,2}$')) ??
          _classBesideLabel(lines.join('\n'));
      if (pageGrade != null) currentGrade = _normalizeGrade(pageGrade);
      if (pageClass != null) currentClass = pageClass;
      if (currentGrade == null || currentClass == null) continue;

      var recordStart = 0;
      for (var index = 0; index < lines.length; index++) {
        final statusEnd = _rosterStatusEnd(lines, index);
        if (statusEnd == null) continue;

        var serialIndex = statusEnd;
        final nameLines = <String>[];
        while (serialIndex < lines.length) {
          final line = lines[serialIndex];
          final serialMatch = RegExp(
            r'^(.*?)(?:\s+)?([0-9]{1,3})$',
          ).firstMatch(line);
          if (serialMatch != null) {
            final namePart = serialMatch.group(1)!.trim();
            if (RegExp(r'[ء-ي]').hasMatch(namePart)) {
              nameLines.add(namePart);
            }
            break;
          }
          if (RegExp(r'[ء-ي]').hasMatch(line)) nameLines.add(line);
          serialIndex++;
        }
        if (serialIndex >= lines.length) break;

        final nationalId = _nationalIdBeforeStatus(lines, index, recordStart);
        final name = nameLines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (nationalId != null &&
            name.length >= 2 &&
            seenNationalIds.add(nationalId)) {
          rows.add(<String>[name, nationalId, currentGrade, currentClass]);
        }
        recordStart = serialIndex + 1;
        index = serialIndex;
      }
    }
    return rows;
  }

  static int? _rosterStatusEnd(List<String> lines, int index) {
    if (lines[index].endsWith('مستمر في الدراسة')) return index + 1;
    if (lines[index].endsWith('مستمر في') &&
        index + 1 < lines.length &&
        lines[index + 1] == 'الدراسة') {
      return index + 2;
    }
    return null;
  }

  static String? _nationalIdBeforeStatus(
    List<String> lines,
    int statusIndex,
    int recordStart,
  ) {
    final segment = lines.sublist(recordStart, statusIndex + 1).join('\n');
    final dates = RegExp(
      r'[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}',
    ).allMatches(segment).toList();
    if (dates.isEmpty) return null;
    final beforeBirthDate = segment.substring(0, dates.last.start);
    final groups = RegExp(
      r'[0-9]+',
    ).allMatches(beforeBirthDate).map((match) => match.group(0)!).toList();
    var nationalId = '';
    for (var index = groups.length - 1; index >= 0; index--) {
      final candidate = groups[index] + nationalId;
      if (candidate.length == 10) return candidate;
      if (candidate.length > 10) break;
      nationalId = candidate;
    }
    return null;
  }

  static String? _gradeBesideLabel(String page) {
    final match = RegExp(
      '($_gradePattern)(?:\\s+الابتدائي)?\\s*الصف|'
      'الصف\\s*($_gradePattern)(?:\\s+الابتدائي)?',
    ).firstMatch(page);
    final value = match?.group(1) ?? match?.group(2);
    return value == null ? null : _normalizeGrade(value);
  }

  static String? _classBesideLabel(String page) {
    final match = RegExp(
      r'(?:^|\n)([0-9]{1,2})\s*الفصل(?:\n|$)|الفصل\s*([0-9]{1,2})',
    ).firstMatch(page);
    return match?.group(1) ?? match?.group(2);
  }

  static String? _valueFollowingLabel(
    List<String> lines,
    String label,
    RegExp valuePattern,
  ) {
    for (var index = lines.length - 2; index >= 0; index--) {
      if (lines[index] == label && valuePattern.hasMatch(lines[index + 1])) {
        return lines[index + 1];
      }
    }
    return null;
  }

  static List<List<String>> _parseStudentDataListPages(List<String> pages) {
    final rows = <List<String>>[];
    final seenNationalIds = <String>{};
    for (final page in pages) {
      final gradeMatch = RegExp(
        'الصف\\s*($_gradePattern)(?:\\s+الابتدائي)?|'
        '($_gradePattern)(?:\\s+الابتدائي)?\\s*الصف',
      ).firstMatch(page);
      final classMatch = RegExp(
        r'الفصل\s*([0-9]{1,2})|([0-9]{1,2})\s*الفصل',
      ).firstMatch(page);
      if (gradeMatch == null || classMatch == null) continue;
      final grade = _normalizeGrade(
        gradeMatch.group(1) ?? gradeMatch.group(2)!,
      );
      final schoolClass = classMatch.group(1) ?? classMatch.group(2)!;

      for (final match in _studentDataRecord.allMatches(page)) {
        final nationalId = match.group(1)!;
        final name = match.group(3)!.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (!seenNationalIds.add(nationalId)) continue;
        rows.add(<String>[name, nationalId, grade, schoolClass]);
      }
    }
    return rows;
  }

  static List<List<String>> _parseOfficialRegistryPages(List<String> pages) {
    final rows = <List<String>>[];
    final seenNationalIds = <String>{};
    for (final page in pages) {
      var blockStart = 0;
      for (final endMatch in _registryRecordEnd.allMatches(page)) {
        final block = page.substring(blockStart, endMatch.end);
        blockStart = endMatch.end;
        final parsed = _parseOfficialRegistryBlock(block);
        if (parsed == null) continue;
        final (name, nationalId, grade, schoolClass) = parsed;
        if (!seenNationalIds.add(nationalId)) continue;
        rows.add(<String>[name, nationalId, grade, schoolClass]);
      }
    }
    return rows;
  }

  static (String, String, String, String)? _parseOfficialRegistryBlock(
    String block,
  ) {
    final idMatches = RegExp(r'[0-9]{10}').allMatches(block).toList();
    if (idMatches.length < 2) return null;
    final gradeMatch = RegExp(
      '($_gradePattern)\\s*منتظم|منتظم\\s*($_gradePattern)',
    ).firstMatch(block);
    final classMatch = RegExp(
      r'العام\s*([0-9]{1,2})|([0-9]{1,2})\s*العام',
    ).firstMatch(block);
    if (gradeMatch == null || classMatch == null) return null;

    var nationalId = idMatches.last.group(0)!;
    final englishIdMatch = _englishNationalId.firstMatch(block);
    if (englishIdMatch != null) nationalId = englishIdMatch.group(1)!;

    final markerIndex = block.indexOf('44AD');
    // Records with a 44AD academic number start at that marker. Official
    // records with a numeric academic number may be emitted in visual column
    // order, placing the Arabic name before either 10-digit number; in that
    // case the whole block belongs to this student and must be retained.
    var nameSource = markerIndex >= 0 ? block.substring(markerIndex) : block;
    final primaryStageIndex = nameSource.indexOf('بتدائي');
    if (primaryStageIndex >= 0) {
      final stageLineStart = nameSource.lastIndexOf('\n', primaryStageIndex);
      nameSource = nameSource.substring(
        0,
        stageLineStart >= 0 ? stageLineStart : primaryStageIndex,
      );
    }
    nameSource = nameSource
        .replaceAll(RegExp(r'العام\s*[0-9]{1,2}|[0-9]{1,2}\s*العام'), ' ')
        .replaceAll(RegExp(r'[A-Za-z0-9.\-:/]+'), ' ');
    for (final marker in <String>[
      'منتظم',
      'الأول',
      'الثاني',
      'الثالث',
      'الرابع',
      'الخامس',
      'السادس',
    ]) {
      nameSource = nameSource.replaceAll(marker, ' ');
    }
    final name = RegExp(r'[\u0621-\u064a]+')
        .allMatches(nameSource)
        .map((match) => match.group(0)!)
        .where((word) => !const {'في', 'من', 'قبل', 'الدراسة'}.contains(word))
        .join(' ')
        .trim();
    if (name.length < 4) return null;
    return (
      name,
      nationalId,
      _normalizeGrade(gradeMatch.group(1) ?? gradeMatch.group(2)!),
      classMatch.group(1) ?? classMatch.group(2)!,
    );
  }

  static String _normalizeGrade(String value) => value
      .trim()
      .replaceFirst(
        RegExp(r'\s+(?:الابتدائي|الإبتدائي|الابتدائية|الإبتدائية)$'),
        '',
      )
      .trim();

  static bool _looksLikeMalformedArialCidText(String value) {
    var glyphs = 0;
    for (final rune in value.runes) {
      if ((rune >= 897 && rune <= 1020) || rune == 3020) glyphs++;
      if (glyphs >= 24) break;
    }
    if (glyphs < 12) return false;
    if (value.contains("Student's Name") ||
        value.contains('Nationality') ||
        value.contains('Date of birth')) {
      return true;
    }
    return glyphs >= 24 &&
        (value.contains('ReportID:') ||
            RegExp(r'[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}').hasMatch(value));
  }

  static bool _looksLikeRosterHeader(List<String> row) {
    final headers = row.map(_normalizeWorkbookHeader).toSet();
    final hasNationalId =
        headers.contains('رقمرخصةالاقامة') ||
        headers.contains('رقمرخصةالإقامة') ||
        headers.contains('السجلالمدني') ||
        headers.contains('رقمالهوية');
    return headers.contains('اسمالطالب') &&
        headers.contains('حالةالقيد') &&
        hasNationalId;
  }

  static int? _findColumn(List<String> row, Set<String> aliases) {
    for (var index = 0; index < row.length; index++) {
      if (aliases.contains(_normalizeWorkbookHeader(row[index]))) return index;
    }
    return null;
  }

  static String _normalizeWorkbookHeader(String value) => value
      .trim()
      .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll(RegExp(r'[^0-9ء-ي]'), '');

  static String _gradeFromWorkbookRows(Iterable<List<String>> rows) {
    for (final row in rows) {
      for (final cell in row) {
        final match = RegExp(
          '^($_gradePattern)(?:\\s+(?:الابتدائي|الإبتدائي|الابتدائية|الإبتدائية))?\$',
        ).firstMatch(cell.trim());
        if (match != null) return match.group(1)!;
      }
    }
    return '';
  }

  static String _stageFromWorkbookRows(Iterable<List<String>> rows) {
    for (final row in rows) {
      for (final cell in row) {
        if (RegExp(
          r'(?:الابتدائي|الإبتدائي|الابتدائية|الإبتدائية)',
        ).hasMatch(cell)) {
          return 'المرحلة الابتدائية';
        }
      }
    }
    return '';
  }

  static String _classFromWorkbookRows(Iterable<List<String>> rows) {
    for (final row in rows) {
      for (var index = 0; index < row.length; index++) {
        if (_normalizeWorkbookHeader(row[index]) != 'الفصل') continue;
        for (var valueIndex = index - 1; valueIndex >= 0; valueIndex--) {
          final value = row[valueIndex].trim();
          if (RegExp(r'^[0-9]{1,2}$').hasMatch(value)) return value;
        }
      }
    }
    return '';
  }

  static String _cell(List<String> row, int column) =>
      column < row.length ? row[column].trim() : '';

  static bool _containsArabicCidGlyph(String value) => value.runes.any(
    (rune) =>
        (rune >= 897 && rune <= 1020) ||
        rune == 751 ||
        rune == 752 ||
        rune == 3020,
  );

  static String _decodeReversedArabicCidLine(String value) {
    return value.split(' ').map(_decodeReversedArabicCidSegment).join(' ');
  }

  static String _decodeReversedArabicCidSegment(String value) {
    if (!_containsArabicCidGlyph(value)) return value;
    final visual = StringBuffer();
    for (final rune in value.runes) {
      if (rune == 3) {
        visual.write(' ');
      } else if (rune == 16) {
        visual.write('-');
      } else if (rune == 751) {
        visual.write('ء');
      } else if (rune == 752) {
        // Arabic tatweel has no semantic value in names and labels.
        continue;
      } else if (rune == 3020) {
        // The entire visual line is reversed below.
        visual.write('هللا');
      } else {
        visual.write(_arabicCidReplacement(rune) ?? String.fromCharCode(rune));
      }
    }
    return String.fromCharCodes(visual.toString().runes.toList().reversed);
  }

  static String? _arabicCidReplacement(int rune) {
    for (final range in _arabicCidRanges) {
      if (rune >= range.$1 && rune <= range.$2) return range.$3;
    }
    return null;
  }

  static String _normalizeArabicPresentationForms(String value) {
    final result = StringBuffer();
    for (final rune in value.runes) {
      if (rune == 0xFDF2) {
        result.write('الله');
        continue;
      }
      if (rune == 0xFBAB || rune == 0xFBAD || rune == 0x06BE) {
        result.write('ه');
        continue;
      }
      if (rune == 0xFBFE || rune == 0xFBFF || rune == 0x06CC) {
        result.write('ي');
        continue;
      }
      final replacement = _presentationFormReplacement(rune);
      result.write(replacement ?? String.fromCharCode(rune));
    }
    return result.toString();
  }

  static String? _presentationFormReplacement(int rune) {
    for (final range in _presentationFormRanges) {
      if (rune >= range.$1 && rune <= range.$2) return range.$3;
    }
    return null;
  }

  static String _normalizeDigits(String value) {
    final result = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        result.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        result.writeCharCode(0x30 + rune - 0x06F0);
      } else {
        result.writeCharCode(rune);
      }
    }
    return result.toString();
  }

  static const List<(int, int, String)> _arabicCidRanges = [
    (897, 898, 'آ'),
    (899, 900, 'أ'),
    (901, 902, 'ؤ'),
    (903, 904, 'إ'),
    (905, 908, 'ئ'),
    (909, 910, 'ا'),
    (911, 914, 'ب'),
    (915, 916, 'ة'),
    (917, 920, 'ت'),
    (921, 924, 'ث'),
    (925, 928, 'ج'),
    (929, 932, 'ح'),
    (933, 936, 'خ'),
    (937, 938, 'د'),
    (939, 940, 'ذ'),
    (941, 942, 'ر'),
    (943, 944, 'ز'),
    (945, 948, 'س'),
    (949, 952, 'ش'),
    (953, 956, 'ص'),
    (957, 960, 'ض'),
    (961, 964, 'ط'),
    (965, 968, 'ظ'),
    (969, 972, 'ع'),
    (973, 976, 'غ'),
    (977, 980, 'ف'),
    (981, 984, 'ق'),
    (985, 988, 'ك'),
    (989, 992, 'ل'),
    (993, 996, 'م'),
    (997, 1000, 'ن'),
    (1001, 1004, 'ه'),
    (1005, 1006, 'و'),
    (1007, 1008, 'ى'),
    (1009, 1012, 'ي'),
    // Ligatures are written in visual order because the line is reversed.
    (1013, 1014, 'آل'),
    (1015, 1016, 'أل'),
    (1017, 1018, 'إل'),
    (1019, 1020, 'ال'),
  ];

  static const List<(int, int, String)> _presentationFormRanges = [
    (0xFE80, 0xFE80, 'ء'),
    (0xFE81, 0xFE82, 'آ'),
    (0xFE83, 0xFE84, 'أ'),
    (0xFE85, 0xFE86, 'ؤ'),
    (0xFE87, 0xFE88, 'إ'),
    (0xFE89, 0xFE8C, 'ئ'),
    (0xFE8D, 0xFE8E, 'ا'),
    (0xFE8F, 0xFE92, 'ب'),
    (0xFE93, 0xFE94, 'ة'),
    (0xFE95, 0xFE98, 'ت'),
    (0xFE99, 0xFE9C, 'ث'),
    (0xFE9D, 0xFEA0, 'ج'),
    (0xFEA1, 0xFEA4, 'ح'),
    (0xFEA5, 0xFEA8, 'خ'),
    (0xFEA9, 0xFEAA, 'د'),
    (0xFEAB, 0xFEAC, 'ذ'),
    (0xFEAD, 0xFEAE, 'ر'),
    (0xFEAF, 0xFEB0, 'ز'),
    (0xFEB1, 0xFEB4, 'س'),
    (0xFEB5, 0xFEB8, 'ش'),
    (0xFEB9, 0xFEBC, 'ص'),
    (0xFEBD, 0xFEC0, 'ض'),
    (0xFEC1, 0xFEC4, 'ط'),
    (0xFEC5, 0xFEC8, 'ظ'),
    (0xFEC9, 0xFECC, 'ع'),
    (0xFECD, 0xFED0, 'غ'),
    (0xFED1, 0xFED4, 'ف'),
    (0xFED5, 0xFED8, 'ق'),
    (0xFED9, 0xFEDC, 'ك'),
    (0xFEDD, 0xFEE0, 'ل'),
    (0xFEE1, 0xFEE4, 'م'),
    (0xFEE5, 0xFEE8, 'ن'),
    (0xFEE9, 0xFEEC, 'ه'),
    (0xFEED, 0xFEEE, 'و'),
    (0xFEEF, 0xFEF0, 'ى'),
    (0xFEF1, 0xFEF4, 'ي'),
    (0xFEF5, 0xFEF6, 'لآ'),
    (0xFEF7, 0xFEF8, 'لأ'),
    (0xFEF9, 0xFEFA, 'لإ'),
    (0xFEFB, 0xFEFC, 'لا'),
  ];
}
