import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class StudentPhoto extends StatelessWidget {
  const StudentPhoto({
    required this.path,
    this.size = 64,
    this.heroTag,
    this.highlighted = false,
    super.key,
  });
  final String? path;
  final double size;
  final String? heroTag;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final exists = file?.existsSync() ?? false;
    final photo = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: exists
            ? null
            : const LinearGradient(
                colors: [Color(0xFFDCECF4), Color(0xFFC9E7E1)],
              ),
        border: Border.all(
          color: highlighted ? AppColors.sky : Colors.white,
          width: highlighted ? 5 : 3,
        ),
        boxShadow: [
          BoxShadow(
            color: (highlighted ? AppColors.blue : Colors.black).withValues(
              alpha: .18,
            ),
            blurRadius: highlighted ? 22 : 8,
            offset: const Offset(0, 5),
          ),
        ],
        image: exists
            ? DecorationImage(image: FileImage(file!), fit: BoxFit.cover)
            : null,
      ),
      child: exists
          ? null
          : Icon(Icons.person_rounded, size: size * .58, color: AppColors.blue),
    );
    return heroTag == null ? photo : Hero(tag: heroTag!, child: photo);
  }
}
