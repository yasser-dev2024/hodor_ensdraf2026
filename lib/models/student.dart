class Student {
  const Student({
    required this.id,
    required this.name,
    required this.nationalId,
    required this.barcodeToken,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.stage = '',
    this.gradeId,
    this.gradeName,
    this.classId,
    this.className,
    this.academicNumber,
    this.photoPath,
    this.transferStatus,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String nationalId;
  final String barcodeToken;
  final String stage;
  final String? gradeId;
  final String? gradeName;
  final String? classId;
  final String? className;
  final String? academicNumber;
  final String? photoPath;
  final String status;
  final String? transferStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  String get classLabel => [
    gradeName,
    className,
  ].where((value) => value != null && value.trim().isNotEmpty).join(' / ');

  String get maskedNationalId {
    if (nationalId.length <= 4) return nationalId;
    return '${'•' * (nationalId.length - 4)}${nationalId.substring(nationalId.length - 4)}';
  }

  Student copyWith({
    String? name,
    String? nationalId,
    String? barcodeToken,
    String? stage,
    String? gradeId,
    String? gradeName,
    String? classId,
    String? className,
    String? academicNumber,
    String? photoPath,
    String? status,
    String? transferStatus,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Student(
      id: id,
      name: name ?? this.name,
      nationalId: nationalId ?? this.nationalId,
      barcodeToken: barcodeToken ?? this.barcodeToken,
      stage: stage ?? this.stage,
      gradeId: gradeId ?? this.gradeId,
      gradeName: gradeName ?? this.gradeName,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      academicNumber: academicNumber ?? this.academicNumber,
      photoPath: photoPath ?? this.photoPath,
      status: status ?? this.status,
      transferStatus: transferStatus ?? this.transferStatus,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
