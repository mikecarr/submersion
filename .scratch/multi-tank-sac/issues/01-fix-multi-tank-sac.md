# Fix SAC calculations to aggregate all tanks on multi-tank dives

Status: done

## Problem

Two surfaces show incorrect SAC values on multi-tank dives:

- **Dive table SAC Rate column** (`_computeSacRate` in `dive_field_extractor.dart`) uses `tanks.first` only, ignoring all other tanks.
- **Statistics page** (trend charts and best/worst records in `statistics_repository.dart`) JOINs `dive_tanks` without aggregating — each tank row becomes an independent data point instead of being summed per dive.

`Dive.sac` already correctly sums all tanks; the table column and SQL queries just don't use it.

## Decisions (see `docs/adr/0001-multi-tank-sac-aggregation.md`)

- **Volume SAC (L/min)** sums gas consumed across all tanks regardless of role.
- **Pressure SAC (bar/min)** uses the back gas tank only (`TankRole.backGas`), falling back to `tanks.first` — summing pressure across different-sized tanks is dimensionally incoherent.
- Dives with partial tank data (some tanks missing pressures) are included using only tanks with valid readings.

## Changes required

### `lib/core/constants/dive_field_extractor.dart`
- `_computeSacRate`: replace `tanks.first` logic with `return dive.sac`
- `_computeGasConsumed`: sum gas across all tanks (same pattern as `Dive.sac`)

### `lib/features/dive_log/domain/entities/dive.dart`
- `sacPressure`: find back gas tank (`tanks.firstWhere(role == backGas, orElse: tanks.first)`) and use only that tank instead of averaging pressure across all tanks by count

### `lib/features/statistics/data/repositories/statistics_repository.dart`
- `getSacVolumeTrend`: wrap per-tank calculation in a CTE that SUMs gas per dive before the monthly AVG
- `getSacPressureTrend`: filter to back gas / first tank per dive before computing bar/min
- `getSacVolumeRecords`: aggregate tanks per dive in a CTE before ORDER BY
- `getSacPressureRecords`: filter to back gas / first tank per dive before ORDER BY

## Tests to add/update
- `test/features/dive_log/domain/entities/dive_sac_test.dart` — multi-tank volume SAC, multi-tank pressure SAC (back gas only)
- `test/features/statistics/` — verify SQL aggregation produces one SAC value per dive
