# The Parallax Initiative

## Science & Knowledge System — Implementation Roadmap

**Version:** Roadmap Draft 1.0
**Companion to:** `Science and Knowledge System.md` (vision), `Question 2 Answer.md` (data architecture)

---

# Purpose

The vision and architecture docs describe *what* the system is. This document breaks it into an *order of construction* — a sequence of phases, each small enough to implement and verify in a single working session, each leaving the game in a playable (if incomplete) state.

Phases are ordered so nothing is built against a dependency that doesn't exist yet.

---

# Decisions Locked In (from design conversation)

* **Tools gate activities, not the reverse.** A location shows only the activities the player currently has an instrument for. Early game: 1-2 activities available anywhere. Late game: all 12.
* **Data format: Godot `Resource` (.tres), not JSON.** Hand-authored Activity/Instrument/Technology definitions live as native Godot resources — editor-authorable, type-checked, consistent with the rest of the project.
* **No confidence percentages.** Instrument upgrades produce discrete new capabilities/discoveries, not the same discovery with a rising certainty number.
* **Knowledge resets with New Game.** It is per-save-file state, not meta-progression across saves.
* **Crafting has two independent gates:** Knowledge unlocks the *blueprint* (reaching a threshold in one or more categories); actual materials (harvested, per-planet) are required to *craft* the first prototype. First-pass crafting UI is a plain requirements list + a Craft button that enables once both gates are satisfied.
* **UI placement:** the "what can I do here" list is a **Cockpit-only right-side panel** (`ActivitiesPanel` or similar) that appears when arrived at a location — not part of System View or Planetary System View. `BodyInfoPanel` already occupies the left side of the Cockpit view, so the new panel sits opposite it with no layout conflict.

---

# Known Open Dependencies (not blockers, but flagged)

* **No save/load system exists yet.** `PlayerState`, `Discoveries`, etc. are all in-memory-only today (reset on New Game). Knowledge/Instrument state should be built the same way — in-memory now, save-shaped later — per the existing pattern in `Discoveries.gd`. Do not block phases on building real save/load; that is a separate, later, project-wide effort (Phase 7 below).
* **No currency/economy system exists yet.** Relevant only to the tail end of the loop ("future units become purchasable"). Can be stubbed (instant unlock, no cost) until an economy system exists.

---

# Phase 0 — Data Foundation

**Goal:** Prove the data shape. No autoloads, no UI, nothing runtime yet.

* Define `ActivityDef`, `InstrumentDef`, `TechnologyDef` as `Resource` subclasses (`class_name`, exported fields).
* `ActivityDef`: name, knowledge category, ordered list of `InstrumentDef`.
* `InstrumentDef`: name, capability description(s), the `TechnologyDef` that unlocks it.
* `TechnologyDef`: name, knowledge requirements (one or more categories + thresholds), unlock/flavor text, (later) material requirements.
* Hand-author **one full chain** as `.tres` files — Resource Survey, 3-4 instruments — to validate the schema holds together.

**Done when:** the Resource Survey chain loads cleanly and can be inspected/edited in the Godot editor.

---

# Phase 1 — Knowledge & Instrument State

**Goal:** Runtime state exists; nothing player-visible yet.

* New autoload(s) following the exact shape of `Discoveries.gd`/`PlayerState.gd`: flat dictionary state, `reset_for_new_game()` hookup, in-memory only.
* Tracks: Knowledge total per category; currently-owned instrument tier per activity.
* Player starts with 1-2 activities unlocked (e.g. Resource Survey Tier I, Geological Survey Tier I); everything else locked.
* Verify via debug prints or `CheatMenu.gd` — no real UI yet.

**Done when:** you can confirm (via cheat menu / print) which activities are available and award/inspect Knowledge values directly.

---

# Phase 2 — Survey Action (closes the core loop)

**Goal:** The loop becomes real and playable, even if ugly.

