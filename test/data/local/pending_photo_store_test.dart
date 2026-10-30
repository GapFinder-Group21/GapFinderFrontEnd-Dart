import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/pending_photo_store.dart';

void main() {
  group('J-17: the pending photo has a maximum age', () {
    final now = DateTime(2026, 10, 30, 12);
    String pathAt(DateTime time) => 'pending_photos/${time.millisecondsSinceEpoch}.jpg';

    test('a photo from a few hours ago is still offered', () {
      expect(PendingPhotoStore.isExpired(pathAt(now.subtract(const Duration(hours: 3))), now), isFalse);
    });

    test('a photo older than 24 hours is not offered to a new table', () {
      expect(PendingPhotoStore.isExpired(pathAt(now.subtract(const Duration(hours: 25))), now), isTrue);
    });

    test('a path without a time is kept', () {
      expect(PendingPhotoStore.isExpired('pending_photos/photo.jpg', now), isFalse);
    });
  });
}
