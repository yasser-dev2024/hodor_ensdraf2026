class SchoolGrade {
  const SchoolGrade({
    required this.id,
    required this.name,
    required this.sortOrder,
  });
  final String id;
  final String name;
  final int sortOrder;
}

class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.gradeId,
    required this.gradeName,
    required this.name,
    required this.sortOrder,
  });
  final String id;
  final String gradeId;
  final String gradeName;
  final String name;
  final int sortOrder;
  String get label => '$gradeName / $name';
}
