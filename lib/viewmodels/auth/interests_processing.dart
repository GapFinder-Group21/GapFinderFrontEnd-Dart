import 'dart:isolate';
import 'package:flutter/foundation.dart';

// Letters with a mark and the letter without it, to compare names without accents
const _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', 'ē': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ī': 'i',
  'ñ': 'n',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o', 'ō': 'o',
  'š': 's', 'ś': 's',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ū': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ž': 'z', 'ź': 'z',
};

// A combining mark (U+0300 to U+036F): it comes after its letter when the text is decomposed (NFD),
// for example "u" + U+0301 is "ú". It is dropped, so both forms of the same word are equal.
bool _isCombiningMark(int rune) => rune >= 0x0300 && rune <= 0x036F;

// Name in lower case and without accents, to search and compare ("Música" -> "musica").
// It works for the precomposed letters (ú) and for the decomposed ones (u + combining mark).
String normalizeInterestName(String name) {
  final lower = name.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    if (_isCombiningMark(rune)) continue;
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

// Top-level function (not a method) so that Isolate.run can run it in another isolate: an isolate
// does not share memory, so it only receives and returns simple data (maps of numbers and text).
// Each map is {id, name}. It returns {id, name, searchName, duplicateIds} without duplicates (same
// normalized name) and sorted alphabetically by that name. The first id is kept; duplicateIds are the ids
// that were dropped for that name, so a selection that has one of them can be moved to the kept one.
List<Map<String, dynamic>> processInterests(List<Map<String, dynamic>> raw) {
  debugPrint('processInterests runs in isolate: ${Isolate.current.debugName}');

  final kept = <String, Map<String, dynamic>>{};
  final result = <Map<String, dynamic>>[];

  for (final item in raw) {
    final name = (item['name'] as String?) ?? '';
    final searchName = normalizeInterestName(name);
    if (searchName.isEmpty) continue;

    final first = kept[searchName];
    if (first != null) {
      (first['duplicateIds'] as List<int>).add(item['id'] as int);
      continue;
    }
    final entry = <String, dynamic>{'id': item['id'], 'name': name, 'searchName': searchName, 'duplicateIds': <int>[]};
    kept[searchName] = entry;
    result.add(entry);
  }

  result.sort((a, b) {
    final byName = (a['searchName'] as String).compareTo(b['searchName'] as String);
    return byName != 0 ? byName : (a['id'] as int).compareTo(b['id'] as int);
  });
  return result;
}
