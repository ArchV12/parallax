class_name CanonicalBodyParams
extends RefCounted

# Input knobs for CanonicalBodyGenerator — known, real-world bodies (Earth,
# Mars, Jupiter, ...) rendered from an actual texture instead of
# PlanetGenerator's procedural noise. Radius/atmosphere framing stays
# tunable in the Forge for comparison, but the surface itself is authored
# (a real map), never rolled from a seed.

var body_name: String = "Earth"
var albedo_texture_path: String = "res://Assets/textures/earth/albedo.png"
# Used only if the texture file above hasn't been added yet.
var fallback_color: Color = Color(0.25, 0.35, 0.55)
var radius: float = 1.0
var atmosphere: float = 0.35
var atmo_color: Color = Color(0.55, 0.75, 1.0)
var atmo_falloff: float = 1.5

# Set for Sol only — an emissive, unshaded surface (no day/night side) plus
# a corona shell instead of a lit-from-outside atmosphere. atmosphere/
# atmo_color/atmo_falloff above double as the corona's knobs when this is on.
var self_luminous: bool = false
var emission_energy: float = 1.5

# Saturn's the one canonical body whose defining feature isn't on the
# surface texture at all — 0 = no rings, higher = wider/denser. Same
# RingSystem utility GasGiantGenerator uses.
var rings: float = 0.0
var ring_tint: Color = Color(0.85, 0.75, 0.55)
