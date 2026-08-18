import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageStorageService {
  Future<String> saveStudentPhoto({
    required String studentId,
    required String sourcePath,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'student_photos'));
    await directory.create(recursive: true);
    final extension = p.extension(sourcePath).toLowerCase();
    final safeExtension = {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
        ? extension
        : '.jpg';
    final target = File(p.join(directory.path, '$studentId$safeExtension'));
    if (await target.exists()) await target.delete();
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  Future<void> deletePhoto(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
