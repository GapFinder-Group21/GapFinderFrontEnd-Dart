import 'dart:isolate';
import 'package:flutter/foundation.dart';

// Letters with a mark and the letter without it, to compare names without accents
const _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n',
};

// Name in lower case and without accents, to search and compare ("Música" -> "musica")
String normalizeInterestName(String name) {
  final lower = name.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

// Top-level function (not a method) so that Isolate.run can run it in another isolate: an isolate
// does not share memory, so it only receives and returns simple data (maps of numbers and text).
// Each map is {id, name}. It returns {id, name, searchName} without duplicates (same normalized
// name) and sorted alphabetically by that name.
List<Map<String, dynamic>> processInterests(List<Map<String, dynamic>> raw) {
  debugPrint('processInterests runs in isolate: ${Isolate.current.debugName}');

  final seen = <String>{};
  final result = <Map<String, dynamic>>[];

  for (final item in raw) {
    final name = (item['name'] as String?) ?? '';
    final searchName = normalizeInterestName(name);
    if (searchName.isEmpty || !seen.add(searchName)) continue;
    result.add({'id': item['id'], 'name': name, 'searchName': searchName});
  }

  result.sort((a, b) {
    final byName = (a['searchName'] as String).compareTo(b['searchName'] as String);
    return byName != 0 ? byName : (a['id'] as int).compareTo(b['id'] as int);
  });
  return result;
}
