import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/equipment/data/repositories/equipment_repository_impl.dart';
import 'package:submersion/features/equipment/data/repositories/service_schedule_repository.dart';
import 'package:submersion/features/equipment/domain/entities/equipment_item.dart';
import 'package:submersion/features/notifications/data/services/notification_scheduler.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EquipmentRepository equipmentRepo;
  late ServiceScheduleRepository scheduleRepo;

  setUp(() async {
    db = await setUpTestDatabase();
    equipmentRepo = EquipmentRepository();
    scheduleRepo = ServiceScheduleRepository();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  test(
    'scheduleAll records per-clock reminders only for future reminder days',
    () async {
      final now = DateTime.now();
      final tank = await equipmentRepo.createEquipment(
        const EquipmentItem(id: '', name: 'AL80', type: EquipmentType.tank),
      );

      // hydro due in 20 days, vip due in 25 days: the 30-day reminder for
      // both is already past, so only 7 and 14 day reminders schedule.
      final schedules = await scheduleRepo.getSchedulesForEquipment(tank.id);
      final hydro = schedules.firstWhere((s) => s.serviceKindId == 'hydro');
      await scheduleRepo.updateSchedule(
        hydro.copyWith(anchorDate: now.add(const Duration(days: 20 - 1825))),
      );
      final vip = schedules.firstWhere((s) => s.serviceKindId == 'vip');
      await scheduleRepo.updateSchedule(
        vip.copyWith(anchorDate: now.add(const Duration(days: 25 - 365))),
      );

      await NotificationScheduler().scheduleAll(settings: const AppSettings());

      final rows = await db.select(db.scheduledNotifications).get();
      expect(rows, hasLength(4)); // 2 clocks x (7d, 14d)
      expect(rows.map((r) => r.reminderDaysBefore).toSet(), {7, 14});
      expect(rows.every((r) => r.equipmentId == tank.id), isTrue);

      // Every row is tagged with its clock, and the two clocks' rows are
      // distinct (on device the platform id derives from the schedule id,
      // so hydro and VIP reminders cannot overwrite each other).
      final scheduleIds = rows.map((r) => r.scheduleId).toSet();
      expect(scheduleIds, {hydro.id, vip.id});

      // Re-running is idempotent (already-scheduled check is per clock).
      await NotificationScheduler().scheduleAll(settings: const AppSettings());
      expect(await db.select(db.scheduledNotifications).get(), hasLength(4));
    },
  );

  test('notifications disabled schedules nothing', () async {
    await equipmentRepo.createEquipment(
      const EquipmentItem(id: '', name: 'AL80', type: EquipmentType.tank),
    );
    await NotificationScheduler().scheduleAll(
      settings: const AppSettings(notificationsEnabled: false),
    );
    expect(await db.select(db.scheduledNotifications).get(), isEmpty);
  });
}
