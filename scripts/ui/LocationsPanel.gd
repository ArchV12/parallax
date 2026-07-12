class_name LocationsPanel
extends Control

# Slide-out "KNOWN LOCATIONS" drawer on the right side of System view —
# every scanned body (Sol, planets, and their scanned moons), selectable in
# a single-select list, with one LOCK + one GO pair at the bottom of the
# panel that act on whatever's currently selected — so locking/traveling to
# something you've already scanned (a moon especially — see the friction
# conversation in parallax-core-design-decisions memory) doesn't require
# drilling back into that body's own Planetary System view every single
# trip. Unlike BodyInfoPanel/ScanPrompt/LockButton in this same scene, this
# drawer is NOT gated on what's currently focused in the 3D view — the TAB
# is always up, built once in SystemView._ready(); the panel itself stays
# collapsed (a permanent on-screen panel broke immersion) until the tab is
# clicked, and the same tab (it rides along, attached to the panel's edge)
# slides it back out.
#
# Selecting a row also emits location_selected(id) — SystemView listens and
# re-focuses the matching body in its own 3D map (same _select() a direct
# click there would trigger), so picking Earth here selects Earth on the
# map too. That only works for bodies actually present in System view's own
# orbit list (Sol + planets); a moon has no 3D presence there to sync to, so
# selecting one just updates this panel — SystemView's handler simply finds
# no match and no-ops. Deliberately one-directional for now: clicking a
# body directly in the 3D view does NOT update this panel's selection back.
#
# LOCK reuses LockButton as-is (it already self-manages LOCK/UNLOCK against
# the Destination autoload) — no new locking logic here, just pointed at
# whatever's selected. GO routes through PlayerState.travel_to(), the same
# shared "lock + start the trip" entry point ConsolePanel's own GO button
# uses, then flicks the viewer to Cockpit exactly like ConsolePanel does —
# this is a second on-ramp into the same travel pipeline, not a separate one.
#
# Positioning is fully anchor/offset-driven (no Container for the drawer
# itself) rather than the usual MarginContainer+HBoxContainer(END) pattern
# BodyInfoPanel uses — that pattern shrink-wraps to content and has no way
# to park part of itself off-screen for the collapsed state. _drawer is
# pinned to the top-right corner (anchor_left=anchor_right=1) with a fixed
# width (TAB_WIDTH + PANEL_WIDTH); _set_expanded() tweens its offset_left/
# offset_right together (width unchanged) between "only the tab's sliver
# sits at the screen edge" and "the whole thing is pulled into view."

signal location_selected(id: String)

const PANEL_WIDTH := 280.0
const TAB_WIDTH := 30.0
const TAB_HEIGHT := 64.0  # a grab handle, not the full drawer height
const TOP_MARGIN := 92
const RIGHT_MARGIN := 24
const BOTTOM_MARGIN := 210  # stays clear of ConsolePanel's center band
const SLIDE_DURATION := 0.28
const ROW_HEIGHT := 44.0
const FOOTER_BUTTON_SIZE := Vector2(0, 32)

var _drawer: Control
var _tab: Button
var _panel: UIPanel
var _rows_container: VBoxContainer
var _row_group: ButtonGroup
var _expanded := false
var _selected_id: String = ""

var _footer_label: Label
var _footer_lock_btn: LockButton
var _footer_go_btn: UIButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_drawer = Control.new()
	_drawer.anchor_left = 1.0
	_drawer.anchor_right = 1.0
	_drawer.anchor_top = 0.0
	_drawer.anchor_bottom = 1.0
	_drawer.offset_top = TOP_MARGIN
	_drawer.offset_bottom = -BOTTOM_MARGIN
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drawer)

	_build_tab()
	_build_panel()

	PlayerState.location_changed.connect(refresh)
	PlayerState.travel_started.connect(refresh)
	PlayerState.travel_completed.connect(refresh)

	refresh()
	_set_expanded(false, false)  # collapsed by default — see class comment


