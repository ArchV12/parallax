class_name BodyInfoPanel
extends Control

# Read-only data readout for the currently-focused body in System view —
# shown once ScanPrompt is pressed (or immediately, with no scan animation,
# if this body was already scanned earlier this session — see SystemView.gd
# and Discoveries), not automatically on selection; planets are unknown
# properties until scanned (parallax-core-design-decisions memory). Real
# solar-system bodies pull straight from KnownBodies' fact fields — real
# astronomical values, not generated ones. Deliberately basic for now:
# gameplay-relevant properties (resources, biodiversity, ...) are a
# separate, later concern.
#
# Owns the scanning animation itself (2026-07-10) — a "SCANNING..." label +
# progress bar at the top of the panel, in place of the data rows, rather
# than a second floating element next to ScanPrompt's button. start_scan()
# runs it and swaps to the real rows on completion; show_for() skips
# straight to the rows for an already-scanned body.
#
# Stars and planets show genuinely different properties (a star has no
# orbital distance/atmosphere; a planet has no spectral type/planet count),
# so rows are rebuilt fresh per body rather than kept as one fixed row set —
# _build_star_rows/_build_planet_rows branch on entry.body_type. A future
# Moon-specific layout would slot in the same way if it ever needs to
# diverge from the planet one.
#
# Sits left-of-center, vertically centered, via a MarginContainer +
# begin-aligned HBoxContainer rather than manual anchor math — the camera
# keeps the focused body dead-centered, so a centered panel would cover it,
# and the callout's own line/label extend leftward from the body to match.

signal scan_finished(id: String)

const PANEL_WIDTH := 300.0
const LEFT_MARGIN := 32
const SCAN_DURATION := 4.0

var _panel: UIPanel
var _title_label: Label
var _scanning_label: Label
var _scanning_bar: ProgressBar
var _scan_tween: Tween
var _vbox: VBoxContainer
var _row_start_index: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", LEFT_MARGIN)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.visible = false
	row.add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(_vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.add_theme_color_override("font_color", UITheme.accent)
	_vbox.add_child(_title_label)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1.5)
	divider.color = Color(UITheme.accent.r, UITheme.accent.g, UITheme.accent.b, 0.5)
	_vbox.add_child(divider)

	_scanning_label = Label.new()
	_scanning_label.text = "SCANNING..."
	_scanning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scanning_label.add_theme_font_size_override("font_size", 13)
	_scanning_label.add_theme_color_override("font_color", UITheme.accent)
	_scanning_label.visible = false
	_vbox.add_child(_scanning_label)

	_scanning_bar = ProgressBar.new()
	_scanning_bar.custom_minimum_size = Vector2(0, 8)
	_scanning_bar.show_percentage = false
	_scanning_bar.min_value = 0.0
	_scanning_bar.max_value = 1.0
	_scanning_bar.add_theme_stylebox_override("fill", _make_bar_style(UITheme.accent, 1.0))
	_scanning_bar.add_theme_stylebox_override("background", _make_bar_style(UITheme.border, 0.3))
	_scanning_bar.visible = false
	_vbox.add_child(_scanning_bar)

	_row_start_index = _vbox.get_child_count()


