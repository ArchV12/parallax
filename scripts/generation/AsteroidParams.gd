class_name AsteroidParams
extends RefCounted

# Input knobs for AsteroidGenerator. Small airless rocky body whose BASE
# SHAPE is irregular, not just lightly bumped like a moon — real asteroids
# are lumpy precisely because they're too small for self-gravity to round
# them out.

var seed_value: int = 0  # named to avoid shadowing the built-in seed() function
var radius: float = 0.12       # much smaller than moons by default
var irregularity: float = 0.5  # amplitude of the base-shape ridged noise — how far from spherical
var elongation: float = 0.3    # directional stretch — 0 = none, higher = peanut/elongated silhouette
var crater_density: float = 0.5
var crater_size: float = 0.35  # MAXIMUM crater radius as a fraction of body radius (power-law distributed below it, see CraterField.make) — proportionally bigger than a moon's, since asteroids are tiny
var crater_depth: float = 0.08
var detail: int = 4            # icosphere subdivisions (3..6)
