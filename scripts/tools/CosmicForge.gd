extends Node3D

# The Cosmic Forge — dev tool for honing the celestial body generators
# (GDD §15, "The Galactic Forge"). Pick a body type, tweak generation knobs,
# and hit Generate to roll new random bodies. Slider changes re-sculpt the
# CURRENT seed live, so one body can be tuned and compared; Generate (or R)
# rolls a fresh seed.
#
# Body Type is a flat list of sibling kinds (Rocky Planet, Water World, Gas
# Giant, Ice Giant, Moon, Asteroid, Star) rather than a "Planet" category
# with sub-types — a gas giant is no more "a planet" than a moon is, so each
# entry gets its own knob set and generator. Rocky Planet and Water World
# happen to share PlanetGenerator (Water World is really just a wetter
# preset of the same pipeline); Gas Giant and Ice Giant share
# GasGiantGenerator; Moon and Asteroid each get their own generator but share
# cratering logic (CraterField) — an asteroid additionally deforms its base
# shape, since real ones are too small for gravity to round them out. Star is
# self-luminous, unshaded, no day/night side at all.
#
# Comet exists as a full generator (CometGenerator/CometParams,
# shaders/comet_tail.gdshader) but is pulled out of BODY_TYPE_NAMES below, so
# it's unreachable from the picker — a static tapered-cone mesh reads as "a
# cone stuck on a sphere," not gas. A convincing tail needs particles, which
# is real additional work; the generator, the Tail/Atmosphere dispatch below,
# and the nucleus-only idle-spin case in _process() are all left intact so
# re-adding "Comet" to BODY_TYPE_NAMES is enough to bring it back once that's
# built (or to leave it out for good — the game may not need comets at all).
#
# Mercury/Venus/Earth/Mars/Luna/Jupiter/Saturn/Uranus/Neptune/Pluto are a
# different kind of sibling entry: known/canonical bodies, not rolled ones —
# CanonicalBodyGenerator maps a real texture onto a UV sphere instead of
# sculpting terrain from noise. Any further real body follows the same
# pattern: a BodyType + knob set + _build_canonical_params(...) call.

const FONT_SIZE_SMALL := 14

const ZOOM_STEP := 0.9
# Low enough to get nose-to-surface on the smallest asteroids/moons for
# close crater/shape inspection.
const MIN_DISTANCE := 0.3
const MAX_DISTANCE := 40.0
const ORBIT_SENSITIVITY := 0.008
const PAN_SENSITIVITY := 0.0012
const BODY_SPIN := 0.05  # rad/s — slow idle rotation

enum BodyType {
	ROCKY_PLANET, WATER_WORLD, GAS_GIANT, ICE_GIANT, MOON, ASTEROID, STAR,
	SOL, MERCURY, VENUS, EARTH, MARS, LUNA, JUPITER, SATURN, URANUS, NEPTUNE, PLUTO,
	COMET,
}

# Comet intentionally omitted — see the class-level comment above. Luna is
# labeled by its proper name, not "Moon" — that label is already taken by
# the generic procedural moon generator above, and the picker would be
# ambiguous with two entries both called "Moon". Sol is likewise its proper
# name, not "Star" — that label is already the procedural self-luminous type.
const BODY_TYPE_NAMES := [
	"Rocky Planet", "Water World", "Gas Giant", "Ice Giant", "Moon", "Asteroid", "Star",
	"Sol", "Mercury", "Venus", "Earth", "Mars", "Luna", "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto",
]

# name: [label, min, max, default, is_int]
const ROCKY_KNOBS: Array = [
	["radius",          ["Radius",          0.4, 2.5,  1.0,  false]],
	["continent_scale", ["Continent Scale", 0.4, 3.0,  1.0,  false]],
	["terrain_height",  ["Terrain Height",  0.01, 0.15, 0.06, false]],
	["roughness",       ["Roughness",       0.3, 0.7,  0.5,  false]],
	["ocean_level",     ["Ocean Level",     0.0, 1.0,  0.35, false]],
	["atmosphere",      ["Atmosphere",      0.0, 1.0,  0.35, false]],
	["atmo_falloff",    ["Atmo Falloff",    0.5, 3.0,  1.5,  false]],
	["detail",          ["Mesh Detail",     3.0, 6.0,  5.0,  true]],
]

