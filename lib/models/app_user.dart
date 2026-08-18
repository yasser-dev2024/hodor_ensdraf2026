enum UserRole {
  manager('المدير'),
  attendanceOfficer('مسؤول الحضور'),
  studentAffairs('وكيل شؤون الطلاب');

  const UserRole(this.label);
  final String label;

  bool get canScan => this != UserRole.studentAffairs;
  bool get canEditAttendance => this == UserRole.manager;
  bool get canManage => this == UserRole.manager;
  bool get canViewReports => true;
}

class AppUser {
  const AppUser({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final UserRole role;
}
