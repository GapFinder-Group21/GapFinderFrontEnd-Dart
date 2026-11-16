import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/current_location_view_model.dart';

// Real points of the saved catalog (center and radius in meters)
final _buildings = [
  Building(id: 1, name: 'ML', latitude: 4.60277854608654, longitude: -74.0648662947269, radiusMeters: 37.4),
  Building(id: 7, name: 'Bobo 1', latitude: 4.60122604850284, longitude: -74.0658814905777, radiusMeters: 16.4),
  Building(id: 8, name: 'Bobo 2', latitude: 4.6011739139905, longitude: -74.065599188094, radiusMeters: 18.6),
];

void main() {
  test('without internet the building is found on the phone, without the part number', () {
    final name = CurrentLocationViewModel.nameForPosition(_buildings, 4.6011739139905, -74.065599188094);
    expect(name, 'Bobo');
  });

  test('a point inside ML gives ML', () {
    expect(CurrentLocationViewModel.nameForPosition(_buildings, 4.60277854608654, -74.0648662947269), 'ML');
  });

  test('a point far from every building is outside campus', () {
    expect(CurrentLocationViewModel.nameForPosition(_buildings, 4.65, -74.10), CurrentLocationViewModel.outsideCampus);
  });
}
