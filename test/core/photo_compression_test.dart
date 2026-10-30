import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:gapfinderfrontend_dart/core/utils/photo_compression.dart';

void main() {
  // A noisy 2000x1500 photo (noise does not compress well, like a real photo)
  Uint8List bigPhoto() {
    final random = Random(1);
    final image = img.Image(width: 2000, height: 1500);
    for (final pixel in image) {
      pixel.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
    }
    return img.encodeJpg(image, quality: 100);
  }

  test('compressPhoto in an isolate: width at most 1080, same proportion and lighter', () async {
    final original = bigPhoto();

    final compressed = await Isolate.run(() => compressPhoto(original));

    final result = img.decodeImage(compressed)!;
    expect(result.width, 1080);
    expect(result.height, 810); // 2000x1500 keeps the 4:3 proportion
    expect(compressed.length, lessThan(original.length));
    // ignore: avoid_print
    print('before: ${original.length ~/ 1024} KB, after: ${compressed.length ~/ 1024} KB');
  });

  test('a photo narrower than 1080 keeps its size and bytes that are not an image are returned as they are', () {
    final small = img.encodeJpg(img.Image(width: 400, height: 300), quality: 90);
    expect(img.decodeImage(compressPhoto(small))!.width, 400);

    final notAnImage = Uint8List.fromList([1, 2, 3]);
    expect(compressPhoto(notAnImage), notAnImage);
  });

  test('J-22: the compressed photo has no EXIF data (no GPS), even when it is small', () {
    final photo = img.Image(width: 400, height: 300);
    photo.exif.imageIfd['Make'] = img.IfdValueAscii('PhoneMaker');
    photo.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    final withExif = img.encodeJpg(photo, quality: 90);
    expect(img.decodeJpgExif(withExif)!.isEmpty, isFalse);

    final compressed = compressPhoto(withExif);

    final exif = img.decodeJpgExif(compressed);
    expect(exif == null || exif.isEmpty, isTrue);
  });
}
