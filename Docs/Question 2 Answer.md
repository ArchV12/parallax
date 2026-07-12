# Science Progression Architecture

## Design Decision

After reviewing the science progression system, the decision is to make the progression **hand-authored but data-driven**.

This provides the flexibility of external data while ensuring the scientific progression remains intentionally designed rather than procedurally generated.

---

# Design Philosophy

The progression of scientific discovery is one of the core gameplay systems of **The Parallax Initiative**.

These discoveries represent entirely new scientific capabilities—not simple numerical upgrades.

For this reason, the progression itself should be authored by hand.

Example:

## Resource Survey

* Basic Spectrometer

  * Detect common elements

* Advanced Spectrometer

  * Detect common ores

* Deep Penetration Scanner

  * Detect rare elements

* Quantum Mineral Imager

  * Detect trace elements

* Exotic Matter Resonator

  * Detect exotic materials

Each stage represents a meaningful expansion of scientific capability rather than a simple increase in efficiency.

---

# Scientific Instruments Instead of "Tiers"

Rather than exposing generic Tier I, Tier II, Tier III terminology, each activity progresses through increasingly advanced scientific instruments.

Example:

## Biological Survey

* Basic Bioscanner
* Advanced Microbial Analyzer
* Xenobiological Sequencer
* Ecosystem Mapping Array
* Evolutionary Genomics Laboratory

This makes progression feel grounded in scientific advancement instead of abstract RPG levels.

---

# Data Organization

The system should consist of three independent layers.

## 1. Activity Definitions

Hand-authored.

Very small.

Approximately 12 permanent activities.

Example:

* Geological Survey
* Resource Survey
* Atmospheric Survey
* Biological Survey
* Radiation Survey
* Anomaly Investigation

Activities never change throughout the game.

---

## 2. Scientific Instrument Progression

Hand-authored.

Each activity has its own sequence of instruments.

The number of instruments does **not** need to be identical across all activities.

For example:

* Resource Survey may have 5 instruments.
* Physics Survey may eventually have 8.
* Xenological Survey may only have 4.

The progression exists because it makes sense scientifically—not because every category must contain the same number of levels.

---

## 3. Technology Unlock Definitions

Data-driven.

Potentially hundreds of technologies.

Each technology contains:

* Name
* Knowledge requirements
* Required prototype components
* Resulting capabilities
* Purchase availability
* Unlock text
* Flavor description

Example:

```json
{
  "technology": "Advanced Microbial Analyzer",
  "requires": {
    "biology": 150,
    "atmosphere": 80,
    "hydrology": 60
  }
}
```

This data should live outside the codebase (JSON, YAML, etc.) so balancing and expansion never require gameplay code changes.

---

# Activity Data Example

```json
{
  "activity": "Resource Survey",
  "knowledgeCategory": "Resource",
  "technologies": [
    {
      "name": "Basic Spectrometer",
      "capabilities": [
        "Detect Common Elements"
      ]
    },
    {
      "name": "Advanced Spectrometer",
      "requires": {
        "resource": 120
      },
      "capabilities": [
        "Detect Common Ores"
      ]
    }
  ]
}
```

The game code understands **how** a Resource Survey works.

The data defines **what each instrument is capable of discovering.**

---

# Separation of Responsibilities

## Gameplay Code

Responsible for:

* Performing surveys
* Calculating scan results
* Applying instrument capabilities
* Awarding Knowledge
* Displaying results

---

## Data

Responsible for:

* Activities
* Scientific instruments
* Unlock requirements
* Prototype recipes
* Knowledge thresholds
* Technology descriptions
* Capability definitions

---

## Game Design

Responsible for:

* Scientific progression
* Order of discoveries
* Unlock pacing
* Cross-discipline requirements
* Overall player experience

These are intentional design decisions and should never be procedurally generated.

---

# Why This Approach

This architecture provides several advantages:

* Scientific progression remains meaningful and intentionally designed.
* Balancing can occur without changing gameplay code.
* AI tools can easily add, modify, or rebalance technologies by editing data files.
* Activities remain simple while technologies can expand almost indefinitely.
* The system scales naturally as the game grows.

Most importantly, the progression feels like genuine scientific advancement rather than arbitrary level increases.

The player is not simply obtaining stronger equipment.

Humanity is inventing entirely new ways to understand the universe.
