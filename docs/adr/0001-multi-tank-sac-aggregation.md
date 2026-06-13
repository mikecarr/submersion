# Multi-tank SAC aggregation strategy

Volume-based SAC (L/min) sums gas consumed across all tanks in a dive regardless of role, because the diver was breathing from each tank and all gas consumption reflects their breathing efficiency. Dives with partial tank data (some tanks missing start/end pressures) are included using only the tanks that have valid readings — excluding the dive entirely would make stats charts patchier without meaningful benefit.

Pressure-based SAC (bar/min) is restricted to the back gas tank (falling back to the first tank if no tank carries `TankRole.backGas`) because summing pressure drops across tanks of different volumes is dimensionally incoherent. For multi-tank dives where an accurate aggregate SAC is needed, L/min is the correct metric.

## Considered options

- **All tanks for pressure SAC** — rejected because averaging bar/min across a 12L back gas and a 7L stage tank produces a number with no physical meaning.
- **Back gas only for volume SAC** — rejected because the diver is actively breathing from stage and deco tanks; excluding them understates total gas consumption and overstates efficiency.