# Same pipeline as Rocky, just wetter by default — and Ocean Level can't be
# dialed down into a dry rock while labeled Water World.
const WATER_WORLD_KNOBS: Array = [
	["radius",          ["Radius",          0.4, 2.5,  1.0,  false]],
	["continent_scale", ["Continent Scale", 0.4, 3.0,  0.7,  false]],
	["terrain_height",  ["Terrain Height",  0.01, 0.15, 0.05, false]],
	["roughness",       ["Roughness",       0.3, 0.7,  0.5,  false]],
	["ocean_level",     ["Ocean Level",     0.6, 1.0,  0.85, false]],
	["atmosphere",      ["Atmosphere",      0.0, 1.0,  0.45, false]],
	["atmo_falloff",    ["Atmo Falloff",    0.5, 3.0,  1.5,  false]],
	["detail",          ["Mesh Detail",     3.0, 6.0,  5.0,  true]],
]

# Jupiter/Saturn — strong banding by default.
const GAS_GIANT_KNOBS: Array = [
	["radius",         ["Radius",         0.8, 3.0, 1.6,  false]],
	["band_scale",     ["Band Scale",     0.5, 3.0, 1.2,  false]],
	["turbulence",     ["Turbulence",     0.0, 1.0, 0.4,  false]],
	["storminess",     ["Storminess",     0.0, 1.0, 0.35, false]],
	["band_contrast",  ["Band Contrast",  0.0, 1.0, 1.0,  false]],
	["atmosphere",     ["Atmosphere",     0.0, 1.0, 0.15, false]],
	["atmo_falloff",   ["Atmo Falloff",   0.5, 3.0, 1.2,  false]],
	["rings",          ["Rings",          0.0, 1.0, 0.0,  false]],
]

# Uranus/Neptune — calmer and nearly featureless by default; Band Contrast
# starts low but is still draggable up to a full Jupiter-style look.
const ICE_GIANT_KNOBS: Array = [
	["radius",         ["Radius",         0.8, 3.0, 1.6,  false]],
	["band_scale",     ["Band Scale",     0.5, 3.0, 1.2,  false]],
	["turbulence",     ["Turbulence",     0.0, 1.0, 0.2,  false]],
	["storminess",     ["Storminess",     0.0, 1.0, 0.1,  false]],
	["band_contrast",  ["Band Contrast",  0.0, 1.0, 0.12, false]],
	["atmosphere",     ["Atmosphere",     0.0, 1.0, 0.15, false]],
	["atmo_falloff",   ["Atmo Falloff",   0.5, 3.0, 1.2,  false]],
	["rings",          ["Rings",          0.0, 1.0, 0.0,  false]],
]

# Airless, cratered — no atmosphere or ocean concept applies at all.
const MOON_KNOBS: Array = [
	["radius",            ["Radius",            0.15, 1.0,  0.35, false]],
	["surface_roughness", ["Surface Roughness", 0.0,  0.08, 0.02, false]],
	["crater_density",    ["Crater Density",    0.0,  1.0,  0.5,  false]],
	["crater_size",       ["Crater Size",       0.05, 0.35, 0.18, false]],
	["crater_depth",      ["Crater Depth",      0.01, 0.15, 0.05, false]],
	["detail",            ["Mesh Detail",       3.0,  6.0,  4.0,  true]],
]

