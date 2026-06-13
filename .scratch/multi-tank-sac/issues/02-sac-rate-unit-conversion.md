# SAC rate in dive table doesn't convert value when unit changes

Status: ready-for-agent

Labels: bug

## Problem

The Dives table SAC Rate column appends the user's volume unit symbol (e.g. `L/min` vs `ft³/min`) but does not convert the underlying numeric value. A diver using imperial units sees the same number as a metric diver with a different label, producing a nonsensical reading.

Identified during Copilot review of PR #305 (comment on `dive_field_extractor.dart:175`).

## Location

`lib/core/constants/dive_field_extractor.dart` — `sacRate` formatter (~line 175). It appends `${units.volumeSymbol}/min` without converting the SAC value to the active unit first.

## Expected behavior

The displayed SAC numeric value must be converted to the active unit before appending the symbol, consistent with how other volume-based values are displayed elsewhere in the app.

## Acceptance criteria

- [ ] SAC rate column shows correct converted value in both metric (L/min) and imperial (ft³/min) unit settings
- [ ] `_computeGasConsumed` audited for the same issue
- [ ] New or updated tests cover unit conversion for both formatters
