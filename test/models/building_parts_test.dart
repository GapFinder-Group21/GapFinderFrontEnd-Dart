import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';

void main() {
  test('the part number is not shown', () {
    expect(Building.baseName('Bobo 1'), 'Bobo');
    expect(Building.baseName('RGD (Cívico) 2'), 'RGD (Cívico)');
    expect(Building.baseName('ML'), 'ML');
    expect(Building.baseName('City U'), 'City U');
  });

  test('parts of one building are listed once, with the first part', () {
    final merged = Building.mergeParts([
      Building(id: 1, name: 'SD'),
      Building(id: 5, name: 'Aulas 1'),
      Building(id: 6, name: 'Aulas 2'),
      Building(id: 7, name: 'Bobo 1'),
      Building(id: 8, name: 'Bobo 2'),
      Building(id: 9, name: 'C'),
    ]);

    expect(merged.map((b) => b.displayName), ['SD', 'Aulas', 'Bobo', 'C']);
    expect(merged.map((b) => b.id), [1, 5, 7, 9]);
  });
}