# Irregular base shape (not a bumped sphere) plus the same cratering as Moon.
const ASTEROID_KNOBS: Array = [
	["radius",         ["Radius",         0.03, 0.3,  0.12, false]],
	["irregularity",   ["Irregularity",   0.0,  1.2,  0.5,  false]],
	["elongation",     ["Elongation",     0.0,  1.5,  0.3,  false]],
	["crater_density", ["Crater Density", 0.0,  1.0,  0.5,  false]],
	["crater_size",    ["Crater Size",    0.05, 0.4,  0.22, false]],
	["crater_depth",   ["Crater Depth",   0.01, 0.15, 0.08, false]],
	["detail",         ["Mesh Detail",    3.0,  6.0,  4.0,  true]],
]

# Self-luminous — no terrain/ocean/atmosphere-day-side concepts apply.
# Temperature is Kelvin, driving color from red dwarf through blue-white.
const STAR_KNOBS: Array = [
	["radius",          ["Radius",          0.6,    3.0,     1.4,    false]],
	["temperature",     ["Temperature (K)", 3000.0, 30000.0, 5800.0, true]],
	["turbulence",      ["Turbulence",      0.0,    1.0,     0.4,    false]],
	["spot_activity",   ["Spot Activity",   0.0,    1.0,     0.15,   false]],
	["corona",          ["Corona",          0.0,    1.0,     0.5,    false]],
	["corona_falloff",  ["Corona Falloff",  0.5,    3.0,     1.5,    false]],
]

# Canonical/known bodies are curated, not rolled — no seed-driven knobs.
# Only framing (size on screen, atmosphere thickness) is adjustable; the
# surface itself is a real texture (see CanonicalBodyGenerator). Radius
# defaults are real Earth-relative ratios (Earth = 1.0); atmosphere defaults
# reflect each body's real atmosphere, from Venus' thick haze to airless
# Mercury/Luna/Pluto.

# Sol is self-luminous (see CanonicalBodyGenerator) — "Atmosphere" here is
# really the corona, same range/defaults as the procedural Star's corona
# knobs. Real Sol is ~109x Earth's radius, far past every other body's
# range here; kept in Star's viewing-friendly range instead of to scale.
const SOL_KNOBS: Array = [
	["radius",       ["Radius",       0.6, 3.0, 1.4, false]],
	["atmosphere",   ["Corona",       0.0, 1.0, 0.5, false]],
	["atmo_falloff", ["Corona Falloff", 0.5, 3.0, 1.5, false]],
]

const MERCURY_KNOBS: Array = [
	["radius",       ["Radius",       0.1, 1.0, 0.38, false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0, 0.0,  false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0, 1.5,  false]],
]

const VENUS_KNOBS: Array = [
	["radius",       ["Radius",       0.4, 1.5, 0.95, false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0, 0.9,  false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0, 1.5,  false]],
]

const EARTH_KNOBS: Array = [
	["radius",       ["Radius",       0.4, 2.5, 1.0,  false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0, 0.35, false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0, 1.5,  false]],
]

# Mars' real atmosphere is ~0.6% the density of Earth's — default stays low
# and dusty rather than reusing Earth's thick-haze default.
const MARS_KNOBS: Array = [
	["radius",       ["Radius",       0.4, 2.5, 0.53, false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0, 0.08, false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0, 1.5,  false]],
]

const LUNA_KNOBS: Array = [
	["radius",       ["Radius",       0.1, 0.6, 0.27, false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0, 0.0,  false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0, 1.5,  false]],
]

const JUPITER_KNOBS: Array = [
	["radius",       ["Radius",       5.0, 15.0, 10.97, false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0,  0.25,  false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0,  1.2,   false]],
]

# The rings are the whole point, so they default on, not at 0 like
# GasGiantParams.rings does — this is Saturn, not "a gas giant that could
# optionally have rings."
const SATURN_KNOBS: Array = [
	["radius",       ["Radius",       4.0, 14.0, 9.14, false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0,  0.25, false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0,  1.2,  false]],
	["rings",        ["Rings",        0.0, 1.0,  0.75, false]],
]

const URANUS_KNOBS: Array = [
	["radius",       ["Radius",       2.0, 6.0, 3.98, false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0, 0.2,  false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0, 1.2,  false]],
]

