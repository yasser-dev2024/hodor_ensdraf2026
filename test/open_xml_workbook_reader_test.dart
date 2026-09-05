import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_student_attendance/services/open_xml_workbook_reader.dart';

void main() {
  test('reads inline and shared strings while preserving empty columns', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'xl/sharedStrings.xml',
          '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<si><t>السجل المدني</t></si>'
              '<si><t>1234567890</t></si>'
              '</sst>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet1.xml',
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<sheetData>'
              '<row r="1"><c r="A1" t="inlineStr"><is><t>اسم الطالب</t></is></c>'
              '<c r="C1" t="s"><v>0</v></c></row>'
              '<row r="2"><c r="A2" t="inlineStr"><is><t>طالب تجريبي</t></is></c>'
              '<c r="C2" t="s"><v>1</v></c></row>'
              '</sheetData>'
              '</worksheet>',
        ),
      );
    final encoded = Uint8List.fromList(ZipEncoder().encode(archive)!);

    final sheets = OpenXmlWorkbookReader.read(encoded);

    expect(sheets, hasLength(1));
    expect(sheets.single.rows[0], ['اسم الطالب', '', 'السجل المدني']);
    expect(sheets.single.rows[1], ['طالب تجريبي', '', '1234567890']);
  });
}
