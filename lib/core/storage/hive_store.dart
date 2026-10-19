import 'package:hive_flutter/hive_flutter.dart';

// Key-value storage (Hive). Call init() once at start, then ask for the boxes you need.
class HiveStore {
  static final Map<String, Future<Box>> _boxes = {};

  static Future<void> init() => Hive.initFlutter();

  // Opens the box the first time and returns the same one afterwards
  static Future<Box> box(String name) {
    return _boxes[name] ??= Hive.openBox(name).catchError((Object e) {
      _boxes.remove(name); // let the next call try again
      throw e;
    });
  }
}
