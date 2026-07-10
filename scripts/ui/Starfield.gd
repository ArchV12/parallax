class_name Starfield
extends Control

# Procedural star backdrop for the main menu — a scatter of faint dots with a
# subtle per-star twinkle. Positions are stored normalized (0-1) so the field
# survives window resizes without re-rolling. Like Ironwood's MenuDiorama,
# MainMenu keeps this node alive across theme rebuilds so the sky doesn't
# visibly re-scatter every time the flavor changes.

const STAR_COUNT := 320
# Twinkle is slow (0.8-2.2 rad/s, i.e. a ~3-8s period) — redrawing every
# single frame re-issues 320 draw_circle calls for a change nobody can
# actually see between frames. Throttling to this rate is visually
# identical but far cheaper on the main thread.
const REDRAW_INTERVAL := 1.0 / 24.0

# A few stars get a faint color tint — spectral variety, very subtle.
const TINTS: Array[Color] = [
	Color(1.00, 1.00, 1.00),  # white (most common, weighted below)
	Color(0.80, 0.87, 1.00),  # blue-white
	Color(1.00, 0.92, 0.80),  # warm yellow
	Color(1.00, 0.83, 0.75),  # faint red
]

var _stars: Array[Dictionary] = []
var _time: float = 0.0
var _redraw_accum: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in STAR_COUNT:
		var tint: Color = TINTS[0] if rng.randf() < 0.7 else TINTS[rng.randi_range(1, TINTS.size() - 1)]
		_stars.append({
			"pos":    Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(0.5, 1.6),
			"alpha":  rng.randf_range(0.25, 0.85),
			# Most stars hold steady; ~1 in 4 twinkles gently.
			"twinkle_amp":   rng.randf_range(0.15, 0.40) if rng.randf() < 0.25 else 0.0,
			"twinkle_speed": rng.randf_range(0.8, 2.2),
			"twinkle_phase": rng.randf_range(0.0, TAU),
			"tint":   tint,
		})


func _process(delta: float) -> void:
	_time += delta
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()


func _draw() -> void:
	var dims := size
	for star: Dictionary in _stars:
		var a: float = star["alpha"]
		var amp: float = star["twinkle_amp"]
		if amp > 0.0:
			a = clampf(a + sin(_time * star["twinkle_speed"] + star["twinkle_phase"]) * amp, 0.05, 1.0)
		var col: Color = star["tint"]
		col.a = a
		draw_circle((star["pos"] as Vector2) * dims, star["radius"], col)
