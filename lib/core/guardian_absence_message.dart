class GuardianAbsenceMessage {
  const GuardianAbsenceMessage._();

  static const settingKey = 'guardian_absence_whatsapp_template';

  static const defaultTemplate =
      'السلام عليكم،\n'
      'ابنكم {student} غائب لهذا اليوم.\n'
      'التاريخ: {date}\n'
      'تنبيه: نأمل تزويد المدرسة بعذر رسمي للغياب.\n'
      'المدرسة: {school}';

  static String render({
    required String? template,
    required String studentName,
    required String date,
    required String schoolName,
  }) {
    final selected = template?.trim().isNotEmpty == true
        ? template!.trim()
        : defaultTemplate;
    return selected
        .replaceAll('{student}', studentName.trim())
        .replaceAll('{date}', date.trim())
        .replaceAll('{school}', schoolName.trim());
  }
}
