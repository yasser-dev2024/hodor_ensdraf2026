import 'package:hijri_core/hijri_core.dart';
import 'package:intl/intl.dart';

class SchoolDayFormatter {
  const SchoolDayFormatter._();

  static const _hijriMonths = <String>[
    'محرم',
    'صفر',
    'ربيع الأول',
    'ربيع الآخر',
    'جمادى الأولى',
    'جمادى الآخرة',
    'رجب',
    'شعبان',
    'رمضان',
    'شوال',
    'ذو القعدة',
    'ذو الحجة',
  ];

  static DateTime dateOnly(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static String key([DateTime? date]) =>
      DateFormat('yyyy-MM-dd').format(dateOnly(date ?? DateTime.now()));

  static DateTime parseKey(String value) => dateOnly(DateTime.parse(value));

  static String gregorianLong(DateTime date) =>
      DateFormat('EEEE، d MMMM yyyy', 'ar').format(dateOnly(date));

  static String hijriLong(DateTime date) {
    final local = dateOnly(date);
    final hijri = toHijri(DateTime.utc(local.year, local.month, local.day));
    if (hijri == null || hijri.hm < 1 || hijri.hm > _hijriMonths.length) {
      return 'التاريخ الهجري غير متاح';
    }
    return '${hijri.hd} ${_hijriMonths[hijri.hm - 1]} ${hijri.hy} هـ';
  }

  static String dualLong(DateTime date) =>
      '${gregorianLong(date)}\n${hijriLong(date)}';

  static String dualInline(DateTime date) =>
      '${gregorianLong(date)} — ${hijriLong(date)}';
}
