import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'image_source.dart';

final class ImageCacheIdentity {
  const ImageCacheIdentity._();

  static String cacheId(
    ResolvedImageSource source, {
    Map<String, String>? headers,
    String? explicitCacheKey,
  }) {
    final input = <String>[
      'source=${source.canonicalIdentity}',
      'headers=${headersIdentity(headers)}',
      'callerKey=${explicitCacheKey ?? ''}',
    ].join('\n');
    return sha256.convert(utf8.encode(input)).toString();
  }

  static String headersIdentity(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return 'none';
    final entries = headers.entries
        .map((entry) => MapEntry(entry.key.toLowerCase().trim(), entry.value))
        .toList()
      ..sort((a, b) {
        final keyCompare = a.key.compareTo(b.key);
        if (keyCompare != 0) return keyCompare;
        return a.value.compareTo(b.value);
      });
    final canonical = entries
        .map((entry) => '${entry.key.length}:${entry.key}=${entry.value.length}:${entry.value}')
        .join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static String bytesGeneration(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }
}
