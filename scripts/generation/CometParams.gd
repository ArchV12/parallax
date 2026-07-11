class_name CometParams
extends RefCounted

# Input knobs for CometGenerator. Icy, irregular nucleus (like an asteroid,
# but a much darker "dirty snowball" crust) wrapped in a coma, trailing a
# tail. Which way the tail points is a scene-relative fact ("away from the
# star") the generator has no way to know — the viewer orients it after
# generate() returns.

var seed_value: int = 0  # named to avoid shadowing the built-in seed() function
var radius: float = 0.1          # nucleus radius — comets are tiny, like asteroids
var irregularity: float = 0.6    # nucleus base-shape deformation, same technique as AsteroidGenerator
var crater_density: float = 0.3
var crater_size: float = 0.32    # MAXIMUM crater radius as a fraction of body radius — power-law distributed below it, see CraterField.make
var crater_depth: float = 0.06
var coma_size: float = 0.6       # coma shell size/intensity around the nucleus
var tail_length: float = 0.6     # tail length, scaled by nucleus radius
var tail_width: float = 0.4      # tail flare width at its far end
var detail: int = 4
