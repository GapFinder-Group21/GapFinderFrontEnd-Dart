import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// The logos are drawn at 110, 80 and 40 px: a bigger file only wastes memory and APK size
void main() {
  // Width and height are stored in the IHDR chunk of the PNG (bytes 16 to 23)
  (int, int) pngSize(String path) {
    final bytes = File(path).readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    return (data.getUint32(16), data.getUint32(20));
  }

  test('logo_gap_finder.png is not bigger than 3x the size it is drawn (110 px)', () {
    final (w, h) = pngSize('assets/images/logo_gap_finder.png');
    expect(w, lessThanOrEqualTo(330));
    expect(h, lessThanOrEqualTo(330));
  });

  test('logo_sin_fondo.png is not bigger than 3x its biggest size (80 px)', () {
    final (w, h) = pngSize('assets/images/logo_sin_fondo.png');
    expect(w, lessThanOrEqualTo(240));
    expect(h, lessThanOrEqualTo(240));
  });

  test('the logos stay square', () {
    for (final name in ['logo_gap_finder.png', 'logo_sin_fondo.png']) {
      final (w, h) = pngSize('assets/images/$name');
      expect(w, h);
    }
  });
}
