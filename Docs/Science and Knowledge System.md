# The Parallax Initiative

## Science & Knowledge Progression System

**Version:** Vision Draft 1.0

---

# Overview

The Parallax Initiative is not a game about collecting loot or grinding experience points.

It is a game about advancing human knowledge.

The player is not a scientist performing research inside a laboratory. Instead, they are humanity's explorer—its eyes and hands at the frontier of the unknown.

Every discovery is transmitted back to Earth, where humanity's scientists analyze the findings and develop new technologies.

The player's role is to push the boundary of exploration.

Humanity's role is to transform discoveries into progress.

---

# Core Gameplay Loop

```text
Travel to a Location
        ↓
Perform Scientific Activities
        ↓
Transmit Scientific Reports to Earth
        ↓
Human Knowledge Increases
        ↓
Scientific Milestones Reached
        ↓
New Prototype Technology Developed
        ↓
Craft the First Prototype
        ↓
Transmit Blueprint to Earth
        ↓
Humanity Begins Mass Production
        ↓
Future Units Become Purchasable
        ↓
Explore Further
```

This loop repeats throughout the entire game.

> **Note:** "Perform Scientific Activities" at a location — originally one
> manually-triggered Survey at a time — has been redesigned. See
> `Docs/Arrival Scan System.md` for the current design: arrival auto-fires
> every owned-instrument Survey in parallel, with scan duration itself
> driven by the body's native rate for that category. The loop shape above
> (Travel → Activities → Transmit → Knowledge → Milestones → ...) is
> unchanged; only how "Perform Scientific Activities" plays out at a
> location is different now.

---

# Design Philosophy

The universe itself does not become more interesting because planets change.

The universe becomes more interesting because humanity develops better tools to understand it.

A planet visited early in the game may reveal completely new discoveries decades later after scientific instruments have improved.

Exploration is driven by increasing scientific capability rather than an endless stream of increasingly exotic planets.

---

# Scientific Activities

Activities are permanent.

The player never unlocks new activities.

Instead, the tools used for each activity improve over time, allowing deeper and more detailed discoveries.

Each activity corresponds directly to one Knowledge Category.

| Activity              | Knowledge Category          |
| --------------------- | --------------------------- |
| Geological Survey     | Geological Knowledge        |
| Resource Survey       | Resource Knowledge          |
| Atmospheric Survey    | Atmospheric Knowledge       |
| Hydrological Survey   | Hydrological Knowledge      |
| Biological Survey     | Biological Knowledge        |
| Astronomical Survey   | Astronomical Knowledge      |
| Planetary Survey      | Planetary Science Knowledge |
| Gravitational Survey  | Gravitational Knowledge     |
| Radiation Survey      | Radiation Knowledge         |
| Physics Survey        | Physics Knowledge           |
| Xenological Survey    | Xenological Knowledge       |
| Anomaly Investigation | Anomaly Knowledge           |

---

# Knowledge

Knowledge represents humanity's accumulated scientific understanding.

Knowledge is:

* Permanent
* Never spent
* Always increasing
* Shared across humanity

Completing scientific activities awards Knowledge in their corresponding discipline.

Example:

```text
Biological Survey Complete

+14 Biological Knowledge
```

Knowledge is not an experience point.

It is humanity's growing understanding of the universe.

---

# Scientific Milestones

The player does not manually research technologies.

Research happens automatically as humanity accumulates sufficient knowledge.

When milestone requirements are met, Earth develops new technologies and informs the player.

Example:

```text
══════════════════════════════

EARTH TRANSMISSION

Scientific Milestone Achieved

Combined advances in:

Atmospheric Knowledge
Radiation Knowledge
Physics Knowledge

have enabled development of a

Prototype Plasma Drive.

Blueprint uploaded to your vessel.

══════════════════════════════
```

Unlocks occur naturally through exploration.

---

# Multi-Discipline Requirements

Advanced technologies often require progress in multiple scientific disciplines.

Example:

```text
Prototype Plasma Drive

Requirements

Atmospheric Knowledge ..... 300
Physics Knowledge ......... 250
Radiation Knowledge ....... 180
```

