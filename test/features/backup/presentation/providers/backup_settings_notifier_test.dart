import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/features/backup/data/repositories/backup_preferences.dart';
import 'package:submersion/features/backup/presentation/providers/backup_providers.dart';

void main() {
  late BackupSettingsNotifier notifier;
  late BackupPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = BackupPreferences(await SharedPreferences.getInstance());
    notifier = BackupSettingsNotifier(prefs);
  });

  group('cloud backup and custom location are mutually exclusive', () {
    test('cloud backup starts disabled', () {
      expect(notifier.state.cloudBackupEnabled, isFalse);
    });

    test('enabling cloud backup clears a custom backup location', () async {
      await notifier.setBackupLocation('/custom/path');
      await notifier.setCloudBackupEnabled(true);

      expect(notifier.state.cloudBackupEnabled, isTrue);
      expect(notifier.state.backupLocation, isNull);
      expect(prefs.getSettings().backupLocation, isNull);
    });

    test('choosing a custom location turns cloud backup off', () async {
      await notifier.setCloudBackupEnabled(true);
      await notifier.setBackupLocation('/custom/path');

      expect(notifier.state.cloudBackupEnabled, isFalse);
      expect(notifier.state.backupLocation, '/custom/path');
      expect(prefs.getSettings().cloudBackupEnabled, isFalse);
    });

    test(
      'clearing the location back to default keeps cloud backup state',
      () async {
        await notifier.setBackupLocation('/custom/path');
        await notifier.setBackupLocation(null);

        expect(notifier.state.backupLocation, isNull);
        expect(notifier.state.cloudBackupEnabled, isFalse);
      },
    );
  });

  group('disableCloudBackup (cloud sync sign-out hook)', () {
    test('turns cloud backup off and resets the location', () async {
      await notifier.setCloudBackupEnabled(true);

      await notifier.disableCloudBackup();

      expect(notifier.state.cloudBackupEnabled, isFalse);
      expect(notifier.state.backupLocation, isNull);
      expect(prefs.getSettings().cloudBackupEnabled, isFalse);
    });

    test('leaves an unrelated custom location untouched', () async {
      await notifier.setBackupLocation('/custom/path');

      await notifier.disableCloudBackup();

      expect(notifier.state.cloudBackupEnabled, isFalse);
      expect(notifier.state.backupLocation, '/custom/path');
    });
  });
}