const NEPTUNE_KNOBS: Array = [
	["radius",       ["Radius",       2.0, 6.0, 3.86, false]],
	["atmosphere",   ["Atmosphere",   0.0, 1.0, 0.2,  false]],
	["atmo_falloff", ["Atmo Falloff", 0.5, 3.0, 1.2,  false]],
]

# Pluto's atmosphere is so thin it's negligible at this scale.
const PLUTO_KNOBS: Array = [
	["radius",       ["Radius",       0.05, 0.4, 0.19, false]],
	["atmosphere",   ["Atmosphere",   0.0,  1.0, 0.0,  false]],
	["atmo_falloff", ["Atmo Falloff", 0.5,  3.0, 1.5,  false]],
]

# Icy irregular nucleus (same deformation technique as Asteroid) + coma +
# tail. Tail direction is patched in by _regenerate(), not this knob set.
const COMET_KNOBS: Array = [
	["radius",         ["Radius",         0.03, 0.3,  0.1,  false]],
	["irregularity",   ["Irregularity",   0.0,  1.2,  0.6,  false]],
	["crater_density", ["Crater Density", 0.0,  1.0,  0.3,  false]],
	["crater_size",    ["Crater Size",    0.05, 0.4,  0.2,  false]],
	["crater_depth",   ["Crater Depth",   0.01, 0.15, 0.06, false]],
	["coma_size",      ["Coma Size",      0.0,  1.0,  0.6,  false]],
	["tail_length",    ["Tail Length",    0.0,  1.0,  0.6,  false]],
	["tail_width",     ["Tail Width",     0.0,  1.0,  0.4,  false]],
	["detail",         ["Mesh Detail",    3.0,  6.0,  4.0,  true]],
]

var _pivot: Node3D
var _camera: Camera3D
var _yaw := 0.6
var _pitch := -0.25
var _distance := 4.0
var _orbiting := false
var _panning := false

var _body: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var _body_type: BodyType = BodyType.ROCKY_PLANET
var _seed: int
var _seed_label: Label
var _knob_container: VBoxContainer
var _sliders: Dictionary = {}  # knob name -> HSlider
var _regen_timer: Timer


func _ready() -> void:
	_regen_timer = Timer.new()
	_regen_timer.one_shot = true
	_regen_timer.wait_time = 0.25
	_regen_timer.timeout.connect(_regenerate)
	add_child(_regen_timer)
	_build_environment()
	_build_camera()
	_build_ui()
	_roll_new_seed()
	MusicManager.play_cosmic_forge()


func _process(delta: float) -> void:
	if _body == null:
		return
	if _body_type == BodyType.COMET:
		# Spin only the nucleus — the coma/tail must stay oriented away from
		# the star regardless of how the nucleus tumbles.
		var nucleus := _body.get_node_or_null("Body")
		if nucleus != null:
			nucleus.rotate_y(BODY_SPIN * delta)
	else:
		_body.rotate_y(BODY_SPIN * delta)


# --- Generation ---

func _knobs_for_type(t: BodyType) -> Array:
	match t:
		BodyType.WATER_WORLD:
			return WATER_WORLD_KNOBS
		BodyType.GAS_GIANT:
			return GAS_GIANT_KNOBS
		BodyType.ICE_GIANT:
			return ICE_GIANT_KNOBS
		BodyType.MOON:
			return MOON_KNOBS
		BodyType.ASTEROID:
			return ASTEROID_KNOBS
		BodyType.STAR:
			return STAR_KNOBS
		BodyType.COMET:
			return COMET_KNOBS
		BodyType.SOL:
			return SOL_KNOBS
		BodyType.MERCURY:
			return MERCURY_KNOBS
		BodyType.VENUS:
			return VENUS_KNOBS
		BodyType.EARTH:
			return EARTH_KNOBS
		BodyType.MARS:
			return MARS_KNOBS
		BodyType.LUNA:
			return LUNA_KNOBS
		BodyType.JUPITER:
			return JUPITER_KNOBS
		BodyType.SATURN:
			return SATURN_KNOBS
		BodyType.URANUS:
			return URANUS_KNOBS
		BodyType.NEPTUNE:
			return NEPTUNE_KNOBS
		BodyType.PLUTO:
			return PLUTO_KNOBS
		_:
			return ROCKY_KNOBS


