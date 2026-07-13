extends Node

# Persistent HUD — an autoload, so unlike everything inside a view's own
# scene tree it survives every change_scene_to_file() swap. Fixed, always-on
# chrome (system status, year, the view-name readout, view-switch nav) lives
# here exactly once instead of being copy-pasted into every view scene; each
# view scene only builds whatever's unique to it.
#
# Metaphor: think of this as the Enterprise's bridge console, not the main
# viewer — it's the instrumentation that's always lit, separate from
# whatever's currently showing on the viewscreen (the swapped 3D scene
# underneath). Switching views is a quick flicker/fade of the viewer, not a
# camera move through space — see the transition decision in the
# parallax-core-design-decisions memory.
#
# Any screen that ISN'T an in-flight view (MainMenu, BootSequence,
# CommanderBriefing, Cosmic Forge, ...) must call hide_hud() in its own
# _ready() — the HUD has no way to know when you've left gameplay other than
# being told, and defaults to hidden so a forgotten call fails safe (no HUD)
# rather than leaking gameplay chrome onto a menu screen.

const TRANSITION_FADE_TIME := 0.18
const TRANSITION_HOLD_TIME := 0.05

var _hud_layer: CanvasLayer
var _fade_layer: CanvasLayer
var _pause_layer: CanvasLayer
var _debug_layer: CanvasLayer
var _system_label: Label
var _year_label: Label
var _view_label: Label
var _view_switcher: ViewSwitcher
var _console: ConsolePanel
var _fade_rect: ColorRect
var _fps_label: Label
var _cheat_engine_label: Label
var _pause_menu: PauseMenu
var _research_panel: ResearchPanel
var _cheat_menu: CheatMenu
var _operation_toast: OperationToast


func _ready() -> void:
	# Fade sits between the 3D viewer (layer 0) and the HUD (layer 100) —
	# the console stays lit and readable through the flicker; only the
	# viewer itself blacks out.
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 50
	add_child(_fade_layer)

	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 100
	add_child(_hud_layer)

	# Above the console, below the debug overlay — the System panel floats
	# over the console it was opened from.
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 150
	add_child(_pause_layer)

	# Above everything and independent of show_hud()/hide_hud() — the F1
	# cheat overlay is dev tooling, not gameplay chrome, so it needs to work
	# on every screen (menus, Cosmic Forge, ...) not just in-flight views.
	_debug_layer = CanvasLayer.new()
	_debug_layer.layer = 200
	add_child(_debug_layer)

	_build_fade()
	_build_hud()
	_build_pause()
	_build_debug()
	hide_hud()

	UITheme.theme_changed.connect(_on_theme_changed)