# A small grab handle vertically centered on the drawer's left edge, not a
# strip spanning the whole height (that read as a wall, not a tab).
func _build_tab() -> void:
	_tab = Button.new()
	_tab.anchor_left = 0.0
	_tab.anchor_right = 0.0
	_tab.anchor_top = 0.5
	_tab.anchor_bottom = 0.5
	_tab.offset_left = 0.0
	_tab.offset_right = TAB_WIDTH
	_tab.offset_top = -TAB_HEIGHT * 0.5
	_tab.offset_bottom = TAB_HEIGHT * 0.5
	_tab.text = "◀"
	_tab.tooltip_text = "Known Locations"
	UITheme.style_button(_tab, UITheme.button, UITheme.button_hov, UITheme.border)
	_tab.pressed.connect(func() -> void:
		AudioManager.ui_confirm("menu_slide")  # the drawer's own slide cue, not the generic click — a raw Button, not UIButton/ConsolePadButton, so this has to do it itself
		_set_expanded(not _expanded))
	_drawer.add_child(_tab)


func _build_panel() -> void:
	_panel = UIPanel.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = TAB_WIDTH
	_panel.offset_right = TAB_WIDTH + PANEL_WIDTH
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	_drawer.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	vbox.add_child(UIPanel.build_title_header("Known Locations"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 4)
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)
	_row_group = ButtonGroup.new()

	_build_footer(vbox)


# Fixed at the bottom of the panel — one LOCK + one GO that act on whatever
# row is currently selected, rather than a pair per row.
func _build_footer(vbox: VBoxContainer) -> void:
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1.5)
	divider.color = Color(UITheme.accent.r, UITheme.accent.g, UITheme.accent.b, 0.35)
	vbox.add_child(divider)

	_footer_label = Label.new()
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_label.add_theme_font_size_override("font_size", 13)
	_footer_label.add_theme_color_override("font_color", UITheme.dim)
	_footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_footer_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	_footer_lock_btn = LockButton.new()
	btn_row.add_child(_footer_lock_btn)

	_footer_go_btn = UIButton.new()
	_footer_go_btn.text = "GO"
	_footer_go_btn.solid = true
	_footer_go_btn.shimmer_enabled = false
	_footer_go_btn.custom_minimum_size = FOOTER_BUTTON_SIZE
	_footer_go_btn.add_theme_font_size_override("font_size", 12)
	_footer_go_btn.press_sfx = "go_button"  # override — see AudioManager.ui_confirm
	_footer_go_btn.pressed.connect(func() -> void: _on_go_pressed(_selected_id))
	btn_row.add_child(_footer_go_btn)


# animate = false only for the initial collapse in _ready — snaps straight
# there instead of visibly sliding in from some default (expanded-looking)
# layout position the instant the scene loads.
func _set_expanded(expanded: bool, animate: bool = true) -> void:
	_expanded = expanded
	_tab.text = "▶" if expanded else "◀"

	var target_left: float
	var target_right: float
	if expanded:
		target_right = -RIGHT_MARGIN
		target_left = -RIGHT_MARGIN - TAB_WIDTH - PANEL_WIDTH
	else:
		target_left = -TAB_WIDTH
		target_right = PANEL_WIDTH

	if not animate:
		_drawer.offset_left = target_left
		_drawer.offset_right = target_right
		return

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_drawer, "offset_left", target_left, SLIDE_DURATION)
	tw.tween_property(_drawer, "offset_right", target_right, SLIDE_DURATION)


# Rebuilds the row list from scratch against current Discoveries/PlayerState
# — simplest correct approach given how infrequently this fires (a scan, a
# trip starting/ending). Re-applies the existing selection highlight to
# whichever new row matches _selected_id (selection itself is just a string,
# not tied to the row Button instance, so it survives the rebuild), then
# refreshes the footer.
func refresh() -> void:
	for child in _rows_container.get_children():
		_rows_container.remove_child(child)
		child.queue_free()

	var entries := _gather_scanned()
	if entries.is_empty():
		_add_empty_row()
	else:
		for entry: KnownBodies.Entry in entries:
			_add_row(entry)

	_refresh_footer()


