import 'user.dart';
import 'open_table.dart';
import '../utils/date_formatter_util.dart';

class Group {
  final int id;
  final String name;
  final DateTime createdAt;

  // Relaciones opcionales (presentes cuando viene la respuesta completa)
  final User? creator;
  final List members;
  final List openTables;

  Group({
    required this.id,
    required this.name,
    required this.createdAt,
    this.creator,
    this.members = const [],
    this.openTables = const [],
  });

  factory Group.fromJson(Map json) {
    return Group(
      id: json['id'],
      name: json['name'] ?? '',
      createdAt: DateFormatterUtil.parseDateTime(json['createdAt']),
      creator: json['creator'] != null ? User.fromJson(json['creator']) : null,
      members: (json['members'] as List?)
          ?.map((m) => User.fromJson(m))
          .toList() ??
          [],
      openTables: (json['openTables'] as List?)
          ?.map((t) => OpenTable.fromJson(t))
          .toList() ??
          [],
    );
  }

  Map toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': DateFormatterUtil.formatDateTime(createdAt),
      'creator': creator?.toJson(),
      'members': members.map((m) => m.toJson()).toList(),
      'openTables': openTables.map((t) => t.toJson()).toList(),
    };
  }
}