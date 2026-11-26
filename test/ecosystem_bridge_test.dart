import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mab_focus/services/ecosystem_bridge_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mab_ecosystem_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('EcosystemBridgeService generates valid mab_ecosystem_sync.json matching Compass spec', () async {
    final service = EcosystemBridgeService.instance;
    final syncFile = File(p.join(tempDir.path, 'mab_ecosystem_sync.json'));

    // تست حالت در حال اجرا
    final payload = {
      'active_pomodoro': {
        'is_running': true,
        'project_id': 'proj-123',
        'project_name': 'پروژه تست کامپس',
        'task_title': 'تسک تست',
        'remaining_seconds': 1200,
        'realm': 'work',
        'status': 'running',
      },
      'last_synced_at': DateTime.now().toIso8601String(),
    };

    await syncFile.writeAsString(jsonEncode(payload));
    expect(await syncFile.exists(), isTrue);

    final readContent = await syncFile.readAsString();
    final decoded = jsonDecode(readContent) as Map<String, dynamic>;

    expect(decoded['active_pomodoro']['is_running'], isTrue);
    expect(decoded['active_pomodoro']['project_id'], 'proj-123');
    expect(decoded['active_pomodoro']['project_name'], 'پروژه تست کامپس');
    expect(decoded['active_pomodoro']['task_title'], 'تسک تست');
    expect(decoded['active_pomodoro']['remaining_seconds'], 1200);
    expect(decoded['last_synced_at'], isNotNull);

    // تست فیلتر نوشتن داخلی جهت جلوگیری از لوپ
    service.notifyInternalWrite();
    expect(service.isRecentInternalWrite, isTrue);
  });
}