# Sol, then every planet (KnownBodies.planets() order — real distance from
# Sol), with each planet's own scanned moons immediately after it — mirrors
# the grouping PlanetarySystemView already presents, so a moon always reads
# as "belonging to" the planet just above it rather than a flat, ambiguous
# list.
func _gather_scanned() -> Array[KnownBodies.Entry]:
	var result: Array[KnownBodies.Entry] = []
	var sol := KnownBodies.sol()
	if sol != null and Discoveries.is_scanned(sol.body_name):
		result.append(sol)
	for planet: KnownBodies.Entry in KnownBodies.planets():
		if Discoveries.is_scanned(planet.body_name):
			result.append(planet)
		for moon: KnownBodies.Entry in KnownBodies.moons_of(planet.body_name):
			if Discoveries.is_scanned(moon.body_name):
				result.append(moon)
	return result


func _add_empty_row() -> void:
	var lbl := Label.new()
	lbl.text = "No locations scanned yet."
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_rows_container.add_child(lbl)


# A toggle-mode Button sharing _row_group (Godot's ButtonGroup enforces
# single-select for free — picking a new row automatically un-presses
# whichever was selected before, no manual bookkeeping needed) with the
# name/subtitle labels added as plain child Controls on top rather than
# Button.text, so the "moon of X" subtitle can stay a distinct dim/smaller
# style the way it did as a separate row element before.
func _add_row(entry: KnownBodies.Entry) -> void:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = _row_group
	btn.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(btn, UITheme.button, UITheme.button_hov, UITheme.border, 4, false)  # pop=false — see UITheme.style_button; rows are flush against the panel edges with nowhere to grow
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(UITheme.accent.r, UITheme.accent.g, UITheme.accent.b, 0.22)
	selected_style.border_color = UITheme.accent
	selected_style.set_border_width_all(1)
	selected_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("pressed", selected_style)
	btn.pressed.connect(func() -> void: AudioManager.ui_confirm())  # a raw Button, not UIButton/ConsolePadButton — those wire this on their own, this one has to do it itself
	_rows_container.add_child(btn)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks fall through to btn underneath
	name_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_box.offset_left = 12.0
	name_box.offset_right = -12.0
	btn.add_child(name_box)

	var title := entry.body_name.to_upper()
	if entry.body_name == PlayerState.location_id:
		title += "  ·  HERE"
	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", UITheme.text)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.add_child(name_lbl)

	if entry.parent != "":
		var sub_lbl := Label.new()
		sub_lbl.text = "moon of %s" % entry.parent
		sub_lbl.add_theme_font_size_override("font_size", 10)
		sub_lbl.add_theme_color_override("font_color", UITheme.dim)
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_box.add_child(sub_lbl)

	if entry.body_name == _selected_id:
		btn.button_pressed = true

	var id := entry.body_name
	btn.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_row_selected(id))


func _on_row_selected(id: String) -> void:
	_selected_id = id
	_refresh_footer()
	location_selected.emit(id)


func _refresh_footer() -> void:
	if _selected_id == "":
		_footer_label.text = "No location selected."
		_footer_lock_btn.reset()
		_footer_go_btn.visible = false
		return

	_footer_label.text = _selected_id.to_upper()
	_footer_lock_btn.present(_selected_id)
	_footer_go_btn.visible = true
	_footer_go_btn.text = "HERE" if _selected_id == PlayerState.location_id else "GO"
	_footer_go_btn.disabled = PlayerState.is_traveling or _selected_id == PlayerState.location_id


func _on_go_pressed(id: String) -> void:
	if PlayerState.travel_to(id):
		HUD.go_to("res://scenes/cockpit.tscn")