func _on_body_type_selected(idx: int) -> void:
	_body_type = idx as BodyType
	# Glow/bloom is only meaningful for self-luminous bodies (the emissive
	# surface needs it to actually bloom instead of reading as flat-bright).
	_env.glow_enabled = (_body_type == BodyType.STAR or _body_type == BodyType.SOL)
	_rebuild_knobs()
	_roll_new_seed()


func _rebuild_knobs() -> void:
	for child in _knob_container.get_children():
		child.queue_free()
	_sliders.clear()
	for knob: Array in _knobs_for_type(_body_type):
		_add_knob_row(_knob_container, knob[0] as String, knob[1] as Array)


func _roll_new_seed() -> void:
	_seed = randi()
	_regen_timer.stop()  # cancel any pending slider debounce — we regen now
	_regenerate()


# Random button: scatter every slider relevant to the current type across
# its range, then roll a new seed.
func _randomize_all() -> void:
	for knob: Array in _knobs_for_type(_body_type):
		var spec: Array = knob[1]
		var slider: HSlider = _sliders[knob[0]]
		slider.value = randf_range(spec[1] as float, spec[2] as float)
	_roll_new_seed()


func _regenerate() -> void:
	if _body != null:
		_body.queue_free()
		_body = null

	match _body_type:
		BodyType.GAS_GIANT, BodyType.ICE_GIANT:
			var params := GasGiantParams.new()
			params.seed_value = _seed
			params.radius = _sliders["radius"].value
			params.band_scale = _sliders["band_scale"].value
			params.turbulence = _sliders["turbulence"].value
			params.storminess = _sliders["storminess"].value
			params.band_contrast = _sliders["band_contrast"].value
			params.atmosphere = _sliders["atmosphere"].value
			params.atmo_falloff = _sliders["atmo_falloff"].value
			params.rings = _sliders["rings"].value
			params.ice = (_body_type == BodyType.ICE_GIANT)
			_body = GasGiantGenerator.generate(params)
		BodyType.MOON:
			var params := MoonParams.new()
			params.seed_value = _seed
			params.radius = _sliders["radius"].value
			params.surface_roughness = _sliders["surface_roughness"].value
			params.crater_density = _sliders["crater_density"].value
			params.crater_size = _sliders["crater_size"].value
			params.crater_depth = _sliders["crater_depth"].value
			params.detail = int(_sliders["detail"].value)
			_body = MoonGenerator.generate(params)
		BodyType.ASTEROID:
			var params := AsteroidParams.new()
			params.seed_value = _seed
			params.radius = _sliders["radius"].value
			params.irregularity = _sliders["irregularity"].value
			params.elongation = _sliders["elongation"].value
			params.crater_density = _sliders["crater_density"].value
			params.crater_size = _sliders["crater_size"].value
			params.crater_depth = _sliders["crater_depth"].value
			params.detail = int(_sliders["detail"].value)
			_body = AsteroidGenerator.generate(params)
		BodyType.STAR:
			var params := StarParams.new()
			params.seed_value = _seed
			params.radius = _sliders["radius"].value
			params.temperature = _sliders["temperature"].value
			params.turbulence = _sliders["turbulence"].value
			params.spot_activity = _sliders["spot_activity"].value
			params.corona = _sliders["corona"].value
			params.corona_falloff = _sliders["corona_falloff"].value
			_body = StarGenerator.generate(params)
		BodyType.COMET:
			var params := CometParams.new()
			params.seed_value = _seed
			params.radius = _sliders["radius"].value
			params.irregularity = _sliders["irregularity"].value
			params.crater_density = _sliders["crater_density"].value
			params.crater_size = _sliders["crater_size"].value
			params.crater_depth = _sliders["crater_depth"].value
			params.coma_size = _sliders["coma_size"].value
			params.tail_length = _sliders["tail_length"].value
			params.tail_width = _sliders["tail_width"].value
			params.detail = int(_sliders["detail"].value)
			_body = CometGenerator.generate(params)
		BodyType.SOL:
			var params := _build_canonical_params(
					"Sol", "sol", Color(1.0, 0.85, 0.55), Color(1.0, 0.75, 0.35))
			params.self_luminous = true
			_body = CanonicalBodyGenerator.generate(params)
		BodyType.MERCURY:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Mercury", "mercury", Color(0.55, 0.52, 0.48), Color(0.6, 0.6, 0.6)))
		BodyType.VENUS:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Venus", "venus", Color(0.80, 0.70, 0.45), Color(0.95, 0.85, 0.55)))
		BodyType.EARTH:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Earth", "earth", Color(0.25, 0.35, 0.55), Color(0.55, 0.75, 1.0)))
		BodyType.MARS:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Mars", "mars", Color(0.60, 0.35, 0.25), Color(0.85, 0.60, 0.45)))
		BodyType.LUNA:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Luna", "moon", Color(0.55, 0.55, 0.58), Color(0.6, 0.6, 0.6)))
		BodyType.JUPITER:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Jupiter", "jupiter", Color(0.80, 0.65, 0.45), Color(0.85, 0.75, 0.55)))
		BodyType.SATURN:
			var params := _build_canonical_params(
					"Saturn", "saturn", Color(0.85, 0.72, 0.48), Color(0.90, 0.80, 0.55))
			params.rings = _sliders["rings"].value
			params.ring_tint = Color(0.80, 0.72, 0.58)
			_body = CanonicalBodyGenerator.generate(params)
		BodyType.URANUS:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Uranus", "uranus", Color(0.55, 0.80, 0.85), Color(0.60, 0.85, 0.90)))
		BodyType.NEPTUNE:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Neptune", "neptune", Color(0.25, 0.35, 0.75), Color(0.35, 0.45, 0.90)))
		BodyType.PLUTO:
			_body = CanonicalBodyGenerator.generate(_build_canonical_params(
					"Pluto", "pluto", Color(0.75, 0.68, 0.60), Color(0.75, 0.70, 0.65)))
		_:
			var params := PlanetParams.new()
			params.seed_value = _seed
			params.radius = _sliders["radius"].value
			params.continent_scale = _sliders["continent_scale"].value
			params.terrain_height = _sliders["terrain_height"].value
			params.roughness = _sliders["roughness"].value
			params.ocean_level = _sliders["ocean_level"].value
			params.atmosphere = _sliders["atmosphere"].value
			params.atmo_falloff = _sliders["atmo_falloff"].value
			params.detail = int(_sliders["detail"].value)
			_body = PlanetGenerator.generate(params)

	add_child(_body)
	_seed_label.text = "Seed: %d" % _seed

	# Point the atmosphere's day-side glow at this scene's sun. (A light's rays
	# travel along -Z of its basis, so +Z is the direction back toward the sun.)
	var atmo := _body.get_node_or_null("Atmosphere") as MeshInstance3D
	if atmo != null:
		(atmo.material_override as ShaderMaterial).set_shader_parameter(
				"sun_dir", _sun.global_basis.z)

	# Comet tails always point away from the star — a scene-relative fact the
	# generator has no way to know, so the Forge orients it here the same way
	# it patches sun_dir onto Atmosphere above.
	var tail := _body.get_node_or_null("Tail") as MeshInstance3D
	if tail != null:
		_orient_tail(tail, _sun.global_basis.z)