func _make_bar_style(col: Color, alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var c := col
	c.a = alpha
	sb.bg_color = c
	sb.set_corner_radius_all(2)
	return sb


# Already-scanned path — no animation, straight to the real data.
func show_for(entry: KnownBodies.Entry) -> void:
	_title_label.text = entry.body_name.to_upper()
	if _scan_tween != null:
		_scan_tween.kill()
		_scan_tween = null
	_scanning_label.visible = false
	_scanning_bar.visible = false
	_populate_rows(entry)
	_panel.open_animated()


# Fresh scan (or a rescan) — shows "SCANNING..." + a filling progress bar in
# place of the data rows, then swaps to the real rows once it completes.
# Doesn't replay the panel's own open/pop-in animation if it's already open
# (a rescan just changes the panel's content, not its container).
func start_scan(entry: KnownBodies.Entry) -> void:
	_title_label.text = entry.body_name.to_upper()
	_clear_rows()
	_scanning_label.visible = true
	_scanning_bar.visible = true
	_scanning_bar.value = 0.0
	if not _panel.visible:
		_panel.open_animated()

	if _scan_tween != null:
		_scan_tween.kill()
	AudioManager.stop("scanner")  # in case a previous scan's sound is still ringing out — a rescan restarts it cleanly rather than layering
	AudioManager.play("scanner")
	_scan_tween = create_tween()
	_scan_tween.tween_property(_scanning_bar, "value", 1.0, SCAN_DURATION)
	_scan_tween.tween_callback(func() -> void: _finish_scan(entry))


func _finish_scan(entry: KnownBodies.Entry) -> void:
	Discoveries.mark_scanned(entry.body_name)
	_scanning_label.visible = false
	_scanning_bar.visible = false
	_populate_rows(entry)
	scan_finished.emit(entry.body_name)


func hide_panel() -> void:
	if _scan_tween != null:
		_scan_tween.kill()
		_scan_tween = null
		AudioManager.stop("scanner")  # scan was still in progress — cut the sound off rather than let it ring out over whatever's shown next
	if _panel.visible:
		_panel.close_animated()


# Rows are rebuilt (not just re-labeled) each time this runs, since a star
# and a planet need entirely different fields, not just different values in
# the same slots.
func _populate_rows(entry: KnownBodies.Entry) -> void:
	_clear_rows()
	if entry.body_type == "Star":
		_build_star_rows(entry)
	else:
		_build_planet_rows(entry)


func _clear_rows() -> void:
	while _vbox.get_child_count() > _row_start_index:
		var child := _vbox.get_child(_vbox.get_child_count() - 1)
		_vbox.remove_child(child)
		child.queue_free()


func _build_planet_rows(entry: KnownBodies.Entry) -> void:
	_add_row("TYPE", entry.body_type)
	_add_row("RADIUS", "%s km (%.2fx Earth)" % [_format_int(entry.real_radius_km), entry.radius_ratio])
	_add_row("ORBITAL DISTANCE", (
			"%.2f AU" % entry.au_distance if entry.parent == "" and entry.au_distance > 0.0 else "—"))
	_add_row("ORBITAL PERIOD", _format_period(entry.orbital_period_days))
	_add_row("ATMOSPHERE", "Yes" if entry.has_atmosphere else "No")
	_add_row("SURFACE PRESSURE", _format_pressure(entry.surface_pressure_atm) if entry.has_solid_surface else "N/A")
	if entry.parent == "":  # moons don't have their own moons
		_add_row("MAJOR MOONS" if entry.moon_count_is_capped else "MOONS", str(entry.moon_count))
		if entry.moon_count > 0:
			_add_planetary_system_button(entry.body_name)


func _build_star_rows(entry: KnownBodies.Entry) -> void:
	_add_row("SPECTRAL TYPE", entry.spectral_type)
	_add_row("RADIUS", "%s km (%.1fx Earth)" % [_format_int(entry.real_radius_km), entry.radius_ratio])
	_add_row("SURFACE TEMPERATURE", "%s K" % _format_int(entry.surface_temp_k))
	_add_row("PLANETS", str(KnownBodies.planets().size()))


func _add_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	_vbox.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", UITheme.text)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)


# Drills into this planet's own moon system (PlanetarySystemView) — only
# offered when there's actually something to look at (moon_count > 0), so
# Mercury/Venus never show a button leading nowhere.
func _add_planetary_system_button(planet_name: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 2)
	_vbox.add_child(spacer)

	var btn := UIButton.new()
	btn.text = "PLANETARY SYSTEM"
	btn.custom_minimum_size = Vector2(0, 32)
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(func() -> void: HUD.go_to_planetary_system(planet_name))
	_vbox.add_child(btn)


func _format_int(n: float) -> String:
	var s := str(int(round(n)))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "," + out
	return out


func _format_period(days: float) -> String:
	if days <= 0.0:
		return "—"
	if days >= 500.0:
		return "%.1f years" % (days / 365.25)
	return "%.1f days" % days


# Real pressures here span 92 atm (Venus) down to 0.00001 atm (Pluto), too
# wide a range for one fixed decimal count — a %.3g-style "N significant
# figures" specifier would be the natural fit, but GDScript's String % only
# supports %s/%d/%f/%o/%x/%c, not %g, so precision is picked by magnitude
# instead.
func _format_pressure(atm: float) -> String:
	if atm <= 0.0:
		return "0 atm"
	if atm >= 1.0:
		return "%.2f atm" % atm
	if atm >= 0.001:
		return "%.4f atm" % atm
	return "%.6f atm" % atm