func _process(_delta: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# Persistent reminder that a tier is pinned even when the cheat menu
	# itself is closed — polled rather than signal-driven since PlayerState.
	# engine_tier_override can also change without the menu's own knowledge
	# (reset_for_new_game, a future dev console, ...).
	_cheat_engine_label.visible = PlayerState.engine_tier_override >= 0
	if _cheat_engine_label.visible:
		var tier: Dictionary = TravelCalc.ENGINE_TIERS[PlayerState.engine_tier_override]
		_cheat_engine_label.text = "ENGINE CHEAT: %s" % tier["name"]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F1:
		_fps_label.visible = not _fps_label.visible
	elif event.keycode == KEY_F2:
		_cheat_menu.toggle()


func _build_fade() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	_fade_layer.add_child(_fade_rect)


func _build_hud() -> void:
	_system_label = _make_label(Control.PRESET_TOP_LEFT)
	_system_label.offset_left = 24
	_system_label.offset_top = 20
	_system_label.text = "TPI COMMAND SYSTEM"

	_year_label = _make_label(Control.PRESET_TOP_RIGHT)
	_year_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_year_label.offset_right = -24
	_year_label.offset_top = 20
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_year_label.text = "YEAR 2037"

	_view_label = _make_label(Control.PRESET_TOP_LEFT)
	_view_label.offset_left = 24
	_view_label.offset_top = 46
	_view_label.add_theme_font_size_override("font_size", 12)
	_view_label.add_theme_color_override("font_color", UITheme.dim)

	_view_switcher = ViewSwitcher.new()
	_view_switcher.view_selected.connect(go_to)
	_hud_layer.add_child(_view_switcher)

	_console = ConsolePanel.new()
	_console.system_pressed.connect(open_system_menu)
	_console.research_pressed.connect(open_research_panel)
	_hud_layer.add_child(_console)

	# Subscribed directly here, not in a per-scene script like Cockpit.gd's
	# other Research/Operations wiring — deliberately the first of its kind.
	# Every other subscription to these signals lives in Cockpit, which is
	# freed on every scene change; HUD is the one autoload CanvasLayer
	# guaranteed to exist regardless of which view is active, same reasoning
	# _process above already uses polling PlayerState.engine_tier_override
	# regardless of scene. Operations completing or a milestone firing while
	# the player isn't in Cockpit (now possible now that operations survive
	# scene changes — see Operations.gd) would otherwise be silently missed,
	# the exact bug this whole notification exists to avoid.
	_operation_toast = OperationToast.new()
	_hud_layer.add_child(_operation_toast)
	Operations.operation_started.connect(_on_operation_started)
	Operations.operation_completed.connect(_on_operation_completed)
	Operations.operation_stopped.connect(_on_operation_stopped)
	Research.milestone_reached.connect(_on_milestone_reached)


# Mining-kind only — the mining-start.ogg/mining-loop.ogg cue (see
# AudioManager.mining_start) needs to fire the instant the operation
# actually starts, same "regardless of which view is active" reasoning as
# the rest of this subscription block: Mining can be STARTED only from
# Cockpit's ActivitiesPanel today, but the player could switch away to
# System View a moment later while it keeps running, so this can't live in
# a Cockpit-only script the way a lot of earlier per-scene wiring did.
func _on_operation_started(op_id: String) -> void:
	var op := Operations.get_operation(op_id)
	if op != null and op.activity_id == "mining":
		AudioManager.mining_start()


# Survey-kind only — Mining never reaches operation_completed at all (see
# Operations.operation_stopped/_on_operation_stopped below). Text is driven
# by the ActivityDef's own display_name rather than a hardcoded per-
# activity_id string.
func _on_operation_completed(op_id: String) -> void:
	var op := Operations.get_operation(op_id)
	if op == null:
		return
	var def := Research.activity_def(op.activity_id)
	var name := def.display_name.to_upper() if def != null else op.activity_id.to_upper()
	_operation_toast.show_toast("%s COMPLETE — %s" % [name, op.location_id])


# Mining-kind only — fires the instant a continuous mining operation ends,
# for any of the three reasons (see Operations._finish_mining). Everything
# in summary was already committed to the player's inventory as it ticked
# (see Operations._tick_mining), so this toast is purely informational, not
# a "come look at this" prompt the way _on_operation_completed's is. Cuts
# the mining-loop.ogg cue and plays mining-end.ogg (see AudioManager.
# mining_end) regardless of which of the three reasons ended it — the STOP
# button doesn't play this itself for exactly that reason (see
# ActivitiesPanel._build_mining_active_row), this one call site covers it
# either way.
func _on_operation_stopped(activity_id: String, location_id: String, summary: Dictionary) -> void:
	if activity_id != "mining":
		return
	AudioManager.mining_end()
	var reason_text := "STOPPED"
	match summary.get("reason", ""):
		"depleted":
			reason_text = "DEPOSIT DEPLETED"
		"departed":
			reason_text = "STOPPED — DEPARTED"
	_operation_toast.show_toast("MINING %s — %s: +%d %s" % [
		reason_text, location_id, summary["amount_awarded"], summary["material_name"]])


func _on_milestone_reached(tech: TechnologyDef) -> void:
	_operation_toast.show_toast("MILESTONE: %s" % tech.display_name)


func _build_pause() -> void:
	_pause_menu = PauseMenu.new()
	_pause_layer.add_child(_pause_menu)
	_research_panel = ResearchPanel.new()
	_pause_layer.add_child(_research_panel)


func _build_debug() -> void:
	_fps_label = Label.new()
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_fps_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fps_label.offset_left = 12
	_fps_label.offset_bottom = -8
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color.YELLOW)
	_fps_label.visible = false
	_debug_layer.add_child(_fps_label)

	_cheat_engine_label = Label.new()
	_cheat_engine_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_cheat_engine_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cheat_engine_label.offset_left = 12
	_cheat_engine_label.offset_bottom = -28  # stacked just above the FPS label
	_cheat_engine_label.add_theme_font_size_override("font_size", 14)
	_cheat_engine_label.add_theme_color_override("font_color", Color.CYAN)
	_cheat_engine_label.visible = false
	_debug_layer.add_child(_cheat_engine_label)

	_cheat_menu = CheatMenu.new()
	_debug_layer.add_child(_cheat_menu)


