# Buildings System

A passive-structure system layered on top of the existing Science & Knowledge
system (`Docs/Science and Knowledge System.md`). Players construct permanent
structures at bodies (planets/moons/asteroids/stars) that generate Knowledge
forever, scaled by a tier multiplier against the body's own **native rate**
for that category. This doc captures the full design as worked out in
conversation, and the current implementation status.

## Status

**Implemented (Phase 1):** the full architecture (`Buildings` autoload,
`BuildingDef`, `NativeRate`, construction UI in `ActivitiesPanel`, the
6-category `KnowledgeBar` top bar) plus ONE fully working category —
**Geology**. See `scripts/core/Buildings.gd`, `scripts/science/BuildingDef.gd`,
`scripts/science/NativeRate.gd`.

**Roadmapped, not yet implemented:** Atmospheric Science, Life Sciences,
Astrophysics, Anomalies (each needs new `KnownBodies.Entry` facts before its
formula can be written — see each section below), and the Transfer Station
idea (a separate, simpler feature, not part of the Knowledge-category system
at all).

## Core concept

Every body has a 0-100ish **native rate** per Knowledge category, representing
how much that body's own properties support that kind of science. A building
applies a **multiplier** (not an addend) against the native rate:
`knowledge_per_second = native_rate * building_multiplier / RATE_TIME_CONSTANT`.
A building on a body with native rate 0 for its category produces nothing,
regardless of tier — e.g. an Atmospheric Science station on an airless
asteroid should be a real, discoverable mistake, not a smaller version of a
good choice.

**Survey results are the hint mechanism.** The player is never shown native
rate numbers directly. Survey reports (Resource/Geological Survey today,
future Activities for other categories) describe a body's properties in
prose, and the player is expected to infer what's worth building from that —
"no atmosphere detected" is the signal not to build an Atmosphere Station
here, the same way Deposit abundance already hints at what's worth mining.
Construction is gated on having surveyed the relevant category at a body at
least once (`Buildings.has_required_survey`), mirroring Mining's existing
`Research.has_resource_survey` prerequisite.

**Tier ladder shape**, 4 tiers per category (mirrors the user's own Geology/
Biology examples): a cheap Beacon-tier structure at a low multiplier (~0.25),
scaling up to a Complex/Headquarters-tier structure at ~1.5. Each tier costs
more credits + materials than the last, and requires the previous tier's
Knowledge threshold met, mirroring `Research.can_craft()`'s existing
Knowledge-tier-plus-materials gate for Technologies. Tier **replaces in
place** — a body hosts at most one structure per category; building the next
tier upgrades what's there rather than stacking a second structure.

**Engineering is not its own building category.** Every construction, in
ANY category, grants a flat Engineering Knowledge bonus (`Buildings.
ENGINEERING_BONUS_PER_CONSTRUCTION`, currently `10`) — "Construct Geological
Outpost, +10 Engineering," per the original design. No Engineering buildings
exist or are planned.

## Geology (implemented)

Reuses the **existing** `"geological"` Knowledge category (the same pool
Geological Survey activities already feed) rather than a parallel counter —
a Geological Survey Beacon and a Geological Survey both count toward the same
number.

**Key insight (validated against the sample chart during design — an
asteroid scored 90, Earth scored 70):** naive intuition says a more
"interesting"/Earth-like body should score higher, but real planetary
science says the opposite for Geology specifically. Atmosphere, oceans, and
life don't just fail to help — they actively **erase** the geological
record (weathering, erosion, tectonic recycling, resurfacing). An airless,
static body is a time capsule; its crust has been undisturbed for billions
of years. So the driver isn't "how dramatic is this body," it's "how much
pristine record is there to actually read."

**Implemented formula** (`NativeRate.geology`, deliberately simplified — see
"Upgrade path" below):
```
if not has_solid_surface:          # gas/ice giants, stars
    return 15.0                    # residual interior-structure interest only
preservation = 1.0 - (0.4 if has_atmosphere else 0.0)
rate = 100 * clamp(preservation, 0.2, 1.0) * (0.5 + 0.5 * terrain_ruggedness)
```
`terrain_ruggedness` (0..1, new field on `KnownBodies.Entry`) represents
surface complexity/features to survey — hand-set on standout curated bodies
(Luna/Mars/Mercury high; resurfaced/volcanic Europa/Io/Enceladus low despite
being airless, a known documented gap in the simplified formula — see
below), seeded per-asteroid otherwise.

