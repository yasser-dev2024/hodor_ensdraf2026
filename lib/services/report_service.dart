import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/attendance_record.dart';
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
  }) async {
    final font = await _arabicFont();
    final document = pw.Document(
      title: 'بطاقات باركود الطلاب',
      author: schoolName,
    );
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
                    width: 260,
                    height: 150,
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
                          width: 100,
                          height: 100,
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
