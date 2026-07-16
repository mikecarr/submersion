import 'package:submersion/core/services/sync/changeset_log/sync_liveness.dart';
import 'package:submersion/core/services/sync/changeset_log/sync_manifest.dart';

/// Outcome of a fleet-acked GC computation. [upToHlc] == null with [allowed]
/// means no live peer constrains GC (single-device library): everything past
/// the safety floor may go.
class TombstoneGcDecision {
  const TombstoneGcDecision._(this.allowed, this.upToHlc);
  const TombstoneGcDecision.blocked() : this._(false, null);
  const TombstoneGcDecision.unbounded() : this._(true, null);
  const TombstoneGcDecision.upTo(String hlc) : this._(true, hlc);

  final bool allowed;
  final String? upToHlc;
}

/// Computes how far this device may garbage-collect its own tombstones: the
/// minimum HLC every LIVE peer's manifest acknowledges having applied from us.
/// A live peer with no ack entry (old-format manifest, or a device that has
/// not pulled our log yet) blocks GC entirely -- the safe default.
class TombstoneHorizon {
  static TombstoneGcDecision compute({
    required String selfDeviceId,
    required Iterable<SyncManifest> peerManifests,
    required Set<String> retiredPeerIds,
    required int nowMillis,
    int retirementPeriodMillis = SyncLiveness.retirementPeriodMillis,
  }) {
    String? min;
    var anyLivePeer = false;
    for (final m in peerManifests) {
      if (m.deviceId == selfDeviceId) continue;
      if (retiredPeerIds.contains(m.deviceId)) continue;
      if (nowMillis - m.updatedAt > retirementPeriodMillis) continue;
      final acked = m.appliedPeerHlc[selfDeviceId];
      if (acked == null) return const TombstoneGcDecision.blocked();
      anyLivePeer = true;
      if (min == null || acked.compareTo(min) < 0) min = acked;
    }
    if (!anyLivePeer) return const TombstoneGcDecision.unbounded();
    return TombstoneGcDecision.upTo(min!);
  }
}
