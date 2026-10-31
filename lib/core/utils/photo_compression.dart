import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// Biggest width of a photo after compressing it
const photoMaxWidth = 1080;
const photoJpegQuality = 80;

// Makes a photo lighter: width at most 1080 px (the proportion is kept) and JPEG quality 80.
// The EXIF data (GPS place, phone model, date) is removed, so the photo never says where it was taken.
// It is a top-level function so that Isolate.run can run it in another isolate:
// decoding and encoding a photo is heavy work that would freeze the screen in the main isolate.
// If the bytes are not an image they are returned as they are.
Uint8List compressPhoto(Uint8List bytes) {
  debugPrint('compressPhoto runs in isolate: ${Isolate.current.debugName}');

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  // Phones save the rotation in the metadata: apply it before resizing
  var photo = img.bakeOrientation(decoded);
  if (photo.width > photoMaxWidth) {
    photo = img.copyResize(photo, width: photoMaxWidth); // the height follows the proportion
  }
  photo.exif = img.ExifData();
  return img.encodeJpg(photo, quality: photoJpegQuality);
}
