extends Node

# Single source of truth for the UI's "chrome" palette — panel backgrounds,
# borders, body/dim text, and accent color shared by every UI panel.
# Functional/semantic colors (alerts, scan results, resource types, etc.) are
# intentionally NOT themed here — they stay as local consts in their owning
# scripts.

signal theme_changed

const PREFS_PATH := "user://prefs.json"

# Curated down (2026-07-16) from an earlier 13-flavor set to just the four
# that actually read as sci-fi — the rest (Verdant, Crimson, Blood Moon,
# Driftwood, Amethyst, Ember, Cotton Candy, Sakura) skewed toward other
# genres entirely (nature, horror, pastel) rather than "spacecraft console."
enum Flavor {
	MIDNIGHT_OIL, ELECTRIC_BLUE, OBSIDIAN, SLATE,
}

const DEFAULT_FLAVOR := Flavor.ELECTRIC_BLUE

const FLAVORS := {
	Flavor.MIDNIGHT_OIL: {
		"name":        "Midnight Oil",
		"bg":          Color(0.04, 0.05, 0.08, 0.85),
		"panel":       Color(0.06, 0.07, 0.11),
		"slot":        Color(0.10, 0.12, 0.17),
		"border":      Color(0.20, 0.24, 0.34),
		"text":        Color(0.85, 0.87, 0.92),
		"dim":         Color(0.40, 0.44, 0.52),
		"accent":      Color(0.90, 0.70, 0.35),
		"button":      Color(0.09, 0.10, 0.15),
		"button_hov":  Color(0.15, 0.17, 0.24),
	},
	Flavor.ELECTRIC_BLUE: {
		"name":        "Electric Blue (Default)",
		"bg":          Color(0.015, 0.03, 0.06, 0.85),
		"panel":       Color(0.02, 0.05, 0.09),
		"slot":        Color(0.03, 0.08, 0.14),
		"border":      Color(0.10, 0.35, 0.55),
		"text":        Color(0.80, 0.92, 1.00),
		"dim":         Color(0.28, 0.45, 0.58),
		"accent":      Color(0.10, 0.75, 1.00),
		"button":      Color(0.02, 0.07, 0.12),
		"button_hov":  Color(0.04, 0.14, 0.22),
	},
	Flavor.OBSIDIAN: {
		"name":        "Obsidian",
		"bg":          Color(0.04, 0.04, 0.05, 0.85),
		"panel":       Color(0.06, 0.06, 0.07),
		"slot":        Color(0.10, 0.10, 0.12),
		"border":      Color(0.22, 0.22, 0.26),
		"text":        Color(0.88, 0.88, 0.92),
		"dim":         Color(0.42, 0.42, 0.48),
		"accent":      Color(0.75, 0.78, 0.85),
		"button":      Color(0.10, 0.10, 0.12),
		"button_hov":  Color(0.16, 0.16, 0.20),
	},
	Flavor.SLATE: {
		"name":        "Slate",
		"bg":          Color(0.08, 0.09, 0.11, 0.85),
		"panel":       Color(0.10, 0.11, 0.13),
		"slot":        Color(0.15, 0.17, 0.20),
		"border":      Color(0.28, 0.32, 0.38),
		"text":        Color(0.85, 0.88, 0.92),
		"dim":         Color(0.45, 0.48, 0.54),
		"accent":      Color(0.40, 0.62, 0.80),
		"button":      Color(0.16, 0.19, 0.23),
		"button_hov":  Color(0.24, 0.28, 0.34),
	},
}

var flavor: Flavor = DEFAULT_FLAVOR

var bg: Color
var panel: Color
var slot: Color
var border: Color
var text: Color
var dim: Color
var accent: Color
var button: Color
var button_hov: Color


func _ready() -> void:
	_apply(_load_saved_flavor())


func set_flavor(f: Flavor) -> void:
	if f == flavor:
		return
	_apply(f)
	_save_flavor(f)
	theme_changed.emit()