**Upgrade path once Atmospheric Science and Life Sciences exist:** replace
the boolean `has_atmosphere` penalty with the real continuous formula
designed in conversation:
```
preservation = 1.0 - 0.3*atmosphere_rate/100 - 0.3*ocean_level - 0.2*(life_sciences_rate/100)
```
This also fixes the Io/Europa gap automatically in the general case (their
LOW preservation would fall out of high tidal/volcanic activity feeding into
a future "resurfacing" term) rather than needing hand-tuned per-body
overrides forever.

## Atmospheric Science (roadmapped)

Not "how thick is the haze" (a rendering knob, `PlanetParams.atmosphere`) —
that's calibrated for visuals, not scientific interest (Mars' real density is
~0.6% of Earth's but its rendering value is tuned higher for visibility). The
real driver is **dynamic complexity**, using different generator params per
body type:
```
if not has_atmosphere:
    return 0
if is_gas_giant:
    rate = 30 + turbulence*35 + storminess*25 + band_contrast*10
else:  # terrestrial
    rate = atmosphere*25 + ocean_level*35 + (has_life ? 25 : 0) + turbulence_proxy*15
```
A thin-but-active atmosphere (Earth: weather, chemistry, a live water cycle)
should outscore a thick-but-static one (Venus: dead, uniform). Gas giants
use their own turbulence/storminess/band_contrast (Jupiter/Saturn score high;
Uranus/Neptune's "calmer bands," per `GasGiantParams.gd`'s own comment,
score lower despite being the same body type).

**Blocker:** `ocean_level`, `turbulence`, `storminess`, `band_contrast` are
currently ephemeral generator-input knobs (`PlanetParams`/`GasGiantParams`),
not canonical per-body facts on `KnownBodies.Entry`. They need to be
promoted to real `Entry` fields (same as `has_atmosphere`/`atmosphere`
already are) before this formula can run independent of whatever view
happens to be rendering the body.

## Life Sciences (roadmapped)

Renamed from "Biology" deliberately — this tracks ongoing habitability
*research* (a legitimate field regardless of outcome, same as real
astrobiology), decoupled from the separate, much rarer, hand-authored
"confirmed life discovered" narrative event (which stays a hero-body-style
special case layered on top, never derived from this rate).

```
if body_type == "Star":
    return 0
if not has_solid_surface and not is_gas_giant:  # airless rock
    return 0
if is_gas_giant:
    return small_floor + turbulence_bonus   # "airborne lifeform" flavor, never high
else:
    temperature_band_score = f(au_distance)  # goldilocks-zone proximity, punishes Venus-style runaway greenhouse
    rate = temperature_band_score * (has_atmosphere ? 1 : 0.3) * (ocean_level presence)
```

**The Titan/Europa exception — the whole point of this category:** those
bodies are scientifically exciting specifically because they BREAK the
temperature-band rule — frozen solid on the surface, but real astrobiology
prizes them for subsurface oceans kept liquid by tidal flexing from their
giant parent. A naive distance-based formula flatlines every outer moon to
0, losing exactly the "wait, Europa scores real points?" surprise. Needs a
new `subsurface_ocean_potential: bool` fact on `KnownBodies.Entry` (hand-set
for the icy-moon archetype, same as `has_atmosphere` is hand-set today) that
bypasses the temperature-band gate entirely when true.

**Blocker:** same `ocean_level`-not-canonical issue as Atmospheric Science,
plus the new `subsurface_ocean_potential` field.

## Astrophysics (roadmapped)

