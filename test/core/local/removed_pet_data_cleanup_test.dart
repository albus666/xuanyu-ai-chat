import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/local/removed_pet_data_cleanup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('xuanyu-pet-cleanup-');
    SharedPreferences.setMockInitialValues({
      'pet_insight_profiles_v1': 'old pet profiles',
      'unrelated_archive': 'keep',
    });
  });

  tearDown(() async {
    await documents.delete(recursive: true);
  });

  test('清掉宠物档案和照片副本，保留其它数据且可重复执行', () async {
    final photos = Directory('${documents.path}/pet_insight_photos');
    await photos.create();
    await File('${photos.path}/pet.jpg').writeAsString('photo');
    final unrelated = File('${documents.path}/archive.jpg');
    await unrelated.writeAsString('keep');
    final preferences = await SharedPreferences.getInstance();

    expect(
        await RemovedPetDataCleanup.run(preferences,
            documentsDirectory: documents),
        isTrue);
    expect(preferences.containsKey('pet_insight_profiles_v1'), isFalse);
    expect(await photos.exists(), isFalse);
    expect(preferences.getString('unrelated_archive'), 'keep');
    expect(await unrelated.readAsString(), 'keep');
    expect(
        await RemovedPetDataCleanup.run(preferences,
            documentsDirectory: documents),
        isTrue);
  });

  test('不跟随照片目录或目录内部的链接删除外部原图', () async {
    final album = Directory('${documents.path}/album');
    await album.create();
    final original = File('${album.path}/original.jpg');
    await original.writeAsString('original');
    final path = '${documents.path}/pet_insight_photos';
    final preferences = await SharedPreferences.getInstance();
    await Link(path).create(album.path);
    expect(
        await RemovedPetDataCleanup.run(preferences,
            documentsDirectory: documents),
        isTrue);
    expect(await original.readAsString(), 'original');
    await Directory(path).create();
    await Link('$path/external').create(album.path);
    expect(
        await RemovedPetDataCleanup.run(preferences,
            documentsDirectory: documents),
        isTrue);
    expect(await original.readAsString(), 'original');
  });
}
