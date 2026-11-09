class CapitalGroup {
  const CapitalGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description,
  });

  final int id;
  final String name;
  final String? description;
  final DateTime createdAt;
}
