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
# surface texture at all. Same RingSystem utility GasGiantGenerator uses,
# but with extent and track count split apart (GasGiantGenerator's single
# "Rings" knob scales both together) — a real ring system's visual size and
# how many separate bands it's made of are independent: Uranus reads as
# essentially one narrow track, Saturn as several packed close (see
# ring.gdshader's organic domain-warp — it does the "looks dense" work
# rather than needing dozens of literal tracks).
var rings: float = 0.0    # 0 = no rings; higher = the system reaches further out
var ring_tracks: int = 8  # how many discrete concentric bands make it up
var ring_tint: Color = Color(0.85, 0.75, 0.55)
# -1 = let RingSystem roll a random tilt; a curated body should instead pass
# its real axial tilt (e.g. Saturn's 26.7°) so it's authored, not rolled.
var ring_tilt_degrees: float = -1.0
