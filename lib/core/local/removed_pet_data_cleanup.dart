import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Removes only storage owned by the retired pet feature.
/// Safe to repeat on startup so failed deletions are retried next launch.
class RemovedPetDataCleanup {
  RemovedPetDataCleanup._();

  static Future<bool> run(
    SharedPreferences preferences, {
    Directory? documentsDirectory,
  }) async {
    var completed = true;
    try {
      if (preferences.containsKey('pet_insight_profiles_v1')) {
        completed = await preferences.remove('pet_insight_profiles_v1');
      }
    } catch (_) {
      completed = false;
    }
    try {
      final documents =
          documentsDirectory ?? await getApplicationDocumentsDirectory();
      final photoPath = '${documents.path}/pet_insight_photos';
      final type = await FileSystemEntity.type(photoPath, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(photoPath).delete(recursive: true);
      } else if (type == FileSystemEntityType.link) {
        // Never follow a link outside the feature's own photo folder.
        await Link(photoPath).delete();
      } else if (type == FileSystemEntityType.file) {
        await File(photoPath).delete();
      }
    } catch (_) {
      completed = false;
    }
    return completed;
  }
}