func flavor_names() -> Array[String]:
	var names: Array[String] = []
	for f: Flavor in Flavor.values():
		names.append(FLAVORS[f]["name"])
	return names


func _load_saved_flavor() -> Flavor:
	var prefs := _read_prefs()
	var idx: int = int(prefs.get("ui_theme", DEFAULT_FLAVOR))
	if idx < 0 or idx >= Flavor.values().size():
		return DEFAULT_FLAVOR
	return idx as Flavor


func _save_flavor(f: Flavor) -> void:
	var prefs := _read_prefs()
	prefs["ui_theme"] = int(f)
	var file := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(prefs))


func _read_prefs() -> Dictionary:
	if not FileAccess.file_exists(PREFS_PATH):
		return {}
	var file := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


# --- Shared button "juice" ---
# Every push button in the game routes through this pair so a tweak to the
# look/feel only has to happen in one place. Gives buttons a thin border, a
# soft drop shadow, a darker "pressed" state, and a hover scale-pop — instead
# of a single flat bg_color swap.

func style_button(btn: Button, bg_normal: Color, bg_hover: Color, border_col: Color, corner: int = 6, pop: bool = true) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_normal
	normal.border_color = border_col
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(corner)
	normal.shadow_color = Color(0, 0, 0, 0.35)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 2)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_hover
	hover.border_color = accent
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(corner)
	hover.shadow_color = Color(0, 0, 0, 0.45)
	hover.shadow_size = 5
	hover.shadow_offset = Vector2(0, 3)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = bg_normal.darkened(0.15)
	pressed.border_color = border_col
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(corner)
	btn.add_theme_stylebox_override("pressed", pressed)

	# Rows packed edge-to-edge in a tight list (see LocationsPanel) have
	# nowhere to grow — the pop visibly bulges past the panel's own border on
	# hover instead of reading as a tactile pop. Callers with that kind of
	# layout pass pop=false and rely on the border/bg swap above alone.
	if pop:
		wire_hover_pop(btn)


# Drop shadow for Labels that float directly over the 3D viewport with no
# panel/backdrop behind them (HUD's top-corner readouts, ShipStatusStrip,
# SystemView/PlanetarySystemView's body callouts) — a bright planet or star
# behind the text can otherwise wash it out. Labels sitting on a UIPanel's
# own opaque background don't need this; only genuinely floating text does.
func style_label_shadow(label: Label, color: Color = Color(0, 0, 0, 0.85), offset: Vector2i = Vector2i(1, 1)) -> void:
	label.add_theme_color_override("font_shadow_color", color)
	label.add_theme_constant_override("shadow_offset_x", offset.x)
	label.add_theme_constant_override("shadow_offset_y", offset.y)


# Subtle scale-up on hover (reset on exit) — gives buttons a tactile "pop"
# instead of just swapping colors. Works on any Control (Button or a manually
# styled PanelContainer).
func wire_hover_pop(ctrl: Control, hover_scale: float = 1.05) -> void:
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.resized.connect(func() -> void: ctrl.pivot_offset = ctrl.size * 0.5)
	ctrl.mouse_entered.connect(func() -> void:
		if ctrl is Button and (ctrl as Button).disabled:
			return
		var tw := ctrl.create_tween()
		tw.tween_property(ctrl, "scale", Vector2(hover_scale, hover_scale), 0.12) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	ctrl.mouse_exited.connect(func() -> void:
		var tw := ctrl.create_tween()
		tw.tween_property(ctrl, "scale", Vector2.ONE, 0.12) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))


func _apply(f: Flavor) -> void:
	flavor = f
	var p: Dictionary = FLAVORS[f]
	bg         = p["bg"]
	panel      = p["panel"]
	slot       = p["slot"]
	border     = p["border"]
	text       = p["text"]
	dim        = p["dim"]
	accent     = p["accent"]
	button     = p["button"]
	button_hov = p["button_hov"]