# Shared by every canonical-body case above — same three sliders (radius,
# atmosphere, atmo_falloff) feed every known body, just with a different
# texture and color grading per body. atmo_color still gets set even for
# airless bodies (Mercury/Luna/Pluto) in case their Atmosphere slider is
# ever dragged up for fun despite the real body having none.
func _build_canonical_params(body_name: String, texture_subdir: String,
		fallback_color: Color, atmo_color: Color) -> CanonicalBodyParams:
	var params := CanonicalBodyParams.new()
	params.body_name = body_name
	params.albedo_texture_path = "res://Assets/textures/%s/albedo.png" % texture_subdir
	params.fallback_color = fallback_color
	params.atmo_color = atmo_color
	params.radius = _sliders["radius"].value
	params.atmosphere = _sliders["atmosphere"].value
	params.atmo_falloff = _sliders["atmo_falloff"].value
	return params


# Aligns a Tail mesh (built centered at the origin, unrotated, extending
# ±height/2 along its local Y) so its narrow end sits at the nucleus and it
# flares away from the star. sun_dir points FROM the body TOWARD the star
# (same convention atmosphere shaders use); aligning local +Y to it puts the
# narrow "top" end on the sunward side, so translating by -sun_dir*(h/2)
# lands that end exactly at the origin, with the wide "bottom" end trailing
# out in the away-from-star direction.
func _orient_tail(tail: MeshInstance3D, sun_dir: Vector3) -> void:
	var y_axis := sun_dir.normalized()
	var arbitrary := Vector3.RIGHT if absf(y_axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x_axis := arbitrary.cross(y_axis).normalized()
	var z_axis := y_axis.cross(x_axis).normalized()
	tail.transform.basis = Basis(x_axis, y_axis, z_axis)
	var h: float = (tail.mesh as CylinderMesh).height
	tail.position = -y_axis * (h * 0.5)


# --- 3D setup ---

func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = _make_starfield_texture()
	var sky := Sky.new()
	sky.sky_material = sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.10, 0.12, 0.18)
	_env.ambient_light_energy = 0.6
	# Glow stays off except for Star, where it's what makes the emissive
	# surface actually bloom instead of just looking like a flat bright disc.
	_env.glow_enabled = false
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.25
	_env.glow_hdr_threshold = 1.0

	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	# Angled to light the hemisphere facing the default camera (yaw 0.6),
	# with the terminator visible on the left for depth.
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.light_energy = 1.3
	_sun.rotation_degrees = Vector3(-20, 75, 0)
	add_child(_sun)

	# Faint cool fill so the night side reads as a silhouette, not a void.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.light_energy = 0.12
	fill.rotation_degrees = Vector3(15, -120, 0)
	add_child(fill)


