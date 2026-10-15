import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuanyu/core/constants/app_constants.dart';
import 'package:xuanyu/core/local/paipan_record_store.dart';
import 'package:xuanyu/core/network/api_client.dart';
import 'package:xuanyu/features/fortune/paipan/models/paipan_record.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);

  final Directory directory;
  Future<void> Function()? beforeResolve;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    await beforeResolve?.call();
    return directory.path;
  }
}

PaipanRecord _record(String id) => PaipanRecord(
      id: id,
      displayName: '案例$id',
      createdAt: DateTime(2026, 9, 28),
      birthDateTime: DateTime(2000, 1, 1, 12),
      isFemale: false,
      calendarTypeIndex: 0,
      summary: '庚辰 戊子 戊午 戊午',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PathProviderPlatform previousPaths;
  late _Paths paths;

  File recordsFor(int userId) =>
      File('${directory.path}/paipan_records_user_$userId.json');

  setUp(() async {
    SharedPreferences.setMockInitialValues({AppConstants.keyUserId: 77});
    directory =
        await Directory.systemTemp.createTemp('paipan-save-reliability-');
    previousPaths = PathProviderPlatform.instance;
    paths = _Paths(directory);
    PathProviderPlatform.instance = paths;
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await directory.delete(recursive: true);
  });

  test('损坏档案不能被新增案例覆盖', () async {
    final file = recordsFor(77);
    const damaged = '[{"id":"旧档案"';
    await file.writeAsString(damaged);

    await expectLater(
      PaipanRecordStore.save(_record('new'), expectedUserId: 77),
      throwsFormatException,
    );

    expect(await file.readAsString(), damaged);
  });

  test('并发保存两个案例均保留且临时目录清理完成', () async {
    await Future.wait([
      PaipanRecordStore.save(_record('first'), expectedUserId: 77),
      PaipanRecordStore.save(_record('second'), expectedUserId: 77),
    ]);

    final records = await PaipanRecordStore.loadAll();
    expect(records.map((record) => record.id),
        unorderedEquals(['first', 'second']));
    expect(
      await directory
          .list()
          .any((entity) => entity.path.contains('.paipan-save-')),
      isFalse,
    );
  });

  test('起始账号与目标账号不符时不写入任一账号', () async {
    await expectLater(
      PaipanRecordStore.save(_record('wrong'), expectedUserId: 88),
      throwsStateError,
    );

    expect(await recordsFor(77).exists(), isFalse);
    expect(await recordsFor(88).exists(), isFalse);
  });

  test('保存等待目录期间切号不会覆盖任何账号的档案', () async {
    final oldContents = jsonEncode([_record('old').toJson()]);
    final otherContents = jsonEncode([_record('other').toJson()]);
    await recordsFor(77).writeAsString(oldContents);
    await recordsFor(88).writeAsString(otherContents);
    final entered = Completer<void>();
    final resume = Completer<void>();
    paths.beforeResolve = () async {
      entered.complete();
      await resume.future;
    };

    final rejected = expectLater(
      PaipanRecordStore.save(_record('late'), expectedUserId: 77),
      throwsStateError,
    );
    await entered.future;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyUserId, 88);
    resume.complete();
    await rejected;

    expect(await recordsFor(77).readAsString(), oldContents);
    expect(await recordsFor(88).readAsString(), otherContents);
  });

  test('辅助上下文写入失败不误报主档保存失败', () async {
    // 用同名普通文件阻止建立缓存目录，模拟不可写的上下文缓存。
    final obstruction = File('${directory.path}/paipan_contexts_user_77');
    await obstruction.writeAsString('保留此文件');

    await PaipanRecordStore.save(_record('saved'), expectedUserId: 77);

    expect((await PaipanRecordStore.loadAll()).single.id, 'saved');
    expect(await obstruction.readAsString(), '保留此文件');
  });

  test('一次保存失败不会阻塞后续保存队列', () async {
    final file = recordsFor(77);
    await file.writeAsString('not-json');
    await expectLater(
      PaipanRecordStore.save(_record('failed'), expectedUserId: 77),
      throwsFormatException,
    );
    await file.writeAsString('[]');

    await PaipanRecordStore.save(_record('recovered'), expectedUserId: 77);

    expect((await PaipanRecordStore.loadAll()).single.id, 'recovered');
  });

  test('新增案例仍迁移并保留旧版本档案', () async {
    final legacy = File('${directory.path}/paipan_records.json');
    await legacy.writeAsString(jsonEncode([_record('legacy').toJson()]));

    await PaipanRecordStore.save(_record('new'), expectedUserId: 77);

    expect(
      (await PaipanRecordStore.loadAll()).map((record) => record.id),
      unorderedEquals(['legacy', 'new']),
    );
  });

  Future<PaipanRecord> note(String id) => PaipanRecordStore.saveCase(
        recordId: id,
        fallback: _record(id),
        caseTitle: '案例$id',
        reasoningNotes: '判断$id',
        commentary: '反馈$id',
        expectedUserId: 77,
      );

  test('损坏文件保存笔记失败且原文完整保留', () async {
    const damaged = '[{"id":"旧笔记未读完"';
    await recordsFor(77).writeAsString(damaged);
    await expectLater(note('new'), throwsFormatException);
    expect(await recordsFor(77).readAsString(), damaged);
    expect(await File('${recordsFor(77).path}.backup').exists(), isFalse);
  });

  test('笔记保存成功保留上次有效原文备份', () async {
    final original = jsonEncode([_record('old').toJson()]);
    await recordsFor(77).writeAsString(original);
    await note('old');
    expect(
        await File('${recordsFor(77).path}.backup').readAsString(), original);
    expect((await PaipanRecordStore.loadAll()).single.reasoningNotes, '判断old');
  });

  test('保存笔记等待目录时切号，两份档案均不改变', () async {
    final old = jsonEncode([_record('old').toJson()]);
    final other = jsonEncode([_record('other').toJson()]);
    await recordsFor(77).writeAsString(old);
    await recordsFor(88).writeAsString(other);
    final entered = Completer<void>();
    final resume = Completer<void>();
    paths.beforeResolve = () async {
      entered.complete();
      await resume.future;
    };
    final rejected = expectLater(note('old'), throwsStateError);
    await entered.future;
    await (await SharedPreferences.getInstance())
        .setInt(AppConstants.keyUserId, 88);
    resume.complete();
    await rejected;
    expect(await recordsFor(77).readAsString(), old);
    expect(await recordsFor(88).readAsString(), other);
  });

  test('同账号退出重登也使旧保存失效', () async {
    final original = jsonEncode([_record('old').toJson()]);
    await recordsFor(77).writeAsString(original);
    final entered = Completer<void>();
    final resume = Completer<void>();
    paths.beforeResolve = () async {
      entered.complete();
      await resume.future;
    };
    final rejected = expectLater(note('old'), throwsStateError);
    await entered.future;
    setupApiClientToken(null);
    setupApiClientToken('synthetic-relogin');
    resume.complete();
    await rejected;
    expect(await recordsFor(77).readAsString(), original);
    setupApiClientToken(null);
  });

  test('并发改笔记改名及新增均保留', () async {
    await PaipanRecordStore.save(_record('old'));
    await Future.wait([
      note('old'),
      PaipanRecordStore.updateDisplayName('old', '修改后的名字'),
      PaipanRecordStore.save(_record('second')),
    ]);
    final records = await PaipanRecordStore.loadAll();
    expect(records, hasLength(2));
    final updated = records.singleWhere((item) => item.id == 'old');
    expect(updated.displayName, '修改后的名字');
    expect(updated.reasoningNotes, '判断old');
  });

  test('删除与保存笔记串行执行不会复活被删除的其他档案', () async {
    await PaipanRecordStore.save(_record('old'));
    await PaipanRecordStore.save(_record('second'));
    await Future.wait([
      PaipanRecordStore.delete('second', expectedUserId: 77),
      note('old'),
    ]);
    expect((await PaipanRecordStore.loadAll()).single.id, 'old');
  });

  test('改名和修改身份不能覆盖损坏档案', () async {
    await recordsFor(77).writeAsString('damaged');
    await expectLater(PaipanRecordStore.updateDisplayName('old', '新名'),
        throwsFormatException);
    await expectLater(
        PaipanRecordStore.updateIdentity('old',
            displayName: '新名', relationship: 'friend'),
        throwsFormatException);
    expect(await recordsFor(77).readAsString(), 'damaged');
  });
}
