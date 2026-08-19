enum UserRole {
  manager('المدير'),
  attendanceOfficer('موظف الغياب'),
  studentAffairs('وكيل شؤون الطلاب');

  const UserRole(this.label);
  final String label;

  bool get canScan => this != UserRole.studentAffairs;
  bool get canEditAttendance =>
      this == UserRole.manager || this == UserRole.attendanceOfficer;
  bool get canManage => this == UserRole.manager;
  bool get canViewReports => true;
  bool get canViewSensitiveStudentData =>
      this == UserRole.manager || this == UserRole.studentAffairs;
}

class AppUser {
  const AppUser({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final UserRole role;
}
