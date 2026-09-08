class SaudiPhoneFormatter {
  const SaudiPhoneFormatter._();

  static String normalize(String value) {
    var digits = value
        .replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '')
        .replaceAllMapped(
          RegExp('[٠-٩]'),
          (match) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(match.group(0)!)}',
        )
        .replaceAllMapped(
          RegExp('[۰-۹]'),
          (match) => '${'۰۱۲۳۴۵۶۷۸۹'.indexOf(match.group(0)!)}',
        );
    if (digits.startsWith('00966')) digits = digits.substring(2);
    if (RegExp(r'^05\d{8}$').hasMatch(digits)) {
      digits = '966${digits.substring(1)}';
    } else if (RegExp(r'^5\d{8}$').hasMatch(digits)) {
      digits = '966$digits';
    }
    return digits;
  }

  static bool isValidSaudiMobile(String value) =>
      RegExp(r'^9665\d{8}$').hasMatch(normalize(value));
}
