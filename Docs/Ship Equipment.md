# Ship Equipment

## Design Pillar

Ship Equipment is the game's primary "carrot on a stick." Travel, surveying, and mining all feed into acquiring better equipment, which in turn unlocks farther/faster/richer versions of those same loops. This is meant to be the first system that gives the player an in-your-face, visible reason to keep pushing outward.

## Acquisition Model

Every slot uses the **same Knowledge + Materials craft gate instruments already use** — `TechnologyDef.knowledge_requirements` / `materials_requirements`, unlocked and crafted via `Research.craft_technology()`. One unified progression currency across all six slots, not a separate Credits shop (Economy/Credits stays exactly as it is today — still nothing to spend Credits on, that's a separate open gap). Equipment never "expires" or swaps out sideways; a slot's chain just keeps advancing through its own tiers, same as an Activity's instrument chain does today.

## Ship Equipment Slots

- Sub-Light Engines
- Beyond Light Engines
- Scanner Array
- Mining System
- Cargo Hold
- Navigation Scanner (TBD)

## Starting Loadout

| Slot | Tier 0 |
|---|---|
| Sub-Light Engines | Liquid Fuel Engines *(see naming note below)* |
| Beyond Light Engines | None |
| Scanner Array | Basic Spectrometer |
| Mining System | Mechanical Excavator |
| Cargo Hold | Standard Hold |
| Navigation Scanner | Basic Navigation Scanner |

---

## Scanner Array

**Purpose:** Speeds up all Surveys. Higher tiers also gate detection bonuses — Resource Survey specifically gains rarer-material detection at higher tiers. This is also the natural home for `Docs/Mining.md`'s already-designed **Deep Vein** mechanic — a higher Scanner Array tier re-reveals additional yield at an already-surveyed deposit (`Research._surveyed_tier`, the highest tier that has ever surveyed a given body, already tracks the state this needs).

**This slot replaces the per-Activity instrument chains** (decided 2026-07-18). Today, Resource Survey and Geological Survey each own an independent `instruments: Array[InstrumentDef]` chain in `Research.gd`, unlocked off that Activity's own Knowledge category. Scanner Array collapses those into **one ship-wide chain** that every survey category reads from — the Resource-Survey-only detection bonus becomes a special-cased effect of specific tiers on this one chain, not a second independent track.

**Implementation note:** this is a real restructure of `Research.gd`'s data model (per-Activity `current_instrument` → ship-wide equipment state), not a relabeling. Needs its own implementation pass.

**Tiers** (reuses/renames the already-built Resource Survey instrument chain — `Data/Science/ResourceSurvey/instrument_*.tres` — rather than inventing new names):

0. Basic Spectrometer
1. Advanced Spectrometer
2. Deep Penetration Scanner
3. Quantum Resonance Imager *(renamed from "Quantum Mineral Imager" — now ship-wide, not Resource-specific)*
4. Exotic Matter Resonator

---

## Sub-Light Engines

**Purpose:** Makes you go faster within a system (internal system travel).

**Naming conflict to resolve:** this doc's own Tier 0 is "Liquid Fuel Engines," but `TravelCalc.ENGINE_TIERS` already has a tuned 5-tier ladder in code under different names:

0. Ion Drive
1. Fusion Drive
2. Improved Fusion
3. Antimatter Drive
4. Relativistic Cap

Recommend adopting the code's existing names rather than renaming a already-tuned constant for no functional reason — but flagging so it's a conscious choice, not a silent overwrite. If "Liquid Fuel Engines" is preferred as the Tier 0 flavor name, that's a one-line rename in `TravelCalc.ENGINE_TIERS`.

**Implementation note:** this ladder is wired *only* to the F2 cheat menu (`PlayerState.engine_tier_override`) today — a dev testing toggle, not real player-owned progression. Turning it into real Ship Equipment means building genuine ownership/craft state for it (Knowledge + Materials, same as everything else here), not just exposing the existing dev switch to the player.

---

## Beyond Light Engines

**Purpose:** Used for interstellar travel and beyond.

**Open dependency: interstellar travel doesn't exist yet.** The universe today is Sol + its planets only — there is no other star system to fly to, and no FTL/warp mechanic. This slot's entire payoff is blocked on a much larger, unscoped future feature. Reserve the slot and lock in tier names now; defer real tier *effects* (and whether tiers 2+ need anything beyond Knowledge+Materials, e.g. a discovered system) until interstellar travel itself is designed.

**Tiers** (all new, no starting gear — begins at None):

1. Warp Bubble Generator — short hops to the nearest stars
2. Alcubierre Drive — practical interstellar cruising range
3. Folded Space Drive — folds spacetime to skip vast distances
4. Wormhole Threader — stable, traversable wormhole network
5. Singularity Drive — near-instant, near-unlimited reach

---

## Mining System

**Purpose:** Speeds up mining. Possibly a yield multiplier as well.

**Reconciliation needed:** `Data/Science/Mining/instrument_precision_mining_laser.tres` already exists in code as the *only* Mining instrument today, standing in at tier 0. Under this doc's naming it should be repositioned to tier 1, with a genuinely basic "Mechanical Excavator" added ahead of it as the real tier 0.

**Tiers:**

0. Mechanical Excavator
1. Precision Mining Laser *(existing asset — reused, not discarded)*
2. Plasma Cutting Array
3. Molecular Disassembler
4. Graviton Extraction Rig

**Open question:** if a yield multiplier is added (not just speed), does it also raise `Deposits.total_units()` for a deposit — i.e. does better equipment make a deposit literally bigger, not just faster to drain? Needs a decision before tuning numbers.

---

## Cargo Hold

**Purpose:** Increases Cargo capacity.

**Implementation note:** `Deposits.CARGO_CAPACITY` is a single flat constant (20,000) today, ship-wide, with no tier data model at all — this is the most greenfield of the six slots.

**Tiers:**

0. Standard Hold
1. Reinforced Hold
2. Modular Cargo Bay
3. Compression Hold
4. Quantum Vault

---

## Navigation Scanner

**Purpose (clarified 2026-07-18): this slot is about *ship navigation* — detecting what bodies actually exist in a system, not surveying a body you already know is there.**

**The Sol system exception (2026-07-18, implemented):** the game starts in 2037. By then humanity already has complete navigational/data knowledge of every planet, moon, and asteroid in our own solar system — real astronomy, not a gameplay gate. Sol's fully-known System View (every body already positioned/nameable, no discovery step) is therefore **correct as a permanent narrative fact about Sol specifically**, not a dev shortcut standing in for a system that hasn't been built yet. Navigation Scanner tiers are meaningless inside Sol and should stay a no-op there.

Concretely, this means the System View "SCAN → SCANNING… → data panel" step is skipped entirely for every Sol body — selecting one goes straight to its `BodyInfoPanel` data. **`Discoveries.gd` now implements this generally**: `scan_tier(id)` defaults to `SCANNED` for any id `KnownBodies.get_entry()` recognizes (every curated planet/moon, plus any asteroid already spawned this session), rather than the old hardcoded Earth/Luna-only pre-scan. A future non-Sol system's bodies won't resolve via `KnownBodies` (a Sol-only catalog) and will correctly default to unscanned there, without needing this to change later.

**Important distinction this does NOT change:** Sol bodies being navigationally known is separate from their Scanner-Array survey data being known. A body can be fully mapped on the System View (you know Mars exists, where it is, that it has two moons) while still being completely unsurveyed for resources/geology/etc. — that still requires owning the right Scanner Array tier and actually running a survey there, exactly as today.

**Everywhere else, the slot works as originally designed:** arriving at any system beyond Sol should start with **zero** navigational knowledge of its planets/moons, revealed by whatever Navigation Scanner tier is owned — likely with tiered range/fidelity (immediate reveal of only the largest/nearest bodies at low tiers, full system layout at the top tier). This is why it's TBD, not just unbuilt: the planetary/body-scanning system needs a rework to represent *limited* knowledge of an unknown area, a case Sol will never need but every other system will. Same category of "reserve the slot, defer real effects" as Beyond Light Engines — and the two are linked: this slot only starts mattering once Beyond Light Engines make leaving Sol possible.

**Flagged as possibly revisited later:** the user notes Sol's own treatment "might change later" — if some future design wants even Sol to carry some navigational mystery (e.g. undiscovered objects), this exception would need to be loosened. Not a concern today.

**Tiers** (renamed to reflect detection range/fidelity, not resource depth — Deep Vein/resource re-detection lives on Scanner Array instead, see above):

0. Basic Navigation Scanner
1. Short Range Detector — reveals only the largest/nearest bodies immediately around arrival
2. Extended Range Array — reveals the system's full planetary layout
3. Deep Stellar Scan — reveals moons, asteroid belts, and other minor bodies
4. Stellar Cartography Suite — full instant mapping of every body in the system, nothing left hidden

---

## Open Questions / Deferred

- Exact numeric tuning per tier: scan-speed %, mining-speed/yield %, cargo capacity, Knowledge + Materials craft costs — deferred to implementation planning.
- Mining System yield-vs-total-deposit-size question above.
- Beyond Light Engine tier 2+ requirements once interstellar travel exists.
- The fog-of-war/limited-knowledge rework Navigation Scanner depends on — no design started, blocked on interstellar travel existing at all.
