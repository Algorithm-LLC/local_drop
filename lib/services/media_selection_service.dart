import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class MediaSelectionService {
  MediaSelectionService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  bool get shouldUseSystemPicker =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<List<String>> pickPhotos() async {
    if (!shouldUseSystemPicker) {
      return const <String>[];
    }
    final files = await _imagePicker.pickMultiImage();
    return files
        .map((item) => item.path.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> pickVideos() async {
    if (!shouldUseSystemPicker) {
      return const <String>[];
    }
    final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (file == null || file.path.trim().isEmpty) {
      return const <String>[];
    }
    return <String>[file.path];
  }
}
