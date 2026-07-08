extends Node3D

# The Cosmic Forge — dev tool for honing the celestial body generators
# (GDD §15, "The Galactic Forge"). Pick a body type, tweak generation knobs,
# and hit Generate to roll new random bodies. Slider changes re-sculpt the
# CURRENT seed live, so one planet can be tuned and compared; Generate (or R)
# rolls a fresh seed.

const FONT_SIZE_SMALL := 14

const ZOOM_STEP := 0.9
const MIN_DISTANCE := 1.2
const MAX_DISTANCE := 40.0
const ORBIT_SENSITIVITY := 0.008
const PAN_SENSITIVITY := 0.0012
const PLANET_SPIN := 0.05  # rad/s — slow idle rotation

var _pivot: Node3D
var _camera: Camera3D
var _yaw := 0.6
var _pitch := -0.25
var _distance := 4.0
var _orbiting := false
var _panning := false

var _planet: Node3D
var _sun: DirectionalLight3D
var _seed: int
var _seed_label: Label
var _sliders: Dictionary = {}  # knob name -> HSlider
var _regen_timer: Timer

# name: [label, min, max, default, is_int]
const KNOBS: Array = [
	["radius",          ["Radius",          0.4, 2.5,  1.0,  false]],
	["continent_scale", ["Continent Scale", 0.4, 3.0,  1.0,  false]],
	["terrain_height",  ["Terrain Height",  0.01, 0.15, 0.06, false]],
	["roughness",       ["Roughness",       0.3, 0.7,  0.5,  false]],
	["ocean_level",     ["Ocean Level",     0.0, 1.0,  0.5,  false]],
	["atmosphere",      ["Atmosphere",      0.0, 1.0,  0.35, false]],
	["atmo_falloff",    ["Atmo Falloff",    0.5, 3.0,  1.5,  false]],
	["detail",          ["Mesh Detail",     3.0, 6.0,  5.0,  true]],
]


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


func _process(delta: float) -> void:
	if _planet != null:
		_planet.rotate_y(PLANET_SPIN * delta)


# --- Generation ---

func _roll_new_seed() -> void:
	_seed = randi()
	_regen_timer.stop()  # cancel any pending slider debounce — we regen now
	_regenerate()


# Random button: scatter every slider across its range, then roll a new seed.
func _randomize_all() -> void:
	for knob: Array in KNOBS:
		var spec: Array = knob[1]
		var slider: HSlider = _sliders[knob[0]]
		slider.value = randf_range(spec[1] as float, spec[2] as float)
	_roll_new_seed()


func _regenerate() -> void:
	var params := PlanetParams.new()
	params.seed = _seed
	params.radius = _sliders["radius"].value
	params.continent_scale = _sliders["continent_scale"].value
	params.terrain_height = _sliders["terrain_height"].value
	params.roughness = _sliders["roughness"].value
	params.ocean_level = _sliders["ocean_level"].value
	params.atmosphere = _sliders["atmosphere"].value
	params.atmo_falloff = _sliders["atmo_falloff"].value
	params.detail = int(_sliders["detail"].value)

	if _planet != null:
		_planet.queue_free()
	_planet = PlanetGenerator.generate(params)
	add_child(_planet)
	_seed_label.text = "Seed: %d" % _seed

	# Point the atmosphere's day-side glow at this scene's sun. (A light's rays
	# travel along -Z of its basis, so +Z is the direction back toward the sun.)
	var atmo := _planet.get_node_or_null("Atmosphere") as MeshInstance3D
	if atmo != null:
		(atmo.material_override as ShaderMaterial).set_shader_parameter(
				"sun_dir", _sun.global_basis.z)


# --- 3D setup ---

func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = _make_starfield_texture()
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

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_bottom = -16
	panel.custom_minimum_size = Vector2(280, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITheme.panel.r, UITheme.panel.g, UITheme.panel.b, 0.92)
	style.border_color = UITheme.border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
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

	# Body type dropdown — Planet only for now; stars/moons/asteroids later.
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
	type_opt.add_item("Planet")
	type_opt.selected = 0
	type_row.add_child(type_opt)

	vbox.add_child(HSeparator.new())

	for knob: Array in KNOBS:
		_add_knob_row(vbox, knob[0] as String, knob[1] as Array)

	vbox.add_child(HSeparator.new())

	var gen_btn := Button.new()
	gen_btn.text = "Generate  (R)"
	gen_btn.custom_minimum_size = Vector2(0, 44)
	gen_btn.add_theme_font_size_override("font_size", 16)
	gen_btn.add_theme_color_override("font_color", UITheme.accent)
	UITheme.style_button(gen_btn, UITheme.button, UITheme.button_hov, UITheme.accent)
	gen_btn.pressed.connect(_roll_new_seed)
	vbox.add_child(gen_btn)

	var rand_btn := Button.new()
	rand_btn.text = "Random"
	rand_btn.custom_minimum_size = Vector2(0, 36)
	rand_btn.tooltip_text = "Randomize all sliders and generate"
	rand_btn.add_theme_font_size_override("font_size", 14)
	rand_btn.add_theme_color_override("font_color", UITheme.text)
	UITheme.style_button(rand_btn, UITheme.button, UITheme.button_hov, UITheme.border)
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
	var back_btn := Button.new()
	back_btn.text = "Menu"
	back_btn.custom_minimum_size = Vector2(70, 32)
	back_btn.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	back_btn.add_theme_color_override("font_color", UITheme.dim)
	UITheme.style_button(back_btn, UITheme.button, UITheme.button_hov, UITheme.border, 5)
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