The one category with **no hard gate** — mass and orbital dynamics apply to
every body. Small floor, scaled up by gravitational/orbital interest:
```
if body_type == "Star":
    rate = 60 + activity_bonus(temperature_extremity, turbulence, spot_activity)  # 60-100
else:
    rate = 5 + size_term(radius_ratio) + rings*25 + min(moon_count, 10)*2
    rate += is_gas_giant ? activity_term(turbulence, storminess) : 0
```
Ring systems (`rings`/`ring_tracks`, already on `Entry`) punch above their
weight — real orbital-resonance/disk-dynamics draws. Moon count similarly
already exists on `Entry`. Stars use the temperature/turbulence/spot_activity
formula from `StarParams` (already canonical there), anchored well above any
planetary body's ceiling.

**Note:** this category needs relative tuning across the WHOLE body roster
at once (does a ringed ice giant beat a big moonless rocky planet?) rather
than the body-by-body sanity checks that worked for Geology — treat the
constants as "get the ingredients right first, tune weights once the whole
table is visible," not something to lock before playtesting.

**Blocker:** none structurally — every input (`radius_ratio`, `rings`,
`moon_count`, star fields) already exists on `Entry`. This is the next
easiest category to implement after Geology.

## Anomalies (roadmapped)

Fundamentally different in *kind* from the other five — not
`f(continuous properties) -> smooth 0-100`, but closer to
`roll(low probability) -> {ordinary: 0} or {anomalous: type + magnitude}`.
Most bodies (~95%+) are ordinary and score flatly 0; a small fraction get a
minor anomaly (small nonzero rate, common enough to feel achievable), a very
rare fraction get a major one (large rate, genuinely late-game — "Researching
anomalies unlocks your late-game tech").

Anomaly types considered: strange magnetic fields, impossible crystals,
gravitational distortions, temporal effects, dark matter concentrations,
quantum weirdness — all physics-flavored, same genre/different magnitudes —
plus **precursor ruins**, which is tonally different (archaeology/lore, not
physics) and probably wants a different downstream payoff (a narrative
unlock rather than a tech-tree unlock) — worth deciding deliberately rather
than letting it sit in the same roll table as "weird crystals" by default.

Needs a genuinely new generation step: a seeded per-body roll (not just
curated hero bodies — the "stumble onto a weird one out in the belt" feeling
requires this to run across the full procedural roster, asteroids included),
assigning an `anomaly_type` + `anomaly_magnitude`. Discovery should ride the
same Survey-as-hint mechanism as everything else — ordinary bodies have
nothing to detect, so a Survey (or a dedicated Anomaly Scan) revealing "this
body has something" before the player would think to build here is
consistent with how every other category already works.

**Blocker:** entirely new fields/generation logic — the biggest lift of the
five roadmapped categories.

## Transfer Station (separate idea, not part of the 6 categories)

A cheap building that opens a local sell point (currently, selling only
happens via `SellCargoPanel`, Cockpit-only, Q hotkey, ship-side). Earth would
start with one by default. Not a Knowledge-generating structure at all —
would need its own, much simpler, `BuildingDef`-adjacent shape (no
category_id/multiplier/native-rate concept, just "exists here or doesn't").
Out of scope for the current Buildings architecture; worth its own small
follow-up rather than folding into `Buildings.gd`'s Knowledge-ticking model.

## Punch list for Phase 2+

- Promote `ocean_level`, gas-giant `turbulence`/`storminess`/`band_contrast`
  to canonical `KnownBodies.Entry` fields (currently ephemeral
  `PlanetParams`/`GasGiantParams` render knobs).
- Add `subsurface_ocean_potential: bool` to `Entry` for the Life Sciences
  icy-moon exception.
- Add an anomaly roll + `anomaly_type`/`anomaly_magnitude` fields, extended
  to the procedural (asteroid) generation path, not just curated bodies.
- Once Atmospheric Science and Life Sciences native rates exist, upgrade
  `NativeRate.geology()` to consume their real continuous values instead of
  the `has_atmosphere` boolean proxy (see "Upgrade path" above).
- `Buildings.RATE_TIME_CONSTANT` (currently `1500.0`) needs a real balance
  pass once Geology is playable and visible next to `Research._technologies`'
  existing milestone thresholds — multiple buildings across multiple bodies
  stack additively, so an overtuned rate could trivialize milestones that
  were balanced around Survey-only Knowledge income.
- Transfer Station, as its own small feature.
