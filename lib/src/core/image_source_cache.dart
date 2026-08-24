import 'image_source.dart';
import 'image_source_resolver.dart';

/// Memoizes [ImageSourceResolver.resolve].
///
/// Resolution is pure string and URI work, but it used to run inside
/// `ImageLoader.build`, so every ancestor rebuild re-parsed the same path.
/// Results are keyed by the raw source string and evicted least-recently-used.
final class ImageSourceCache {
  const ImageSourceCache._();

  static const int maxEntries = 512;
  static const ImageSourceResolver _resolver = ImageSourceResolver();

  // LinkedHashMap iteration follows insertion order, so `keys.first` is always
  // the least recently used entry once hits are re-inserted at the tail.
  static final Map<String, ResolvedImageSource> _entries =
      <String, ResolvedImageSource>{};
  static final ResolvedImageSource _empty = _resolver.resolve(null);

  static ResolvedImageSource resolve(String? source) {
    if (source == null || source.isEmpty) return _empty;

    final hit = _entries.remove(source);
    if (hit != null) {
      _entries[source] = hit;
      return hit;
    }

    final resolved = _resolver.resolve(source);
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[source] = resolved;
    return resolved;
  }

  static void clear() => _entries.clear();
}
