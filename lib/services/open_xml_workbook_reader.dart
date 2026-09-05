import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/import_models.dart';

/// Lightweight fallback for valid OOXML workbooks rejected by the main Excel
/// package because of non-standard style metadata in some Ministry exports.
class OpenXmlWorkbookReader {
  const OpenXmlWorkbookReader._();

  static List<ImportSheetData> read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final sharedStrings = _readSharedStrings(archive);
    final worksheetFiles =
        archive
            .where(
              (file) => RegExp(
                r'^xl/worksheets/sheet[0-9]+\.xml$',
              ).hasMatch(file.name),
            )
            .toList()
          ..sort((left, right) {
            final leftNumber = _sheetNumber(left.name);
            final rightNumber = _sheetNumber(right.name);
            return leftNumber.compareTo(rightNumber);
          });

    return [
      for (final file in worksheetFiles)
        ImportSheetData(
          name: 'ورقة ${_sheetNumber(file.name)}',
          rows: _readRows(file, sharedStrings),
        ),
    ];
  }

  static List<String> _readSharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return const [];
    final document = XmlDocument.parse(_text(file));
    return document
        .findAllElements('si')
        .map(
          (item) =>
              item.findAllElements('t').map((value) => value.innerText).join(),
        )
        .toList();
  }

  static List<List<String>> _readRows(
    ArchiveFile file,
    List<String> sharedStrings,
  ) {
    final document = XmlDocument.parse(_text(file));
    final rows = <List<String>>[];
    for (final rowElement in document.findAllElements('row')) {
      final values = <int, String>{};
      var maximumColumn = -1;
      for (final cell in rowElement.findElements('c')) {
        final reference = cell.getAttribute('r') ?? '';
        final column = _columnIndex(reference);
        if (column < 0) continue;
        maximumColumn = column > maximumColumn ? column : maximumColumn;
        final type = cell.getAttribute('t');
        String value;
        if (type == 'inlineStr') {
          value = cell
              .findAllElements('t')
              .map((text) => text.innerText)
              .join();
        } else {
          value = cell.findElements('v').firstOrNull?.innerText ?? '';
          if (type == 's') {
            final index = int.tryParse(value);
            value = index != null && index >= 0 && index < sharedStrings.length
                ? sharedStrings[index]
                : '';
          }
        }
        values[column] = value.trim().replaceAll(RegExp(r'\.0$'), '');
      }
      rows.add(
        maximumColumn < 0
            ? <String>[]
            : [
                for (var column = 0; column <= maximumColumn; column++)
                  values[column] ?? '',
              ],
      );
    }
    return rows;
  }

  static int _sheetNumber(String name) =>
      int.parse(RegExp(r'sheet([0-9]+)\.xml$').firstMatch(name)!.group(1)!);

  static int _columnIndex(String reference) {
    final letters = RegExp(r'^[A-Za-z]+').firstMatch(reference)?.group(0);
    if (letters == null) return -1;
    var value = 0;
    for (final rune in letters.toUpperCase().runes) {
      value = value * 26 + rune - 64;
    }
    return value - 1;
  }

  static String _text(ArchiveFile file) =>
      utf8.decode((file.content as List<int>).toList(growable: false));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