* Resolve "activities available at this location" = current owned instruments ∩ activities (universal per-location for now; no per-body-type filtering yet).
* Build the **Cockpit right-side Activities Panel**: appears on arrival, lists available activities, each with a "Run Survey" action.
* Running a survey awards Knowledge in its category and shows a simple result (hand-authored per instrument tier — not yet unique per planet).

**Done when:** Travel → open Activities Panel → run a survey → Knowledge visibly increases, end to end.

---

# Phase 3 — Milestones & Unlocks

**Goal:** Knowledge accumulation starts producing new capability.

* A checker runs whenever Knowledge changes, compares totals against all locked `TechnologyDef`s, and fires an "Earth Transmission" event when requirements are met (including multi-category requirements).
* On trigger: grant the next instrument tier for the relevant activity/activities.
* Reuse the existing modal/notification patterns already in the project for this transmission event.

**Done when:** performing surveys can visibly unlock a new instrument tier, changing what's available in the Phase 2 panel.

---

# Phase 4 — Research UI Panel

**Goal:** Surface everything Phases 0-3 built. No new mechanics.

* New HUD tab (alongside the existing PLANETARY tab): per-category display — current Knowledge, current instrument, next milestone + requirement progress, "Future Developments: Unknown" for anything further out.

**Done when:** the player can check overall science progress without needing the cheat menu.

---

# Phase 5 — Materials & Crafting

**Goal:** The other crafting gate becomes real.

* Player materials inventory — harvested via Resource Surveys, tied into Cosmic Forge's existing per-planet resource data.
* `TechnologyDef` gains a materials-cost list alongside its Knowledge requirements.
* Basic crafting screen: requirements list (Knowledge gate + materials gate), Craft button enabled only when both are satisfied.

**Done when:** a full prototype can be crafted from surveyed Knowledge + harvested materials.

---

# Phase 6 — Earth Manufacturing Loop (stub-acceptable)

**Goal:** Close the "prototype → future purchasable units" loop, minimally.

* Post-craft, a technology becomes purchasable. Since no currency system exists, start as an instant/no-cost unlock; a real economy can be layered in later without reworking this phase.

**Done when:** crafting a prototype makes future units available through whatever acquisition flow exists at the time.

---

# Phase 7 — Real Save/Load

**Goal:** Persist the whole feature (and likely the rest of the project's in-memory state alongside it).

* Retrofit save/load once the feature's shape has stabilized through play-testing — same "in-memory now, backend swap later" reasoning already used by `Discoveries.gd`.

**Done when:** Knowledge, instruments, materials, and crafted prototypes survive a save/reload cycle.

---

# Working Notes

* Each phase should be its own session/commit — phases are context-heavy and independently verifiable.
* Nothing in Phases 0-4 depends on Phase 5/6/7 existing; the core science loop is fully playable without crafting, purchasing, or saving.
* Revisit per-planet-unique discovery text (vs. hand-authored per-instrument-tier text) as a later refinement once the loop is proven — not a blocker for any phase above.

---

# Open Design Question (raised by Knowledge Domains and Tech Catalog.md)

That doc frames Technologies as cross-cutting catalog categories (e.g. "Sensors & Scientific Equipment") spanning multiple Activities and multiple Knowledge Domains at once — different from the model actually built in Phases 0-3, where each Activity owns a private TechnologyDef chain gated on (so far) a single category. `TechnologyDef.knowledge_requirements` was already a generic multi-category dict, so nothing built needs to change to SUPPORT multi-domain gating — this is purely about whether a Technology belongs to one Activity's private ladder (current) or a shared catalog category spanning several Activities (the new doc's framing).

**Deliberately not decided yet** — with only one Activity (Resource Survey) built, both models are indistinguishable in code. Decide this when authoring the SECOND Activity's instrument chain, not before.

Also per this doc: "Robotics," "Computing," and "Engineering" appear as Knowledge Requirements in its Technology Catalog (Part 2) but are not among the 12 defined Knowledge Domains (Part 1) — decided NOT to add them as new Domains. When catalog technologies referencing them are actually authored (Phase 5/6+), map them onto the nearest existing Domain instead.
