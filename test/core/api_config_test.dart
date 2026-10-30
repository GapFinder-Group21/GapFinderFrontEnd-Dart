import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/network/api_config.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/avatar_widget.dart';

void main() {
  group('ApiConfig', () {
    test('the address is https and never a LAN or local address', () {
      final base = ApiConfig.baseUrl;

      expect(base.startsWith('https://'), isTrue);
      expect(base, isNot(contains('192.168')));
      expect(base, isNot(contains('localhost')));
      expect(base, isNot(contains('10.0.2.2')));
    });

    test('without --dart-define the app uses the placeholder', () {
      expect(ApiConfig.baseUrl, ApiConfig.defaultBaseUrl);
    });

    test('avatar paths from the back are built from ApiConfig.baseUrl', () {
      expect(AvatarWidget.resolveUrl('/uploads/foto.jpg'), startsWith(ApiConfig.baseUrl));
    });

    test('complete avatar urls are kept as they are', () {
      expect(AvatarWidget.resolveUrl('https://example.org/a.png'), 'https://example.org/a.png');
    });
  });
}