# Star-scatter panorama generated at runtime — no assets needed.
func _make_starfield_texture() -> ImageTexture:
	var img := Image.create(2048, 1024, false, Image.FORMAT_RGB8)
	img.fill(Color(0.005, 0.007, 0.012))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 1400:
		var x := rng.randi_range(0, 2047)
		var y := rng.randi_range(0, 1023)
		var b := rng.randf_range(0.2, 1.0)
		var col := Color(b, b, b * rng.randf_range(0.85, 1.0))
		img.set_pixel(x, y, col)
		if b > 0.8:  # brightest stars get a tiny cross of neighbors
			for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var px := x + off.x
				var py := y + off.y
				if px >= 0 and px < 2048 and py >= 0 and py < 1024:
					img.set_pixel(px, py, col * 0.4)
	return ImageTexture.create_from_image(img)


func _build_camera() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_camera = Camera3D.new()
	_pivot.add_child(_camera)
	_update_camera()


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.45, 1.45)
	_distance = clampf(_distance, MIN_DISTANCE, MAX_DISTANCE)
	_pivot.rotation = Vector3(_pitch, _yaw, 0)
	_camera.position = Vector3(0, 0, _distance)


# --- Camera input ---
# _unhandled_input so the control panel's own mouse handling wins over it.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back_to_menu()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_R:
			_roll_new_seed()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance *= ZOOM_STEP
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance /= ZOOM_STEP
				_update_camera()
			MOUSE_BUTTON_LEFT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SENSITIVITY
			_pitch -= mm.relative.y * ORBIT_SENSITIVITY
			_update_camera()
		elif _panning:
			var scale_factor := _distance * PAN_SENSITIVITY
			_pivot.position += (-_camera.global_basis.x * mm.relative.x
					+ _camera.global_basis.y * mm.relative.y) * scale_factor


