# Show both dives on a "Likely duplicate" quality finding

Date: 2026-08-11

## Problem

Expanding a "Likely duplicate" finding in the Data Quality inbox shows a
"Consolidate" action and a single "Go to dive" link -- for `finding.diveId`
only. There is no way to see or reach the second dive (`finding.relatedDiveId`)
without leaving the inbox and hunting for it in the dive list. A user deciding
whether two dives are really the same dive has to act on faith, or go find
the other dive manually before coming back to consolidate.

## Decision

Add a compact two-up comparison (date/time, depth, duration, computer, plus a
"View dive" link) inside the expanded "Likely duplicate" card, using the
`evidence` slot `QualityFindingCard` already exposes but that nothing
currently populates.

## Design

- New widget `DuplicateDiveComparison`
  (`lib/features/data_quality/presentation/widgets/duplicate_dive_comparison.dart`),
  a `ConsumerWidget` taking `diveId`, `relatedDiveId`, and the page's existing
  `QualityUnitFormatters`. It watches `diveProvider(diveId)` and
  `diveProvider(relatedDiveId)` (both already exist,
  `lib/features/dive_log/presentation/providers/dive_providers.dart:199`) and
  renders two summary cards side by side: entry date/time, max depth, runtime,
  dive computer model. No new provider or repository method needed.
- Each card has a "View dive" button. Wired to the same navigation
  `data_quality_inbox_page.dart` already uses for the existing "Go to dive"
  footer link (`context.push('/dives/$id')`).
- `data_quality_inbox_page.dart` passes
  `evidence: DuplicateDiveComparison(...)` into `QualityFindingCard` only when
  `finding.detectorId == 'duplicate' && finding.relatedDiveId != null`. No
  other finding type is affected; `QualityFindingCard` itself is unchanged.
- Scoped to the `duplicate` detector only, not `split_pair` (also carries a
  `relatedDiveId`, but represents a computer splitting one dive into two
  segments -- a different scenario from two independently-logged dives).
  Worth the same treatment later, but out of scope here.
- A finding is always a pair (`DuplicateDetector.detect` emits one finding per
  matching neighbor -- `duplicate_detector.dart:48-62`), never a 3+-way
  cluster. Three similar dives means two separate findings under the same
  dive's header (already how the inbox groups them via `_groupByDive`), each
  independently showing its own two-up comparison. No special-casing needed
  for clusters.

## Edge case

If either dive fails to load (deleted by a sync mid-session, consolidated
away by resolving a different finding for the same dive first, ...), that
side of the comparison shows a small "Dive not found" fallback instead of
crashing the card or blocking the other side from rendering.

## Alternatives considered

- Fetch both dives inside `QualityFindingCard` itself (convert it from
  `StatefulWidget` to `ConsumerStatefulWidget`): couples the card to
  Riverpod and to per-detector fetching logic it doesn't otherwise need,
  when the page already has an `evidence` extension point built for exactly
  this. Rejected.
- Minimal version with just a second "Go to dive" link, no inline facts:
  matches part of what was asked, but doesn't let the user judge whether the
  two dives are really duplicates without navigating away twice. The
  mockup version (two-up summary + link each) was confirmed against a
  visual mockup during design; going with that.
- Include `split_pair` findings in the same widget now: same underlying
  shape (`diveId` + `relatedDiveId`), but a materially different question
  ("is this one dive split into two files" vs "are these two dives the same
  dive") -- reusing the exact same card copy/layout risks confusing the two.
  Left as a natural, easy follow-up once this ships.

## Testing

Widget test in `test/features/data_quality/presentation/data_quality_inbox_page_test.dart`
(or a new dedicated test file for `DuplicateDiveComparison` if the widget
warrants isolation): seed two real dives with distinct depth/duration/computer
via `DiveRepository().createDive(...)` (matching the existing
`time-shift repair` test's pattern of seeding real dives against the test
DB), seed a `duplicate` finding referencing both, expand the card, and assert
both dives' facts render and that tapping each "View dive" button navigates
to the corresponding dive id. A second test covers the missing-dive fallback
by seeding a finding whose `relatedDiveId` doesn't exist in the DB.
