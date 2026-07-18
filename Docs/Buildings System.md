# Buildings System

A passive-structure system layered on top of the existing Science & Knowledge
system (`Docs/Science and Knowledge System.md`). Players construct permanent
structures at bodies (planets/moons/asteroids/stars) that generate Knowledge
forever, scaled by a tier multiplier against the body's own **native rate**
for that category. This doc captures the full design as worked out in
conversation, and the current implementation status.

## Status

**Implemented:** the full architecture (`Buildings` autoload, `BuildingDef`,
`NativeRate`, construction UI in `BuildingsPanel`/`BuildingDetailPanel`/
`StructuresReadout`, the 6-category `KnowledgeBar` top bar) plus ALL FIVE
buildable categories — **Geology**, **Astrophysics**, **Life Sciences**,
**Anomalies**, and **Atmospheric Science**. `Engineering` (the 6th
`KnowledgeBar` category) deliberately has no building ladder at all — see
"Core concept" below ("Engineering is not its own building category"). See
`scripts/core/Buildings.gd`, `scripts/science/BuildingDef.gd`,
`scripts/science/NativeRate.gd`.

**Not part of the Knowledge-category system at all:** the Transfer Station
idea (a separate, simpler feature — see that section below).

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

**Upgrade path once Atmospheric Science exists too (Life Sciences now does):**
replace the boolean `has_atmosphere` penalty with the real continuous formula
designed in conversation — `life_sciences_rate`/`ocean_level` are both real
now (`NativeRate.life_sciences`/`KnownBodies.Entry.ocean_level`), only
`atmosphere_rate` still needs Atmospheric Science's own native rate to exist:
```
preservation = 1.0 - 0.3*atmosphere_rate/100 - 0.3*ocean_level - 0.2*(life_sciences_rate/100)
```
This also fixes the Io/Europa gap automatically in the general case (their
LOW preservation would fall out of high tidal/volcanic activity feeding into
a future "resurfacing" term) rather than needing hand-tuned per-body
overrides forever.

## Atmospheric Science (implemented)

