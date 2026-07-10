extends Node3D

# The player's real "game" view, reached straight from the boot sequence for
# now — CommanderBriefing is kept around but temporarily pulled out of the
# New Game flow (see BootSequence._finish / CommanderBriefing._on_begin).
# Opens on Earth and Luna as seen from Earth orbit — the vertical slice's
# starting position (see the parallax-core-design-decisions memory). Bodies
# reuse CanonicalBodyGenerator directly, the same generator Cosmic Forge
# uses, rather than re-deriving Earth/Luna's look here.
#
# Positions are hand-placed for a good "you're really here" composition, not
# physically accurate distances — Cockpit/System/Object are deliberately
# separate scale contexts (see "structural, not double-precision" in the
# same memory). Earth sits close and large, cropped into a corner rather
# than centered/full-frame (an "orbital flyby" feel, not a diagram); Luna
# sits genuinely far in the background, small — real relative distance is
# ~30 Earth diameters, wildly impractical to render at readable size, so
# this is an artistic compromise, not a to-scale one. Getting real distance
# scale right (for every body, not just these two) is exactly the kind of
# problem the eventual seeded-hierarchy/orbit system needs to solve
# properly — see the parallax-universe-generation-architecture memory.
#
# Music is hardcoded to Earth Orbit for now since there's no location system
# yet — the game always starts there. Once travel/location tracking exists,
# this should switch to whatever MusicManager.play_<location>() the player's
# current position calls for instead of always playing Earth Orbit.

const EARTH_RADIUS := 5.5
const EARTH_POS := Vector3(-5.0, -4.0, -9.0)   # close and offset toward a corner, not centered
const MOON_RADIUS := 0.9                        # kept readable-sized despite the distance below — see class comment
const MOON_BASE_POS := Vector3(9.0, 4.5, -85.0) # far background, opposite corner from Earth
const MOON_POS_JITTER := 6.0                    # small per-load random offset — see _build_bodies
const EARTH_SPIN := 0.02                        # rad/s — idle rotation
const MOON_SPIN := 0.01                         # rad/s — idle rotation, purely for a "living" feel

var _sun: DirectionalLight3D
var _earth: Node3D
var _moon: Node3D


func _ready() -> void:
	_build_environment()
	_build_bodies()
	HUD.set_view("Earth Orbit", "System", "res://scenes/system_view.tscn")
	MusicManager.play_earth_orbit()


func _process(delta: float) -> void:
	if _earth != null:
		_earth.rotate_y(EARTH_SPIN * delta)
	if _moon != null:
		_moon.rotate_y(MOON_SPIN * delta)


# --- 3D scene ---

func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = StarfieldSky.build_texture()
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.12, 0.18)
	env.ambient_light_energy = 0.6

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.light_energy = 1.3
	_sun.rotation_degrees = Vector3(-25, 55, 0)
	add_child(_sun)

	# Faint cool fill so Earth's night side reads as a silhouette, not a void.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.light_energy = 0.12
	fill.rotation_degrees = Vector3(15, -120, 0)
	add_child(fill)

	# Fixed forward-facing camera, not aimed at Earth — that's what puts
	# Earth's bulk off in a corner instead of centered/full-frame. Narrower
	# than Godot's 75° default — at this close a distance that default reads
	# as an extreme fisheye bulge rather than a majestic orbital view.
	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.rotation_degrees = Vector3(-3, 8, 0)
	add_child(camera)


func _build_bodies() -> void:
	# Colors/texture come from the shared KnownBodies catalog; radius and
	# atmosphere framing are overridden here for this scene's own close-up
	# composition, same as Cosmic Forge overrides them with its sliders.
	var earth_params := KnownBodies.get_entry("Earth").to_params(EARTH_RADIUS)
	earth_params.atmosphere = 0.20
	earth_params.atmo_falloff = 3.0
	_earth = CanonicalBodyGenerator.generate(earth_params)
	_earth.position = EARTH_POS
	# Rerolled each scene load — otherwise Earth always starts at the exact
	# same longitude facing camera, which can land on empty ocean (or the
	# texture's antimeridian seam) every single time.
	_earth.rotation.y = randf_range(0.0, TAU)
	add_child(_earth)

	var atmo := _earth.get_node_or_null("Atmosphere") as MeshInstance3D
	if atmo != null:
		(atmo.material_override as ShaderMaterial).set_shader_parameter(
				"sun_dir", _sun.global_basis.z)

	var moon_params := KnownBodies.get_entry("Luna").to_params(MOON_RADIUS)
	_moon = CanonicalBodyGenerator.generate(moon_params)
	# Small per-load random offset around the base position — a touch of
	# variety without risking drifting out of frame the way a full orbital
	# angle roll around Earth would.
	_moon.position = MOON_BASE_POS + Vector3(
			randf_range(-MOON_POS_JITTER, MOON_POS_JITTER),
			randf_range(-MOON_POS_JITTER * 0.5, MOON_POS_JITTER * 0.5),
			randf_range(-MOON_POS_JITTER * 2.0, MOON_POS_JITTER * 2.0))
	add_child(_moon)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		HUD.hide_hud()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
