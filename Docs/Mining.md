# The Parallax Initiative
## Mining Activity Design (First Pass)

## Core Philosophy

Mining is fundamentally different from scientific surveys.

Scientific activities answer:

> **"What do we learn?"**

Mining answers:

> **"What do we extract?"**

Mining is an industrial operation. It primarily rewards **resources**, not Knowledge Points.

---

# Prerequisite

Mining is **not** available immediately upon arriving at a location.

The player must first complete a **Resource Survey**, which identifies available deposits.

Example:

```text
RESOURCE SURVEY COMPLETE

Detected Deposits

• Iron Deposit
• Water Ice Deposit
• Titanium Trace Deposit
```

Only after deposits have been discovered does Mining become available.

---

# Mining Activity Screen

Rather than simply clicking "Mine," the Mining screen is focused on selecting a discovered deposit.

Example:

```text
══════════════════════════════════
MINING OPERATIONS

Target: Luna

Available Deposits

Iron Deposit
Abundance: High

Water Ice Deposit
Abundance: Moderate

Titanium Deposit
Abundance: Trace

══════════════════════════════════
```

The player selects a deposit to inspect.

---

# Deposit Details

Selecting a deposit displays its operational information.

Example:

```text
══════════════════════════════════
IRON DEPOSIT

Estimated Yield
High

Extraction Difficulty
Easy

Mining Duration
4:30

Estimated Energy Usage
Low

[ BEGIN EXTRACTION ]

══════════════════════════════════
```

This reinforces the feeling that the player is assigning an industrial operation rather than simply pressing a "Mine" button.

---

# Mining In Progress

Once started, mining behaves like every other timed activity.

Example:

```text
══════════════════════════════════
IRON EXTRACTION

███████░░░░

Progress
72%

Remaining
01:12

Current Yield
Iron Ore x18

[Cancel]

══════════════════════════════════
```

The player may leave this screen while mining continues in the background.

---

# Mining Complete

Example:

```text
══════════════════════════════════
EXTRACTION COMPLETE

Iron Ore +25

Deposit Remaining
82%

══════════════════════════════════
```

---

# Deposits Instead of Global Resources

The game should think in terms of **deposits**, not global planetary resource pools.

Instead of:

> The Moon contains 500 Iron.

Think:

```text
Iron Deposit Alpha
Richness: High

Water Ice Deposit Bravo
Richness: Moderate

Titanium Deposit Charlie
Richness: Trace
```

Each deposit has its own remaining richness.

The save game only needs to remember how much of each discovered deposit has been extracted.

---

# Deposit Exhaustion

Deposits gradually become depleted.

Example:

```text
Iron Deposit Alpha

Richness

██████████
```

After repeated mining:

```text
Iron Deposit Alpha

Richness

███░░░░░░░
```

Mining remains possible, but yields decrease over time.

---

# Future Progression

Improved scanners should enhance existing deposits rather than simply revealing entirely new ones.

Example:

Initial Resource Survey:

```text
Iron Deposit Alpha
Surface Deposit
```

Later, after obtaining a Deep Resource Scanner:

```text
Iron Deposit Alpha

Surface Deposit
Complete

Deep Vein
Detected
```

Technology increases humanity's understanding of known locations, encouraging players to revisit earlier discoveries.

---

# Future Mining Choices (Later Game)

Mining is an ideal candidate for introducing operational decisions.

Example:

```text
Extraction Method

○ Rapid Extraction
Yield: Medium
Power: High
Duration: Short

○ Standard Extraction
Yield: High
Power: Medium
Duration: Medium

○ Precision Extraction
Yield: Very High
Power: Low
Duration: Long
```

These options should not exist initially but provide meaningful progression later in the game.

---

# Design Summary

- Mining is an industrial activity, not a scientific one.
- Resource Surveys must be completed before mining is possible.
- Players mine **discovered deposits**, not entire planets.
- Mining rewards materials rather than Knowledge Points.
- Deposits persist, can be depleted, and improve with better scanning technology.
- Mining operations follow the same asynchronous activity framework as surveys, allowing them to continue while the player performs other tasks.