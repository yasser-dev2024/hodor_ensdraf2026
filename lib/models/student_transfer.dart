class StudentTransfer {
  const StudentTransfer({
    required this.id,
    required this.studentId,
    required this.oldClassLabel,
    required this.newClassLabel,
    required this.transferredAt,
    required this.transferredBy,
  });

  final String id;
  final String studentId;
  final String oldClassLabel;
  final String newClassLabel;
  final DateTime transferredAt;
  final String transferredBy;
}
