import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/buddies/data/repositories/buddy_repository.dart';
import 'package:submersion/features/buddies/domain/entities/buddy.dart'
    as domain;
import 'package:submersion/features/buddies/domain/entities/buddy_role_credential.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late BuddyRepository repository;
  late AppDatabase db;

  setUp(() async {
    db = await setUpTestDatabase();
    await db.customStatement('PRAGMA foreign_keys = ON');
    repository = BuddyRepository();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  domain.Buddy buddyFixture(String name) {
    final now = DateTime.now();
    return domain.Buddy(id: '', name: name, createdAt: now, updatedAt: now);
  }

  group('BuddyRepository role CRUD', () {
    test('setRolesForBuddy inserts and getRolesForBuddy reads back', () async {
      final buddy = await repository.createBuddy(buddyFixture('Alice'));
      final now = DateTime.now();
      await repository.setRolesForBuddy(buddy.id, [
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.instructor,
          credentialNumber: '12345',
          agency: CertificationAgency.padi,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final roles = await repository.getRolesForBuddy(buddy.id);
      expect(roles, hasLength(1));
      expect(roles.single.role, BuddyRole.instructor);
      expect(roles.single.credentialNumber, '12345');
      expect(roles.single.agency, CertificationAgency.padi);
    });

    test('setRolesForBuddy dedupes by role (last wins)', () async {
      final buddy = await repository.createBuddy(buddyFixture('Bob'));
      final now = DateTime.now();
      await repository.setRolesForBuddy(buddy.id, [
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.instructor,
          credentialNumber: '111',
          createdAt: now,
          updatedAt: now,
        ),
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.instructor,
          credentialNumber: '222',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final roles = await repository.getRolesForBuddy(buddy.id);
      expect(roles, hasLength(1));
      expect(roles.single.credentialNumber, '222');
    });

    test('setRolesForBuddy preserves the row id of a kept role', () async {
      final buddy = await repository.createBuddy(buddyFixture('Carol'));
      final now = DateTime.now();
      await repository.setRolesForBuddy(buddy.id, [
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.instructor,
          credentialNumber: '111',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final firstRoles = await repository.getRolesForBuddy(buddy.id);
      final originalId = firstRoles.single.id;

      await repository.setRolesForBuddy(buddy.id, [
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.instructor,
          credentialNumber: '999',
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final secondRoles = await repository.getRolesForBuddy(buddy.id);
      expect(secondRoles, hasLength(1));
      expect(secondRoles.single.id, originalId);
      expect(secondRoles.single.credentialNumber, '999');
    });

    test('setRolesForBuddy removes roles omitted from the new list', () async {
      final buddy = await repository.createBuddy(buddyFixture('Dave'));
      final now = DateTime.now();
      await repository.setRolesForBuddy(buddy.id, [
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.instructor,
          createdAt: now,
          updatedAt: now,
        ),
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.diveMaster,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      await repository.setRolesForBuddy(buddy.id, [
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.instructor,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final roles = await repository.getRolesForBuddy(buddy.id);
      expect(roles, hasLength(1));
      expect(roles.single.role, BuddyRole.instructor);
    });

    test('deleting a buddy cascades its buddy_roles rows (FK ON)', () async {
      final buddy = await repository.createBuddy(buddyFixture('Erin'));
      final now = DateTime.now();
      await repository.setRolesForBuddy(buddy.id, [
        BuddyRoleCredential(
          id: '',
          buddyId: buddy.id,
          role: BuddyRole.instructor,
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      await repository.deleteBuddy(buddy.id);

      final countResult = await db
          .customSelect('SELECT COUNT(*) as count FROM buddy_roles')
          .getSingle();
      expect(countResult.data['count'], 0);
    });

    test('getAllRoles returns a buddyId-keyed map', () async {
      final credentialed = await repository.createBuddy(buddyFixture('Frank'));
      final plain = await repository.createBuddy(buddyFixture('Gina'));
      final now = DateTime.now();
      await repository.setRolesForBuddy(credentialed.id, [
        BuddyRoleCredential(
          id: '',
          buddyId: credentialed.id,
          role: BuddyRole.diveGuide,
          createdAt: now,
          updatedAt: now,
        ),
      ]);

      final map = await repository.getAllRoles();

      expect(map.containsKey(credentialed.id), isTrue);
      expect(map[credentialed.id], hasLength(1));
      expect(map.containsKey(plain.id), isFalse);
    });
  });
}
