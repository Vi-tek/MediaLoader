import 'package:flutter_test/flutter_test.dart';
import 'package:media_loader/media_loader.dart';

void main() {
  const resolver = ImageSourceResolver();
  final source = resolver.resolve('https://example.com/private/avatar?token=secret');

  test('cache ID is stable across header insertion order', () {
    final first = ImageCacheIdentity.cacheId(
      source,
      headers: const <String, String>{'B': '2', 'A': '1'},
    );
    final second = ImageCacheIdentity.cacheId(
      source,
      headers: const <String, String>{'A': '1', 'B': '2'},
    );

    expect(first, second);
  });

  test('header values and explicit keys change the identity', () {
    final first = ImageCacheIdentity.cacheId(
      source,
      headers: const <String, String>{'Authorization': 'Bearer one'},
      explicitCacheKey: 'user-one',
    );
    final second = ImageCacheIdentity.cacheId(
      source,
      headers: const <String, String>{'Authorization': 'Bearer two'},
      explicitCacheKey: 'user-two',
    );

    expect(first, isNot(second));
  });

  test('cache ID does not expose URL query data or authorization values', () {
    final id = ImageCacheIdentity.cacheId(
      source,
      headers: const <String, String>{'Authorization': 'Bearer private-token'},
    );

    expect(id, isNot(contains('secret')));
    expect(id, isNot(contains('private-token')));
    expect(id, hasLength(64));
  });
}
