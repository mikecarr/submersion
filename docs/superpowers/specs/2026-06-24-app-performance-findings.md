# App Performance — Phase 1 Findings

**Date:** 2026-06-24
**Spec:** docs/superpowers/specs/2026-06-24-app-performance-investigation-design.md
**Plan:** docs/superpowers/plans/2026-06-24-app-performance-phase1-measurement.md
**Mode:** profile, macOS

## Environment
- Flutter: 3.41.4 stable (framework ff37bef603, engine e4b8dca3f1)
- macOS: 26.5.1 (build 25F80)
- Mac: MacBook Pro (Mac17,8), **Apple M5 Pro**
- Display: Built-in Liquid Retina XDR, 3456x2234 Retina, ProMotion (up to 120 Hz)
- Frame budget: 8.3 ms @ 120 Hz / 16.7 ms @ 60 Hz — **confirm the actual budget line from the DevTools Frames chart** (Flutter macOS desktop may render at 60 Hz even on a ProMotion panel)
- Library shape (from the design spec): 37 dives, 40,933 profile samples (avg 1,106, max 3,644), 40,912 tank-pressure samples, 22 MB DB

## Scenario 1 — Cold start / load time

### Numbers
| Metric | Value |
| --- | --- |
| Time to first frame (engine -> splash) | **74 ms** (`flutter run --trace-startup`) |
| Perceived splash -> dashboard usable (cold, observed) | **~2 s** |
| Artificial floor (deterministic, from code) | **1.9 s** = 1 s minimum (`startup_page.dart:191`) + 0.9 s fade (`:110`) |

### Verdict
- Engine/framework init is **negligible** — 74 ms to first frame on an M5 Pro. NOT a contributor.
- Perceived load (~2 s) ≈ the artificial floor. Service init (DB opens, species seed) runs under the 1 s minimum (`Future.wait([_initializeServices(), Future.delayed(1s)])`), so at this library size it is **masked by the floor, not additive**.
- **L1 (shrink splash floor): CONFIRMED dominant.** ~1.5-1.8 s of perceived load is recoverable by reducing the 1 s minimum + 0.9 s fade to a minimal anti-flicker.
- **L2 (species re-seed) / L3 (redundant opens): not separately visible** — hidden under the 1 s minimum. They matter only once L1 lowers the floor below service-init time; quantify service-init (a cold-start CPU profile) when implementing L1.
- L4 (pre-runApp awaits): subsumed in the 74 ms first frame; negligible.

## Scenario 2 — First dive-details lag
(filled by Task 3)

## Scenario 3 — Background-sync stutter
(filled by Task 4)

## Avenue verdicts & Phase 2 ranking
(filled by Task 5)
