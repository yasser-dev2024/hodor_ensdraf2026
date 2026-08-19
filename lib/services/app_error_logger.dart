import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppErrorLogger {
  AppErrorLogger._();

  static const _maxEntries = 100;

  static Future<void> record(
    Object error,
    StackTrace stack, {
    required String category,
  }) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File(p.join(directory.path, 'safe_error_log.jsonl'));
      final previous = await file.exists()
          ? await file.readAsLines()
          : <String>[];
      final stackFrames = stack
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(8)
          .map(_sanitizeStackFrame)
          .toList();
      final entry = jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'category': category,
        'error_type': error.runtimeType.toString(),
        'stack': stackFrames,
      });
      final retained = [...previous, entry];
      final start = retained.length > _maxEntries
          ? retained.length - _maxEntries
          : 0;
      await file.writeAsString(
        '${retained.sublist(start).join('\n')}\n',
        flush: true,
      );
    } catch (_) {
      // لا نسمح لفشل سجل التشخيص بالتأثير في تشغيل التطبيق أو بياناته.
    }
  }

  static String _sanitizeStackFrame(String value) => value
      .replaceAll(RegExp(r'file:\/\/\/[^\s)]+'), 'local-source')
      .replaceAll(RegExp(r'\b\d{6,}\b'), '[number]')
      .trim();
}
