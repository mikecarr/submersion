import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/sync/changeset_log/sync_manifest.dart';
import 'package:submersion/core/services/sync/changeset_log/tombstone_horizon.dart';

void main() {
  const now = 1000000000000;
  const month = 30 * 24 * 60 * 60 * 1000;

  SyncManifest peer(
    String id, {
    int ageMillis = 0,
    Map<String, String> applied = const {},
  }) => SyncManifest(
    deviceId: id,
    provider: 'fake',
    headSeq: 1,
    updatedAt: now - ageMillis,
    appliedPeerHlc: applied,
  );

  test('no live peers: GC unbounded', () {
    final d = TombstoneHorizon.compute(
      selfDeviceId: 'self',
      peerManifests: const [],
      retiredPeerIds: const {},
      nowMillis: now,
    );
    expect(d.allowed, isTrue);
    expect(d.upToHlc, isNull);
  });

  test('live peer without an ack entry blocks GC', () {
    final d = TombstoneHorizon.compute(
      selfDeviceId: 'self',
      peerManifests: [peer('p1')],
      retiredPeerIds: const {},
      nowMillis: now,
    );
    expect(d.allowed, isFalse);
  });

  test('horizon is the minimum ack across live peers', () {
    final d = TombstoneHorizon.compute(
      selfDeviceId: 'self',
      peerManifests: [
        peer('p1', applied: {'self': '00000000000020:000000:x'}),
        peer('p2', applied: {'self': '00000000000010:000000:x'}),
      ],
      retiredPeerIds: const {},
      nowMillis: now,
    );
    expect(d.allowed, isTrue);
    expect(d.upToHlc, '00000000000010:000000:x');
  });

  test('stale (13-month) and retired peers do not count', () {
    final d = TombstoneHorizon.compute(
      selfDeviceId: 'self',
      peerManifests: [
        peer('stale', ageMillis: 13 * month), // beyond retirement period
        peer('gone', applied: const {}), // retired below
        peer('live', applied: {'self': '00000000000030:000000:x'}),
      ],
      retiredPeerIds: const {'gone'},
      nowMillis: now,
    );
    expect(d.allowed, isTrue);
    expect(d.upToHlc, '00000000000030:000000:x');
  });

  test('own manifest is ignored', () {
    final d = TombstoneHorizon.compute(
      selfDeviceId: 'self',
      peerManifests: [peer('self')],
      retiredPeerIds: const {},
      nowMillis: now,
    );
    expect(d.allowed, isTrue);
    expect(d.upToHlc, isNull);
  });
}