# --- UI ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := UIPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_bottom = -16
	panel.custom_minimum_size = Vector2(280, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "COSMIC FORGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Flat list of sibling body kinds — not "Planet" with sub-types. Moon,
	# Asteroid, and Star will join this same list later, each with their own
	# knob set and generator.
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 8)
	vbox.add_child(type_row)
	var type_lbl := Label.new()
	type_lbl.text = "Body Type"
	type_lbl.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	type_lbl.add_theme_color_override("font_color", UITheme.text)
	type_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(type_lbl)
	var type_opt := OptionButton.new()
	for type_name in BODY_TYPE_NAMES:
		type_opt.add_item(type_name)
	type_opt.selected = 0
	type_opt.item_selected.connect(_on_body_type_selected)
	type_row.add_child(type_opt)

	vbox.add_child(HSeparator.new())

	_knob_container = VBoxContainer.new()
	_knob_container.add_theme_constant_override("separation", 10)
	vbox.add_child(_knob_container)
	_rebuild_knobs()

	vbox.add_child(HSeparator.new())

	var gen_btn := UIButton.new()
	gen_btn.text = "Generate  (R)"
	gen_btn.accent = true
	gen_btn.custom_minimum_size = Vector2(0, 44)
	gen_btn.add_theme_font_size_override("font_size", 16)
	gen_btn.pressed.connect(_roll_new_seed)
	vbox.add_child(gen_btn)

	var rand_btn := UIButton.new()
	rand_btn.text = "Random"
	rand_btn.custom_minimum_size = Vector2(0, 36)
	rand_btn.tooltip_text = "Randomize all sliders and generate"
	rand_btn.add_theme_font_size_override("font_size", 14)
	rand_btn.pressed.connect(_randomize_all)
	vbox.add_child(rand_btn)

	_seed_label = Label.new()
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_label.add_theme_font_size_override("font_size", 12)
	_seed_label.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(_seed_label)

	var hint := Label.new()
	hint.text = "Drag — orbit   ·   Wheel — zoom\nRight-drag — pan"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(hint)

	# Corner cluster, matching the main menu convention
	var icon_row := HBoxContainer.new()
	icon_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	icon_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	icon_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	icon_row.offset_right = -16
	icon_row.offset_bottom = -16
	layer.add_child(icon_row)
	var back_btn := UIButton.new()
	back_btn.text = "Menu"
	back_btn.dim = true
	back_btn.custom_minimum_size = Vector2(70, 32)
	back_btn.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	back_btn.pressed.connect(_back_to_menu)
	icon_row.add_child(back_btn)


func _add_knob_row(parent: VBoxContainer, knob_name: String, spec: Array) -> void:
	var lbl := Label.new()
	lbl.text = spec[0]
	lbl.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	lbl.add_theme_color_override("font_color", UITheme.text)
	parent.add_child(lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var is_int: bool = spec[4]
	var slider := HSlider.new()
	slider.min_value = spec[1]
	slider.max_value = spec[2]
	slider.step = 1.0 if is_int else 0.01
	slider.value = spec[3]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", UITheme.dim)
	val_lbl.text = _format_knob(slider.value, is_int)
	row.add_child(val_lbl)

	# Label updates live; the (possibly expensive) re-sculpt is debounced so
	# mid-drag movement and keyboard nudges regenerate shortly after the value
	# settles, and drag release fires immediately.
	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = _format_knob(v, is_int)
		_regen_timer.start())
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			_regen_timer.stop()
			_regenerate())

	_sliders[knob_name] = slider


func _format_knob(value: float, is_int: bool) -> String:
	return str(int(value)) if is_int else "%.2f" % value


func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