func _make_label(preset: Control.LayoutPreset) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(preset)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UITheme.text)
	_hud_layer.add_child(l)
	return l


func _on_theme_changed() -> void:
	_system_label.add_theme_color_override("font_color", UITheme.text)
	_year_label.add_theme_color_override("font_color", UITheme.text)


# --- Visibility ---

func show_hud() -> void:
	_hud_layer.visible = true


func hide_hud() -> void:
	_hud_layer.visible = false
	_pause_menu.force_close()
	_research_panel.force_close()


# --- View registration ---
# Every in-flight view scene calls this from its own _ready() to tell the
# HUD what it is — view_name is the specific-location readout (e.g. "Earth
# Orbit"), view_id is which ViewSwitcher.VIEWS scope tab to highlight (e.g.
# "cockpit") — the two are independent since a scope can have more than one
# specific location within it. The console itself never changes between
# views (see ConsolePanel.gd) and no longer switches scopes at all — that's
# the ViewSwitcher's job now; System view's own Esc handling still covers
# "back to Cockpit" when nothing's focused there.
func set_view(view_name: String, view_id: String) -> void:
	show_hud()
	_view_label.text = view_name.to_upper()
	_view_switcher.set_active(view_id)


# --- Parameterized navigation ---
# change_scene_to_file() can't pass arguments directly, so a scene that
# needs to know something about WHERE it's going (which planet's moon
# system to build, here) stashes it here first — the target scene reads it
# back in its own _ready(). Planetary System is parameterized per-planet,
# not a fixed scene — reached via a specific scanned planet's BodyInfoPanel
# button, OR the ViewSwitcher's PLANETARY tab (which resolves the right
# planet itself before calling this — see ViewSwitcher._current_planet_for_view)
# (see the planetary-system-view conversation in parallax-core-design-decisions
# memory).
var pending_planet_name: String = ""

# Which scene to go back to on Esc/the back button — Planetary System can
# now be reached from more than one place (Cockpit's PLANETARY tab, System
# view's PLANETARY tab, or a scanned planet's BodyInfoPanel button, which
# only ever lives in System view), so "back" can't be hardcoded to System
# view anymore. Captured from whatever scene is actually active the moment
# this is called — before the switch — rather than requiring every caller
# to know/pass its own path.
var pending_return_scene: String = ""


# See PlayerState.reset_for_new_game — stray pending-navigation state left
# over from a previous session shouldn't leak into a fresh one.
func reset_for_new_game() -> void:
	pending_planet_name = ""
	pending_return_scene = ""


func go_to_planetary_system(planet_name: String) -> void:
	pending_planet_name = planet_name
	var current_scene := get_tree().current_scene
	pending_return_scene = current_scene.scene_file_path if current_scene != null else "res://scenes/system_view.tscn"
	go_to("res://scenes/planetary_system_view.tscn")


# --- System / pause menu ---
# Reached via the console's SYSTEM button, or Esc from Cockpit — both a
# toggle: pressing either again while the menu is already up closes it
# instead of replaying the open animation on top of itself. _pause_menu.
# visible goes true the instant open() runs and only goes false once
# close()'s own animation actually finishes, so it doubles as "is this
# currently open (or closing)" without a separate state flag.
func open_system_menu() -> void:
	if _pause_menu.visible:
		_pause_menu.close()
	else:
		_pause_menu.open()


# Reached via the console's RESEARCH button (Docs/Science and Knowledge
# System - Implementation Roadmap.md, Phase 4) — same open/close toggle
# shape as open_system_menu above.
func open_research_panel() -> void:
	if _research_panel.visible:
		_research_panel.close()
	else:
		_research_panel.open()


# --- Transition ---
# Quick flicker/fade of the viewer only (the console stays lit throughout,
# per the fade/HUD layer split above) — sells "the main viewer just
# switched feed," not a literal camera move through space. `reveal_time`
# only stretches the SECOND leg (black -> new scene) — the first leg (old
# scene -> black) has nothing worth lingering on, so it always stays the
# quick default. BootSequence's first-ever cockpit reveal is the one caller
# that wants a long, deliberate reveal instead of a quick flicker (passes
# its own multi-second value); every ordinary view switch leaves this
# unset and gets the same snappy fade as before.
func go_to(scene_path: String, reveal_time: float = TRANSITION_FADE_TIME) -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 1.0, TRANSITION_FADE_TIME)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene_path))
	tw.tween_interval(TRANSITION_HOLD_TIME)
	tw.tween_property(_fade_rect, "modulate:a", 0.0, reveal_time)