This encourages players to become well-rounded explorers rather than repeatedly performing a single activity.

---

# Activity Progression

Activities remain constant throughout the game.

Only the instruments improve.

Example:

## Resource Survey

### Tier I

* Detect common elements

### Tier II

* Detect common ores

### Tier III

* Detect rare elements

### Tier IV

* Detect trace elements

### Tier V

* Detect exotic materials

The player continues performing a **Resource Survey** for the entire game.

Only the quality of information improves.

---

# Confidence & Resolution

Improved instruments provide both greater detail and greater certainty.

Example:

### Early Game

```text
Life Probability

18%
```

### Mid Game

```text
Organic Compounds Detected

Possible Microbial Life

72% Confidence
```

### Late Game

```text
Extraterrestrial Microbial Life Confirmed

15,327 Species Identified
```

The same activity evolves into a much richer scientific experience.

---

# Revisiting Worlds

Improved scientific equipment naturally encourages revisiting previously explored locations.

Example:

First visit to Europa:

```text
Ice
Rock
```

Decades later:

```text
Water Reservoirs
Organic Carbon
Cryovolcanic Activity
Rare Earth Deposits
Subsurface Microbial Life
```

The world did not change.

Humanity's understanding did.

---

# Prototype Philosophy

Every technology is crafted exactly once.

The player builds the very first working prototype.

Once complete:

1. Blueprint transmitted to Earth.
2. Humanity begins manufacturing.
3. Future copies become available for purchase.

Example:

```text
First Plasma Drive

↓

Craft Prototype

↓

Transmit Blueprint

↓

Earth Manufactures Plasma Drives

↓

Player Purchases Additional Units
```

This makes crafting meaningful without becoming repetitive or grind-heavy.

---

# Research Interface

The player never sees the complete technology tree.

Instead, every Knowledge Category displays only:

* Current Knowledge
* Current Technology Tier
* Next Scientific Milestone
* Requirements for that milestone

Future technologies remain hidden.

Example:

```text
══════════════════════════════

BIOLOGICAL KNOWLEDGE

Current Knowledge

127

Current Capability

Tier II Biological Survey

──────────────────────────────

Next Scientific Milestone

Advanced Microbial Analyzer

Requirements

✓ Biological Knowledge ......150

✓ Atmospheric Knowledge .....80

□ Hydrological Knowledge ....60

Progress

2 / 3 Requirements Met

──────────────────────────────

Future Developments

Unknown

══════════════════════════════
```

This gives players a clear direction while preserving discovery and surprise.

---

# Earth as a Living Civilization

Earth is not simply a shop.

Earth is an active scientific civilization.

Every survey contributes to thousands of researchers working behind the scenes.

Technology is developed by humanity—not by the player alone.

Scientific milestone messages reinforce this relationship.

Example:

```text
Commander,

Recent geological surveys of Europa have completely changed our understanding of cryovolcanic activity.

Our engineering division has completed a prototype Deep Core Tomography Scanner.

Specifications have been uploaded to your vessel.

— Earth Science Directorate
```

---

# Guiding Principles

* Exploration drives scientific discovery.
* Scientific discovery advances humanity.
* Humanity develops new technology.
* New technology enables deeper exploration.
* Activities remain constant.
* Instruments continually improve.
* Knowledge is permanent.
* Knowledge is never spent.
* Technologies unlock automatically through accumulated knowledge.
* Advanced technologies require multiple scientific disciplines.
* Players are encouraged to revisit previously explored worlds.
* Crafting is meaningful because every technology is prototyped exactly once.
* The player advances civilization rather than simply leveling up a character.

---

# Core Vision

Most exploration games attempt to remain interesting by continually generating new places.

The Parallax Initiative takes the opposite approach.

The universe is already interesting.

What changes is humanity's ability to understand it.

The player is not chasing experience points.

They are expanding the frontier of human knowledge.

Every survey...
Every anomaly...
Every discovery...

...pushes humanity one step farther into the unknown.