Not "how thick is the haze" (a rendering knob, `PlanetParams.atmosphere`) —
that's calibrated for visuals, not scientific interest (Mars' real density is
~0.6% of Earth's but its rendering value is tuned higher for visibility). The
real driver is **dynamic complexity**, using different generator params per
body type. **Implemented formula** (`NativeRate.atmospheric`):
```
if not has_atmosphere:
    return 0
if is_gas_giant:
    rate = 30 + gas_turbulence*35 + gas_storminess*25 + gas_band_contrast*10
else:  # terrestrial/moon
    rate = atmosphere*25 + ocean_level*35 + (life_bonus) + atmospheric_turbulence*15
```
A thin-but-active atmosphere (Earth: weather, chemistry, a live water cycle)
should outscore a thick-but-static one (Venus: dead, uniform). Gas giants use
their own `gas_turbulence`/`gas_storminess`/`gas_band_contrast` (Jupiter/
Saturn score high; Uranus stays genuinely bland/low, matching
`GasGiantParams.band_contrast`'s own doc comment).

**Deliberate real-science divergence from the doc's original framing above:**
Neptune is NOT paired with Uranus despite both being "calmer-banded ice
giants" visually — real Neptune has the fastest winds in the solar system
(~2100 km/h) and a real Great Dark Spot despite receiving less sunlight than
Uranus. `gas_band_contrast` stays low for both (visually smoother banding),
but `gas_turbulence`/`gas_storminess` deliberately diverge, landing Neptune
well above Uranus — same "documented real-science gap, deliberate override"
precedent as the existing Io/Europa `terrain_ruggedness` exception in the
Geology section above.

**`entry.atmosphere` is reused directly**, not re-derived — despite this
section's own opening caution that raw thickness "is calibrated for visuals,
not scientific interest," the actual per-body values already in
`KnownBodies.gd` (Mercury 0.0, Venus 0.9, Earth 0.35, Mars 0.08) are already
real-fact-grounded, not visually inflated, so no second parallel field was
needed. **One real bug this surfaced and fixed**: Titan's `Entry.atmosphere`
was silently `0.0` (`_make_moon()` never sets it) despite Titan's real
atmosphere being thicker than Earth's — hand-set to `0.55` alongside its new
`atmospheric_turbulence` fact, confirmed safe with zero rendering side
effects (Titan renders via a separate `MoonParams`/`MoonGenerator` path that
never reads `Entry.atmosphere` at all).

**`has_life` has no backing data anywhere** — no "confirmed life discovered"
system exists in code (same finding as the Life Sciences/Anomalies sections).
Substituted with a threshold check on the already-computed
`NativeRate.life_sciences(body_id) >= 40.0` instead of inventing a new
unbacked boolean — Earth and the three subsurface-ocean moons
(Europa/Enceladus/Titan) clear it, nothing else does.

**`turbulence_proxy` (terrestrial branch) is the new `atmospheric_turbulence`
fact** on `Entry` — how active/dynamic the weather is, distinct from
`atmosphere`'s thickness. Hand-set: Earth 0.8 (live weather/jet streams),
Venus 0.1 (this section's own "dead, uniform" framing), Mars 0.3 (real dust
storms, thin atmosphere overall), Titan 0.5 (real methane weather cycle).
Default 0.4 (moderate/unremarkable) everywhere else, same precedent as
`terrain_ruggedness`'s 0.6 default.

## Life Sciences (implemented)

Renamed from "Biology" deliberately — this tracks ongoing habitability
*research* (a legitimate field regardless of outcome, same as real
astrobiology), decoupled from the separate, much rarer, hand-authored
"confirmed life discovered" narrative event (which stays a hero-body-style
special case layered on top, never derived from this rate — nothing like
that exists in code yet, only this passive research rate does).

**Implemented formula** (`NativeRate.life_sciences`):
```
if body_type == "Star":
    return 0
if is_gas_giant:
    return LIFE_GAS_GIANT_FLOOR + LIFE_GAS_GIANT_ACTIVITY_BONUS  # flat "airborne lifeform" flavor, never high
if not has_solid_surface:
    return 0  # defensive only — every non-gas-giant, non-star body in the catalog already has a solid surface
if subsurface_ocean_potential:
    return SUBSURFACE_OCEAN_RATE  # the Titan/Europa exception, see below
temperature_band_score = f(effective_au_distance)  # goldilocks-zone proximity, asymmetric — steep sunward, gentle outward
rate = 100 * temperature_band_score * (has_atmosphere ? 1 : 0.3) * ocean_level
rate += ANCIENT_LIFE_BONUS_RATE if rolled_ancient_life(body_id) else 0  # see "Ancient life roll" below
```

**The Titan/Europa exception — the whole point of this category:** those
bodies are scientifically exciting specifically because they BREAK the
temperature-band rule — frozen solid on the surface, but real astrobiology
prizes them for subsurface oceans kept liquid by tidal flexing from their
giant parent. A naive distance-based formula flatlines every outer moon to
0, losing exactly the "wait, Europa scores real points?" surprise. Implemented
via a new `subsurface_ocean_potential: bool` fact on `KnownBodies.Entry`,
hand-set true on **Europa, Enceladus, and Titan** (not Ganymede/Callisto/
Triton — a deliberate, smaller pick), that bypasses the temperature-band gate
entirely and returns a flat `SUBSURFACE_OCEAN_RATE` (60 — comparable to
Earth's own computed rate, ~70) instead.

**A real gap in the original pseudocode above, found and fixed during
implementation:** `f(au_distance)` breaks for every moon, since
`KnownBodies.Entry.au_distance` is explicitly "unused for moons" and stays
0.0 — a literal implementation would treat every moon as sitting at the Sun.
Fixed by walking up to the *parent's* `au_distance` for any body that has one
(`effective_au_distance` above), so a moon's temperature band correctly
tracks its actual solar distance via its parent, not a meaningless 0.

**`ocean_level`** is now a real `KnownBodies.Entry` fact (0..1, default 0.0 —
dry), same "promote one fact, hand-set only the standouts" move Geology's
`terrain_ruggedness` and Astrophysics' `star_turbulence`/`star_spot_activity`
already were. Only `Earth.ocean_level = 0.7` is hand-set; every other body
correctly stays dry at the default. Deliberately NOT wired into rendering
this pass — `PlanetParams.ocean_level` stays a separate, disconnected render
knob (still defaults to 0.5 for everyone) — scoped to the Knowledge formula
only.

**Ancient life roll (new mechanic, not in the original design above):** a
small seeded 5% chance (`ANCIENT_LIFE_ROLL_CHANCE`) for ANY rocky body
reaching the temperature-band branch to score a flat `ANCIENT_LIFE_BONUS_RATE`
(10) bonus regardless of its current `ocean_level` — representing plausible
ancient/historical habitability even without present-day water. Mars (no
current surface water, but real astrobiology's most iconic target: subsurface
ice, ancient riverbeds, methane plumes) was the motivating case, but it is
NOT special-cased — the roll applies uniformly to every rocky body, curated
or procedural, and is deterministic per body (seeded off the body id, same
salted-`RandomNumberGenerator.seed` idiom `KnownBodies._synthesize_asteroid_
entry` already uses for asteroid `terrain_ruggedness`) so it's stable for the
rest of the session rather than re-rolled every frame.

## Astrophysics (implemented)

The one category with **no hard gate** — mass and orbital dynamics apply to
every body. Small floor, scaled up by gravitational/orbital interest.
**Implemented formula** (`NativeRate.astrophysics`):
```
if body_type == "Star":
    rate = 60 + temp_extremity*20 + (star_turbulence + star_spot_activity)*10  # 60-100
else:
    rate = 5 + radius_ratio*2 + rings*25 + min(moon_count, 10)*2
    rate += 10 if (is_gas_giant or is_ice_giant) else 0
```
Ring systems (`rings`, already on `Entry`) punch above their weight — real
orbital-resonance/disk-dynamics draws. Moon count similarly already exists
on `Entry`. Stars use `surface_temp_k` deviation from an "ordinary G-type
star" reference point plus two new small `Entry` facts, `star_turbulence`/
`star_spot_activity` (hand-set on Sol to match `StarParams`' own rendering
defaults — the only Star that exists in this game today), anchored well
above any planetary body's ceiling (Sol itself lands ~65-70, an intentionally
*ordinary* star, just above Saturn's ~65 as the highest-scoring planet).

**Deliberately simplified vs. the original target formula above this note**:
the real gas/ice-giant term wants `turbulence`/`storminess`/`band_contrast`
from `GasGiantParams`, which are still ephemeral render knobs, not canonical
`Entry` facts (same blocker Atmospheric Science has) — this substitutes a
flat `+10` bonus (`NativeRate.GAS_GIANT_ACTIVITY_BONUS`) instead, same
"simplify the term that isn't canonical yet, note the real upgrade path"
treatment Geology's own `has_atmosphere` boolean got.

**Note:** this category needs relative tuning across the WHOLE body roster
at once (does a ringed ice giant beat a big moonless rocky planet?) rather
than the body-by-body sanity checks that worked for Geology — the constants
above are a first pass, not locked; expect a nudge once seen next to real
Knowledge thresholds in actual play, same as Geology's `RATE_TIME_CONSTANT`
needed after its own first pass read as invisible.

## Anomalies (implemented)

Fundamentally different in *kind* from the other five — not
`f(continuous properties) -> smooth 0-100`, but
`roll(low probability) -> {ordinary: 0} or {anomalous: type + magnitude}`.
Most (body, category) pairs (95%) are ordinary and score flatly 0; 4% get a
minor anomaly (`ANOMALY_MINOR_RATE = 15`), 1% get a major one
(`ANOMALY_MAJOR_RATE = 50`, genuinely late-game).

**No dedicated Anomaly Scan** (a deliberate departure from the doc's original
"or a dedicated Anomaly Scan" phrasing above) — any of the 4 existing survey
activities (Resource, Geological, Astrophysics, Life Sciences) can
independently reveal an anomaly. The roll is per **(body, category)**, not
per body: a single body can have a Geological anomaly AND a separate
Astrophysics anomaly, discovered independently by running each survey there.
`resource_survey`'s own category (`"resource"`) is deliberately included even
though it isn't one of the 6 Buildings Knowledge categories itself — a
Resource Survey can occasionally reveal an Anomalies-category finding, a
cross-pollination that gives Resource Survey late-game relevance beyond
Mining-gating.

**Hand-placed, guaranteed anomalies** (`NativeRate.GUARANTEED_ANOMALIES`) —
since the solar system is a fixed, curated set of bodies (not procedurally
regenerated), specific story-worthy bodies can be seeded with a real anomaly
instead of leaving it to the random roll. Checked first in `anomaly_for`,
overriding the roll entirely for that one `(body, category)` pair — every
other pair at the same body still rolls normally. Currently just **Titan**
(Life Sciences, Major — "Sustained Prebiotic Reaction Cycle," tying into its
real hydrocarbon-lake chemistry and its existing `subsurface_ocean_potential`
exception in the Life Sciences formula above).

Anomaly types shipped this pass (`NativeRate.ANOMALY_TYPES`), physics/
chemistry-flavored only: exotic alloys/antimatter traces (Resource),
non-standard strata/impossible cave geometry (Geological, requires a solid
surface), gravitational fluctuation/spacetime distortion (Astrophysics, no
gate), unidentified organic trace/complex prebiotic chemistry (Life
Sciences, excludes Stars only — gas/ice giants stay eligible, matching
`life_sciences()`'s own "airborne lifeform" flavor for them). **Precursor
ruins are explicitly deferred** — still tonally different (archaeology/lore,
not physics) and still wants its own narrative-unlock payoff rather than
sitting in this physics-flavored roll table. Life Sciences anomaly wording
deliberately stays "unexplained trace," never "confirmed life" — same
narrative-event separation the Life Sciences section above already commits
to.

Discovery rides the existing Survey-as-hint mechanism exactly as originally
envisioned: `NativeRate.anomaly_for(body_id, category_id)` is a pure,
deterministic seeded function (same idiom as `terrain_ruggedness`/
`_rolled_ancient_life`) — always the same ground truth regardless of
discovery — but the survey REPORT (`SurveyReportPanel`'s two `show_*_report`
entry points, or `ActivitiesPanel`'s flat-fallback label for activities
without a rich report class) only surfaces it once that category's survey
has actually run at that body. Revisiting via "Show Results" re-shows the
same anomaly (both report paths re-derive fresh from `NativeRate` every
call, no separate cached/persistent state needed). A dedicated
`AudioManager.anomaly_detected()` voiceover line fires alongside
`survey_complete_vo()` specifically when the just-resolved survey found one,
so it isn't easy to miss/skip past the report.

Construction gating is bespoke (`Buildings.has_required_survey`'s
`"anomalies"` special-case, backed by `Research.has_detected_anomaly`) since
no single activity governs it — true once the player has actually surveyed
a body with at least one activity whose category independently rolled a
real anomaly there, not merely that one mathematically exists.

**Not implemented this pass:** the seeded roll DOES already run across the
full procedural roster (asteroids included, same as every other category),
satisfying "stumble onto a weird one out in the belt." `anomaly_type`/
`anomaly_magnitude` live only as `AnomalyResult`'s in-memory fields (name/
magnitude/description/rate), not persisted `KnownBodies.Entry` facts —
consistent with every other category here having no save system yet.

## Transfer Station (separate idea, not part of the 6 categories)

A cheap building that opens a local sell point (currently, selling only
happens via `SellCargoPanel`, Cockpit-only, Q hotkey, ship-side). Earth would
start with one by default. Not a Knowledge-generating structure at all —
would need its own, much simpler, `BuildingDef`-adjacent shape (no
category_id/multiplier/native-rate concept, just "exists here or doesn't").
Out of scope for the current Buildings architecture; worth its own small
follow-up rather than folding into `Buildings.gd`'s Knowledge-ticking model.

## Punch list for Phase 2+

- **Now fully unblocked, not yet done:** `NativeRate.geology()`'s "Upgrade
  path" (see the Geology section above) — every input it needs
  (`atmosphere`/`life_sciences`/`ocean_level` rates) is real now, but the
  boolean `has_atmosphere` proxy hasn't actually been swapped for the
  continuous preservation formula yet.
- **Also now fully unblocked, not yet done:** `NativeRate.astrophysics()`'s
  gas/ice-giant branch still uses the flat `GAS_GIANT_ACTIVITY_BONUS`
  stand-in — `Entry.gas_turbulence`/`gas_storminess`/`gas_band_contrast` exist
  now (added for Atmospheric Science) and could feed it directly instead.
- `Buildings.RATE_TIME_CONSTANT` (currently `1500.0`) needs a real balance
  pass once Geology is playable and visible next to `Research._technologies`'
  existing milestone thresholds — multiple buildings across multiple bodies
  stack additively, so an overtuned rate could trivialize milestones that
  were balanced around Survey-only Knowledge income.
- Transfer Station, as its own small feature.
