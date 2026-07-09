class_name PlanetParams
extends RefCounted

# Input knobs for PlanetGenerator. The Cosmic Forge drives these from sliders;
# the eventual game will derive them from system-generation data. Same seed +
# same knobs must always produce the same planet.

var seed_value: int = 0  # named to avoid shadowing the built-in seed() function
var radius: float = 1.0            # display units
var continent_scale: float = 1.0   # noise frequency multiplier — higher = more, smaller landmasses
var terrain_height: float = 0.06   # max displacement as a fraction of radius
var roughness: float = 0.5         # fractal gain — higher = craggier detail
var ocean_level: float = 0.5       # 0 = dry world, 1 = water world
var atmosphere: float = 0.35       # 0 = airless, 1 = thick haze
var atmo_falloff: float = 1.5      # glow falloff exponent — higher hugs the limb, lower spreads outward
var detail: int = 5                # icosphere subdivisions (3..6)
