# Submersion

A dive logging application for scuba divers. The core domain is recording, analysing, and visualising dive data including gas consumption, depth profiles, and equipment.

## Language

### Dives

**Dive**:
A single recorded underwater excursion, identified by dive number and date/time. Contains depth, duration, gas, and equipment data.
_Avoid_: Session, entry, log entry

**Bottom time**:
Time spent at depth, excluding descent and ascent. Stored as `bottomTime`.
_Avoid_: Duration (ambiguous — used for runtime in imported data), dive time

**Runtime**:
Total elapsed time from entry to exit, including descent and ascent. The preferred denominator for SAC calculations.
_Avoid_: Total time, elapsed time, duration

**Effective runtime**:
Runtime when available, falling back to bottom time. The single field callers should use when they need a dive's time for SAC or rate calculations.
_Avoid_: Duration

**Dive profile**:
Time-series of depth and sensor readings captured during a dive. Used for phase analysis, SAC segmentation, and chart rendering.
_Avoid_: Profile data, depth trace

### Gas and Tanks

**SAC (Surface Air Consumption)**:
The rate at which a diver consumes gas normalised to surface pressure. Expressed as L/min (volume SAC) or bar/min (pressure SAC). Measures breathing efficiency across dives.
_Avoid_: Air consumption rate, breathing rate, gas consumption rate

**Volume SAC**:
SAC expressed in L/min. Requires tank volume. Sums gas consumed across all tanks on the dive. The preferred SAC metric for multi-tank dives.
_Avoid_: SAC in litres, litre-based SAC

**Pressure SAC**:
SAC expressed in bar/min. Does not require tank volume. For multi-tank dives, only the back gas tank (or first tank if no back gas role is set) is used — summing pressure across tanks of different volumes is dimensionally incoherent.
_Avoid_: Bar SAC, pressure-based consumption

**CylinderSac**:
Per-cylinder SAC calculated using the actual time window that specific cylinder was breathed, not total dive runtime. Used in the dive detail view to show breathing rate per tank phase.
_Avoid_: Tank SAC, per-tank SAC

**DiveTank**:
A tank used on a specific dive, carrying gas mix, volume, working pressure, start/end pressures, and a role.
_Avoid_: Cylinder (acceptable in UI copy), bottle, tank record

**Back gas**:
The primary breathing tank (`TankRole.backGas`), typically the largest tank. The reference tank for pressure SAC on multi-tank dives.
_Avoid_: Primary tank, main tank, back-mount gas

**Tank role**:
The designated purpose of a DiveTank: back gas, stage, deco, bailout, diluent, or oxygen. Determines how the tank is treated in SAC and gas planning calculations.
_Avoid_: Tank type, cylinder type

**Gas mix**:
The O₂/He/N₂ composition of the gas in a tank. Represented as `GasMix` with `o2` and `he` fractions.
_Avoid_: Blend, mixture, gas blend

**GasMix**:
The domain type representing a breathing gas composition. Has named forms (Air, Nitrox, Trimix, Oxygen) derived from o2/he fractions.
_Avoid_: Gas, blend

### Dive Sites and Equipment

**Dive site**:
A named location where dives take place, optionally with GPS coordinates and descriptions.
_Avoid_: Location, spot, site

**Gear**:
Equipment items tracked across dives with service history.
_Avoid_: Equipment (acceptable in UI copy), kit
