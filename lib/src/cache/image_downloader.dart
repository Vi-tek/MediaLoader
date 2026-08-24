import '../core/image_source.dart';

import 'image_download.dart';

abstract interface class ImageDownloader {
  Future<DownloadedImage> download(
    ResolvedImageSource source,
    ImageDownloadRequest request,
  );

  void close();
}
