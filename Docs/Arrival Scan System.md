# Arrival Scan System

A redesign of how the player interacts with a location's Survey activities,
worked out in a brainstorming conversation about the Science & Knowledge loop
becoming "instantly repetitive." Layered on top of the existing
`Docs/Science and Knowledge System.md` (vision) and
`Docs/Science and Knowledge System - Implementation Roadmap.md` (Phase 2,
"Survey Action") — same relationship `Docs/Buildings System.md` has to that
pair. This doc **replaces** the manual per-activity flow those describe for
Survey-kind activities specifically; Mining, Building construction, and
Selling are unaffected (see "What stays manual" below).

## Status

**Implemented and in active playtesting/iteration** — `ArrivalScanRow.gd`,
wired into `Cockpit.gd`. See "Implementation notes" below for what changed
from this doc's original scoping during that process, including a real
pivot to the trigger model (see "Core concept").

## The problem this solves

The current loop (`ActivitiesPanel`'s gateway/detail/active-ops flow) makes
the player open each Survey activity one at a time, confirm BEGIN, wait for
a flat 4-second timer (`BodyInfoPanel.SCAN_DURATION` — identical for every
activity regardless of body or instrument tier today), then back out and do
the next one. Every body shows the same activity list today (a known,
already-flagged gap — see `ActivitiesPanel.gd`'s own comment: "Availability
isn't gated per-location yet for Surveys... the same list shows at every
destination for now"). The combination — same menu everywhere, repeated
manual triggering, passive waiting — is what reads as "instantly repetitive."
Separately, survey report prose (well-written, but read on every visit) stops
getting read after the first few times a player sees the shape of it.

## Core concept

**Revised after playtesting** — arrival no longer auto-fires anything (see
"Implementation notes"). A single **RUN SCANS** button appears at the top of
the right-side stack whenever at least one owned category has something new
to learn at this body — pressing it fires **every Survey category the player
currently owns an instrument for**, all in parallel, no manual BEGIN per
category. This keeps the player in control of when a visit's information
lands: they can sit and look at the view uninterrupted for as long as they
want, then trigger the whole burst in one press when they're ready. "Scans
initiated" plays once the button is pressed, then the button hides and a
stack of progress cards — one per survey category — fills down the right
side of the Cockpit view (same screen real estate the old ActivitiesPanel
drawer used, now scrollable rather than a slide-out panel — see
"Implementation notes" below). Categories with no owned instrument simply
have no card and don't factor into whether the button appears (extends the
Roadmap's existing "tools gate activities, not the reverse" decision: tools
now also gate which cards/button appear, not just which menu items were
clickable). A body with nothing new to learn anywhere skips the button
entirely and shows its recap cards immediately (see "Revisits" below) —
there's nothing to gate behind a press if nothing would actually start.

**Scan duration is driven by the body's own native rate for that category**
(`NativeRate.geology`/`atmospheric`/`life_sciences`/`astrophysics`/etc. —
already computed for Buildings' knowledge-generation math, now reused for
pacing). A native rate near 0 resolves almost instantly ("No atmosphere" on
an airless asteroid finishes before the player's eye even reaches that bar);
a high native rate takes the longest to resolve. This makes the previously
hidden native-rate number legible ambiently, before any prose is read — the
bar still spinning after the others finished IS the hint that something's
here, the same signal survey text used to have to spell out in words.

Duration must be **capped and curved, not linear** — a rate-100 result
should still land within a few seconds, not literally take 100 units of
time. Something like `duration = min(MAX_SCAN_SECONDS, sqrt(native_rate) * k)`
gets "0 is instant, 100 is the longest bar but still fast" — exact constants
need a playtesting pass once this exists, same as `Buildings.
RATE_TIME_CONSTANT` needed after Geology's own first pass read as invisible.

**Target overall feel:** every scan on every body finishes within ~5 seconds
of arrival. The player's very next decision is Mine / Build / Sell (or
nothing, if the body's genuinely unremarkable) — not "which survey do I run
next."

## Result summaries

Each bar collapses into a short result readout (2-3 lines max) when its scan
finishes:

```
ATMOSPHERIC SURVEY
Significant atmospheric data acquired.
[See More]
```

With an anomaly, the anomaly line leads (same "pinned at top, eye-catching"
precedent `SurveyReportPanel._set_anomaly_banner` already established):

```
ATMOSPHERIC SURVEY
⚠ Atmospheric Anomaly Detected!
Significant atmospheric data acquired.
[See More]
```

**Fixed adjective ladder, reused verbatim across every category** — e.g.
*negligible / minor / significant / exceptional* — rather than bespoke prose
per category per magnitude. The category name varies; the verdict word
doesn't. Once a player has seen "Significant" twice, they're pattern-matching
the word instead of reading a fresh sentence, which is the actual speed win
here. (Exact wordlist TBD — 4-5 tiers feels right, matching the tier-ladder
shape Buildings' own 4-tier construction ladder already uses.)

**Color-code the tier, not just the words** — reuse
`SurveyReportPanel.ANOMALY_COLOR` for the anomaly case, `UITheme.dim` for
negligible (visually reads as skippable before it's read at all),
`UITheme.accent` for significant/exceptional. The row should be sortable by
eye — skippable results fade, notable ones pop — without requiring any
reading.

**"See More" only appears where a rich report exists.** Resource and
Geological Surveys already have rich report classes (`ResourceSurveyData`/
`GeologicalSurveyData`, surfaced via `SurveyReportPanel`'s two `show_*_report`
entry points); Astrophysics/Life Sciences/Atmospheric currently fall back to
`ActivitiesPanel`'s flat label. Where no rich report exists, the one-liner
already *is* the whole story — no "See More" shown, which itself
communicates "nothing more to see" rather than requiring a click to confirm
that. (Building richer report classes for the remaining categories is a
separate, later effort — not required to ship this redesign.)

**Existing survey prose is preserved, not discarded** — it just moves from
mandatory reading (old flow: you had to open the report to know what
happened) to opt-in reading (new flow: the one-liner is enough for routine
results, "See More" is for the player who wants the detail). This is the
same "verdict-first, prose-second" idea, just now literally split across two
UI layers instead of one collapsible section.

**Anomalies are an independent roll layered on top of magnitude, not derived
from it** (per `Docs/Buildings System.md`'s Anomalies section — separate
`roll(low probability)` per (body, category), unrelated to the continuous
native-rate score). This means a fast, near-instant, negligible-rate bar can
still surprise the player with an anomaly — deliberately kept, not
"fixed," since it's what stops the fast bars from being safe to
ignore entirely. Because every owned-instrument category now scans
unconditionally on arrival, anomaly discovery becomes reliable rather than
contingent on the player choosing to run that particular survey — arguably
the actual fix for "anomalies exist but nobody finds them," more than a
side effect.

## Timing/legibility details

* **Stagger simultaneous instant resolutions.** Multiple near-0-native-rate
  categories will legitimately finish in the same frame (a bare asteroid:
  no atmosphere, no life, at minimum). Force a small stagger (~0.2-0.3s)
  between bar resolutions so two "no atmosphere / no life" results don't
  flash past in the same instant and get missed.
* **Anomaly banners must survive even a near-instant scan.** A 0.1s bar with
  a Major anomaly can't just flicker — the banner needs its own minimum
  on-screen dwell/highlight regardless of how fast the underlying scan
  resolved.
* **Row layout:** open question whether categories hold a fixed position
  (spatial memory — "atmo is always bar 3") or anomalies/high-tier results
  get promoted to the front of the row. Fixed position is probably right by
  default (learnable) with a strong per-bar visual highlight for
  anomalies/exceptional results doing the "catch my eye" work instead of
  reordering.

## Revisits

First arrival at a body with anything new to learn shows the RUN SCANS
button; pressing it plays the full animated parallel-scan flourish.
**A revisit where `Research.can_survey_for_new_info` is already false for
every owned category skips straight to a compact, static summary strip** —
no button, no re-scan animation, no wait at all, just the same result lines
already shown to read. This replaces `ActivitiesPanel`'s current per-activity
"Show Results" tile (`_build_show_results_row`) with a single always-visible
recap rather than a menu of individually-tappable stale rows. A better
instrument tier acquired since the last visit brings the button back for
just the category(ies) that now have new information — matching the
existing `can_survey_for_new_info` semantics, still gated behind the
player's own press rather than resolved automatically.

## What stays manual

Deliberately **not** touched by this redesign — these remain player-initiated
actions, not ambient/automatic:

* **Mining** — already continuous and meant to take real time (`Operations.
  _tick_mining`); the player explicitly wants this to stay a deliberate,
  time-costing action they can do other things alongside (travel planning,
  research, selling), not something to compress.
* **Building construction** — a real credits+materials spend decision,
  should stay deliberate.
* **Selling** (Transfer Station / `SellCargoPanel`) — likewise a deliberate
  economic action.

The split: **perception (surveys) becomes fast and one-press instead of
five separate manual flows; every economic/spend decision stays manual.**
This is the core shape of the redesign — not "make everything automatic,"
specifically "make the information-gathering step take one deliberate press
instead of five, and never longer than the player wants to wait for it."

## Implementation notes (first pass, shipped)

* **Layout evolved during build/playtesting**: shipped first as a row across
  the top of the screen, then moved to a scrollable stack down the right
  side (`ArrivalScanRow`, `TOP_MARGIN`/`RIGHT_MARGIN`/`BOTTOM_MARGIN`
  matching the old drawer's own proven-good margins) — reads better with up
  to 5 cards' worth of real content (materials lists, anomaly banners,
  buttons) than a fixed-height horizontal row did.
* **`ActivitiesPanel` was deleted entirely**, not kept as a Mining-only
  drawer as originally scoped above — its Survey rows became dead code, and
  Mining's own UI split into two pieces instead: `MiningOperationsPanel`
  (the deposit-list gateway, now a standalone popup opened directly from
  the scan card's inline "Mine" button) and `MiningStatusStrip` (a new
  small bottom-right corner readout, visible only while mining is actually
  RUNNING — yield/remaining%/STOP). The command menu's OPERATIONS leaf is
  gone with it (5 chips now, not 6).
* **Duration curve**: `Operations._scan_duration_for`, `MIN_SCAN_SECONDS =
  0.3`, `MAX_SCAN_SECONDS = 4.0`, linear on the clamped 0-100 rate (not the
  sqrt-style curve floated above) — first pass, not yet playtested against
  a real body roster.
* **Tier wordlist locked for now**: negligible (<15) / minor (<40) /
  significant (<70) / exceptional (>=70) — thresholds are a first pass.
* **Resource Survey**: flat `RESOURCE_SCAN_SECONDS = 1.0`, result renders as
  a materials list + inline Mine button, exactly as scoped.
  `NativeRate.ANOMALY_TYPES` gained an `"atmospheric"` entry (was missing).
* **Cost question resolved as originally expected**: Surveys are still free
  (time-only), so auto-firing everything on arrival needed no gating beyond
  `can_start`/`can_survey_for_new_info`.
* **Rich report coverage gap still open** — Astrophysics/Life Sciences/
  Atmospheric still have no `SurveyReportPanel`-style detail view, "See
  More" still doesn't exist for them. Unchanged from the original scoping
  above.
* **Audio**: `AudioManager.scans_complete()`/the shared `survey` ambient loop
  are burst-scoped (start/stop once per arrival, via `ArrivalScanRow`), not
  per-category — firing either once per bar was the first thing that read as
  broken in play (VO repeating 5x, ambient loop restarting/cutting itself out
  from under still-running bars). The one-shot start chirp/completion ding
  stay per-category; only the sustained loop and the two spoken lines
  (`scans_initiated()`/`scans_complete()`) are batched. The apparent "VO
  spam" bug turned out to be a red herring twice over: the batching logic
  itself was correct (proved via debugger — it only ever fired once), and
  what was actually repeating was `AudioManager.survey_complete()`, the
  per-bar SFX ding, which had a real spoken VO file accidentally placed in
  `Assets/sfx/` under the same name the ding used. Renamed the spoken-line
  functions/asset keys to `scans_initiated`/`scans_complete` afterward so the
  VO and SFX cues can never share a name/folder collision again.

## Resolved — collapse/hide affordance became RUN SCANS

The open question above (bring back some form of the old drawer's collapse/
tab so the player can tuck the whole stack away and just look at the view)
got resolved differently than either option it posed: instead of a
show/hide TOGGLE on top of auto-fire behavior, arrival stopped auto-firing
at all. A **RUN SCANS** button (`ArrivalScanRow._run_scans_button`) sits at
the top of the stack — same slot the topmost card would occupy — whenever
there's anything new to learn, and nothing starts until the player presses
it (see the revised "Core concept" above). This gets the same outcome the
open question wanted (arrival never forces anything on the player) with a
mechanism that also solves a second problem noted early in this doc's
design conversation: a body with a genuinely high native rate could
previously auto-start a multi-second scan the instant you arrived, even if
you only meant to glance around — now that's always the player's own
choice. `refresh_for_arrival` still auto-shows anything already RUNNING
(reattaching after a mid-scan departure) and any pure recap (nothing new
anywhere) immediately, with no button — neither of those involves
auto-*starting* anything, so there was nothing to gate in the first place.
