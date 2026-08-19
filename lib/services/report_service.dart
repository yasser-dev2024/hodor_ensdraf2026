import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_record.dart';
import '../models/period_report.dart';
import '../models/student.dart';

class ReportService {
  Future<pw.Font> _arabicFont() async {
    final data = await rootBundle.load('assets/fonts/NotoSansArabic.ttf');
    return pw.Font.ttf(data);
  }

  Future<File> generateDailyPdf({
    required String date,
    required DailySummary summary,
    required List<AttendanceRecord> records,
    required String schoolName,
  }) async {
    final font = await _arabicFont();
    final document = pw.Document(
      title: 'تقرير الحضور $date',
      author: schoolName,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColor.fromInt(0xFF176B9D)),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(schoolName, style: pw.TextStyle(fontSize: 12)),
              pw.Text(
                'تقرير الحضور الصباحي',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 16),
          pw.Text('التاريخ: $date', style: const pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _statBox(
                'إجمالي الطلاب',
                summary.totalStudents,
                const PdfColor.fromInt(0xFF153A5B),
              ),
              _statBox(
                'الحاضرون',
                summary.present,
                const PdfColor.fromInt(0xFF168A5B),
              ),
              _statBox(
                'الغائبون',
                summary.absent,
                const PdfColor.fromInt(0xFFD54848),
              ),
              _statBox(
                'المستأذنون',
                summary.excused,
                const PdfColor.fromInt(0xFFE09B26),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'نسبة الحضور: ${(summary.attendanceRate * 100).toStringAsFixed(1)}٪',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: const ['الحالة', 'الوقت', 'الصف / الفصل', 'اسم الطالب'],
            data: records
                .map(
                  (record) => [
                    record.status.label,
                    DateFormat(
                      'hh:mm a',
                      'ar',
                    ).format(record.recordedAt.toLocal()),
                    record.classLabel,
                    record.studentName,
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF176B9D),
            ),
            cellAlignment: pw.Alignment.centerRight,
            cellStyle: const pw.TextStyle(fontSize: 10),
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF1F6F9),
            ),
          ),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
      ),
    );
    return _saveTemp('attendance_$date.pdf', await document.save());
  }

  Future<File> generateBarcodeCards(
    List<Student> students, {
    String schoolName = '',
    String cardSize = 'standard',
  }) async {
    final font = await _arabicFont();
    final document = pw.Document(
      title: 'بطاقات باركود الطلاب',
      author: schoolName,
    );
    final cardWidth = switch (cardSize) {
      'compact' => 170.0,
      'large' => 350.0,
      _ => 260.0,
    };
    final cardHeight = switch (cardSize) {
      'compact' => 112.0,
      'large' => 190.0,
      _ => 150.0,
    };
    final qrSize = switch (cardSize) {
      'compact' => 72.0,
      'large' => 135.0,
      _ => 100.0,
    };
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        margin: const pw.EdgeInsets.all(18),
        build: (context) => [
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: students
                .map(
                  (student) => pw.Container(
                    width: cardWidth,
                    height: cardHeight,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: const PdfColor.fromInt(0xFF9CB3C2),
                      ),
                      borderRadius: pw.BorderRadius.circular(7),
                    ),
                    child: pw.Row(
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: student.barcodeToken,
                          width: qrSize,
                          height: qrSize,
                        ),
                        pw.SizedBox(width: 10),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              if (schoolName.isNotEmpty)
                                pw.Text(
                                  schoolName,
                                  style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfColors.grey700,
                                  ),
                                ),
                              pw.SizedBox(height: 6),
                              pw.Text(
                                student.name,
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textAlign: pw.TextAlign.right,
                              ),
                              pw.SizedBox(height: 5),
                              pw.Text(
                                student.classLabel.isEmpty
                                    ? 'غير محدد'
                                    : student.classLabel,
                                style: const pw.TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
    return _saveTemp('student_qr_cards.pdf', await document.save());
  }

  Future<File> generatePeriodPdf({
    required PeriodReport report,
    required String schoolName,
    required String title,
    AttendanceAnalytics? analytics,
  }) async {
    final font = await _arabicFont();
    final document = pw.Document(title: title, author: schoolName);
    final date = DateFormat('yyyy-MM-dd');
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(schoolName, style: const pw.TextStyle(fontSize: 10)),
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          pw.Text(
            'الفترة: ${date.format(report.startDate)} إلى ${date.format(report.endDate)} — النطاق: ${report.scope.label}',
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              _statBox(
                'الطلاب',
                report.totalStudents,
                const PdfColor.fromInt(0xFF153A5B),
              ),
              _statBox(
                'أيام الدراسة',
                report.schoolDays,
                const PdfColor.fromInt(0xFF176B9D),
              ),
              _statBox(
                'الحضور',
                report.present,
                const PdfColor.fromInt(0xFF168A5B),
              ),
              _statBox(
                'الغياب',
                report.absent,
                const PdfColor.fromInt(0xFFD54848),
              ),
              _statBox(
                'الاستئذان',
                report.excused,
                const PdfColor.fromInt(0xFFE09B26),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'نسبة الانضباط العامة: ${(report.attendanceRate * 100).toStringAsFixed(1)}٪',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (analytics != null) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'لوحة الأفضل والأكثر — المدرسة كاملة',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: const ['النتيجة', 'المؤشر'],
              data: [
                [
                  analytics.mostDisciplined.isEmpty
                      ? 'لا توجد بيانات'
                      : '${analytics.mostDisciplined.first.studentName} — ${(analytics.mostDisciplined.first.disciplineRate * 100).toStringAsFixed(1)}٪',
                  'أفضل طالب انضباطًا',
                ],
                [
                  analytics.mostAbsent.isEmpty
                      ? 'لا توجد حالات'
                      : '${analytics.mostAbsent.first.studentName} — ${analytics.mostAbsent.first.absent}',
                  'أكثر طالب غيابًا',
                ],
                [
                  analytics.mostExcused.isEmpty
                      ? 'لا توجد حالات'
                      : '${analytics.mostExcused.first.studentName} — ${analytics.mostExcused.first.excused}',
                  'أكثر طالب استئذانًا',
                ],
                [
                  analytics.bestClass == null
                      ? 'لا توجد بيانات'
                      : '${analytics.bestClass!.label} — ${(analytics.bestClass!.attendanceRate * 100).toStringAsFixed(1)}٪',
                  'أفضل فصل انضباطًا',
                ],
                [
                  analytics.mostAbsentClass == null
                      ? 'لا توجد بيانات'
                      : '${analytics.mostAbsentClass!.label} — ${analytics.mostAbsentClass!.absent}',
                  'أكثر فصل غيابًا',
                ],
              ],
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF6C4AB6),
              ),
              cellAlignment: pw.Alignment.centerRight,
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'النسبة',
              'استئذان',
              'غياب',
              'حضور',
              'الأيام المتوقعة',
              'الصف / الفصل',
              'الطالب',
            ],
            data: report.students
                .map(
                  (student) => [
                    '${(student.disciplineRate * 100).toStringAsFixed(1)}٪',
                    '${student.excused}',
                    '${student.absent}',
                    '${student.present}',
                    '${student.expectedDays}',
                    student.classLabel,
                    student.studentName,
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF176B9D),
            ),
            cellAlignment: pw.Alignment.centerRight,
            cellStyle: const pw.TextStyle(fontSize: 9),
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF1F6F9),
            ),
          ),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
      ),
    );
    return _saveTemp(
      'period_${date.format(report.startDate)}_${date.format(report.endDate)}.pdf',
      await document.save(),
    );
  }

  Future<File> exportPeriodExcel({
    required PeriodReport report,
    AttendanceAnalytics? analytics,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['التقرير'];
    sheet.isRTL = true;
    sheet.appendRow(
      [
        'اسم الطالب',
        'الصف / الفصل',
        'أيام الدراسة المتوقعة',
        'الحضور',
        'الغياب',
        'الاستئذان',
        'نسبة الانضباط',
      ].map(TextCellValue.new).toList(),
    );
    for (final student in report.students) {
      sheet.appendRow([
        TextCellValue(student.studentName),
        TextCellValue(student.classLabel),
        IntCellValue(student.expectedDays),
        IntCellValue(student.present),
        IntCellValue(student.absent),
        IntCellValue(student.excused),
        DoubleCellValue(student.disciplineRate * 100),
      ]);
    }
    if (analytics != null) {
      final analyticsSheet = excel['الإحصاءات'];
      analyticsSheet.isRTL = true;
      analyticsSheet.appendRow(
        ['المؤشر', 'النتيجة'].map(TextCellValue.new).toList(),
      );
      analyticsSheet.appendRow([
        TextCellValue('نسبة الحضور العامة'),
        DoubleCellValue(analytics.report.attendanceRate * 100),
      ]);
      analyticsSheet.appendRow([
        TextCellValue('أفضل طالب انضباطًا'),
        TextCellValue(
          analytics.mostDisciplined.isEmpty
              ? 'لا توجد بيانات'
              : '${analytics.mostDisciplined.first.studentName} — ${(analytics.mostDisciplined.first.disciplineRate * 100).toStringAsFixed(1)}٪',
        ),
      ]);
      analyticsSheet.appendRow([
        TextCellValue('أكثر طالب غيابًا'),
        TextCellValue(
          analytics.mostAbsent.isEmpty
              ? 'لا توجد حالات'
              : '${analytics.mostAbsent.first.studentName} — ${analytics.mostAbsent.first.absent}',
        ),
      ]);
      analyticsSheet.appendRow([
        TextCellValue('أكثر طالب استئذانًا'),
        TextCellValue(
          analytics.mostExcused.isEmpty
              ? 'لا توجد حالات'
              : '${analytics.mostExcused.first.studentName} — ${analytics.mostExcused.first.excused}',
        ),
      ]);
      analyticsSheet.appendRow([
        TextCellValue('أفضل فصل انضباطًا'),
        TextCellValue(
          analytics.bestClass == null
              ? 'لا توجد بيانات'
              : '${analytics.bestClass!.label} — ${(analytics.bestClass!.attendanceRate * 100).toStringAsFixed(1)}٪',
        ),
      ]);
      analyticsSheet.appendRow([
        TextCellValue('أكثر فصل غيابًا'),
        TextCellValue(
          analytics.mostAbsentClass == null
              ? 'لا توجد بيانات'
              : '${analytics.mostAbsentClass!.label} — ${analytics.mostAbsentClass!.absent}',
        ),
      ]);
    }
    if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('تعذر إنشاء ملف Excel.');
    return _saveTemp(
      'period_${DateFormat('yyyy-MM-dd').format(report.startDate)}_${DateFormat('yyyy-MM-dd').format(report.endDate)}.xlsx',
      bytes,
    );
  }

  Future<File> exportDailyExcel({
    required String date,
    required List<AttendanceRecord> records,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['تقرير $date'];
    sheet.isRTL = true;
    sheet.appendRow(
      [
        'اسم الطالب',
        'الصف / الفصل',
        'الحالة',
        'التاريخ',
        'الوقت',
      ].map(TextCellValue.new).toList(),
    );
    for (final record in records) {
      sheet.appendRow(
        [
          record.studentName,
          record.classLabel,
          record.status.label,
          record.attendanceDate,
          DateFormat('HH:mm').format(record.recordedAt.toLocal()),
        ].map(TextCellValue.new).toList(),
      );
    }
    if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
    final bytes = excel.save();
    if (bytes == null) throw StateError('تعذر إنشاء ملف Excel.');
    return _saveTemp('attendance_$date.xlsx', bytes);
  }

  pw.Widget _statBox(String label, int value, PdfColor color) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
      padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            '$value',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            label,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
          ),
        ],
      ),
    ),
  );

  Future<File> _saveTemp(String fileName, List<int> bytes) async {
    final root = await getTemporaryDirectory();
    final reportDirectory = Directory(
      p.join(root.path, 'morning_attendance_reports'),
    );
    await reportDirectory.create(recursive: true);
    final file = File(p.join(reportDirectory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
