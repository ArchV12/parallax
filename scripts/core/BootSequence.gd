extends Control

# The player's very first moments after "New Game" — a system-boot / mission
# briefing intro establishing scale and tone before dropping into the cockpit.
# Text accumulates rather than fading away, framing this as the player
# activating the command vessel rather than watching a cutscene. Any
# key/click skips straight to the cockpit.
#
# CommanderBriefing is temporarily out of this flow (kept around, not
# deleted) — this hands off directly to Cockpit.gd instead.
#
# Audio:
#   MusicManager.play_boot()      -> Assets/music/Boot Sequence.ogg [live]
#     Ambient drone / distant orchestral swell, played once (not looped) —
#     timed to run out right as "You are its commander" lands in silence.
#     Held off until the menu music has finished crossfading out (MainMenu
#     calls MusicManager.stop() on "New Game"; we wait out MusicManager.
#     FADE_TIME on a black, silent screen before starting this track), so
#     the two never overlap.
#   AudioManager.type_char()      -> Assets/sfx/type_char.ogg [live]
#     Terminal click, retriggered every TYPE_CLICK_STRIDE characters as text
#     types on, with a little pitch wobble per hit.
#   AudioManager.boot_tone()      -> Assets/sfx/boot/tone.wav|ogg [not yet added]
#     Soft electronic blip, played once per status line during the
#     "INITIALIZING..." beat.
#   AudioManager.boot_confirm()   -> Assets/sfx/access_granted.ogg [live]
#     Single confirmation tone under "COMMANDER ACCESS GRANTED".
# The not-yet-added ones no-op safely (with a one-time warning) until the
# files exist, per AudioManager/MusicManager's existing convention.

const FADE_TIME := 1.0
const COCKPIT_REVEAL_TIME := 4.0  # the sequence's own natural ending (_finish) gets a long, deliberate reveal — skipping (early or via the intro pref) still gets HUD.go_to's normal quick fade, see those call sites
const TYPE_CHARS_PER_SEC := 35.0
const TYPE_MIN_TIME := 0.06
const TYPE_CLICK_STRIDE := 2  # click every Nth typed character — every char at 35cps blurs into a buzz
const PREFS_PATH := "user://prefs.json"  # same file/shape OptionsUI reads and writes "skip_intro" to

var _skipped := false

var _status_label: Label
var _title_label: Label
var _year_label: Label
var _body_label: Label
var _hud_label: Label
var _skip_hint: Label


func _ready() -> void:
	# Skip Intro (Options menu) — bail before building any of the sequence's
	# UI at all, straight to the same destination the manual skip goes to.
	if _skip_intro_pref():
		HUD.go_to("res://scenes/cockpit.tscn")
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_status_label = _make_label(16, UITheme.dim, Control.PRESET_TOP_LEFT)
	_status_label.offset_left = 24
	_status_label.offset_top = 20

	_title_label = _make_label(48, UITheme.text, Control.PRESET_CENTER)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_year_label = _make_label(22, UITheme.accent, Control.PRESET_CENTER)
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_body_label = _make_label(22, UITheme.text, Control.PRESET_CENTER)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.custom_minimum_size = Vector2(760, 0)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_hud_label = _make_label(16, UITheme.accent, Control.PRESET_TOP_LEFT)
	_hud_label.offset_left = 24
	_hud_label.offset_top = 20

	_skip_hint = _make_label(11, UITheme.dim, Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skip_hint.offset_right = -16
	_skip_hint.offset_bottom = -12
	_skip_hint.text = "Press any key to skip"
	_skip_hint.visible = true

	HUD.hide_hud()
	_run_sequence()


func _make_label(font_size: int, color: Color, preset: Control.LayoutPreset) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(preset)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.modulate.a = 0.0
	l.visible = false
	add_child(l)
	return l


# --- Sequence ---

func _run_sequence() -> void:
	# Hold on black until the main menu music has finished crossfading out,
	# then bring in the boot sequence's own track before anything else starts.
	if not await _wait(MusicManager.FADE_TIME):
		return
	MusicManager.play_boot()

	# System boot status ticker — typed out like the briefing's terminal reveal.
	_status_label.visible = true
	_status_label.modulate.a = 1.0
	_status_label.visible_ratio = 0.0
	AudioManager.boot_tone()
	if not await _type_append(_status_label, "TPI COMMAND SYSTEM"):
		return
	if not await _wait(0.9):
		return
	AudioManager.boot_tone()
	if not await _type_append(_status_label, "\nINITIALIZING..."):
		return
	if not await _wait(2.8):
		return
	if not await _fade(_status_label, 0.0, 0.4):
		return
	_status_label.visible = false

	# Title card.
	_title_label.text = "THE PARALLAX INITIATIVE"
	_title_label.visible = true
	if not await _fade(_title_label, 1.0, 1.5):
		return
	if not await _wait(3.8):
		return
	if not await _fade(_title_label, 0.0, 1.0):
		return
	_title_label.visible = false

	# Archive-entry date stamp.
	_year_label.text = "YEAR 2037"
	_year_label.visible = true
	if not await _fade(_year_label, 1.0, 0.6):
		return
	if not await _wait(2.8):
		return
	if not await _fade(_year_label, 0.0, 0.6):
		return
	_year_label.visible = false

	# Accumulating narration — three thoughts building on one another.
	_body_label.visible = true
	_body_label.modulate.a = 1.0
	if not await _accumulate(_body_label, "Humanity has mapped the Earth.", 3.0):
		return
	if not await _accumulate(_body_label, "Humanity has touched the Moon.", 3.0):
		return
	if not await _accumulate(_body_label, "But the universe remains mostly unknown.", 5.0):
		return
	if not await _fade(_body_label, 0.0, 1.0):
		return

	_body_label.text = "The first permanent exploration\ncommand vessel has been commissioned."
	if not await _fade(_body_label, 1.0, 1.0):
		return
	if not await _wait(3.8):
		return
	if not await _fade(_body_label, 0.0, 1.0):
		return

	_body_label.text = "You are its commander."
	_body_label.modulate.a = 1.0
	if not await _wait(3.8):
		return
	if not await _fade(_body_label, 0.0, 1.0):
		return
	_body_label.visible = false

	# Final HUD confirmation, typed out, then hand off to the briefing.
	_hud_label.visible = true
	_hud_label.modulate.a = 1.0
	_hud_label.visible_ratio = 0.0
	if not await _type_append(_hud_label, "TPI-01"):
		return
	if not await _wait(0.4):
		return
	if not await _type_append(_hud_label, "\nCOMMANDER ACCESS GRANTED"):
		return
	AudioManager.boot_confirm()
	if not await _wait(2.7):
		return
	if not await _fade(_hud_label, 0.0, 0.6):
		return

	_finish()


func _accumulate(label: Label, line: String, hold_time: float) -> bool:
	label.text = line if label.text == "" else label.text + "\n\n" + line
	if not await _wait(hold_time):
		return false
	return true


# Types on new text at the end of a label that may already hold typed text —
# the already-visible portion stays put while only the new characters type in.
# Steps one character at a time (rather than a single tween) so a click sfx
# can be fired in lockstep with each character actually appearing.
func _type_append(label: Label, text_to_add: String) -> bool:
	if _skipped:
		return false
	var old_len := label.text.length()
	label.text += text_to_add
	var new_len := label.text.length()
	if new_len == 0:
		return true
	label.visible_ratio = float(old_len) / float(new_len)
	var char_time := maxf(1.0 / TYPE_CHARS_PER_SEC, TYPE_MIN_TIME)
	var clickable_count := 0
	for i in range(old_len, new_len):
		if _skipped:
			return false
		label.visible_ratio = float(i + 1) / float(new_len)
		var ch := label.text[i]
		if ch != " " and ch != "\n":
			clickable_count += 1
			if clickable_count % TYPE_CLICK_STRIDE == 1:
				AudioManager.type_char()
		await get_tree().create_timer(char_time).timeout
	return not _skipped


func _fade(node: CanvasItem, target_alpha: float, duration: float) -> bool:
	if _skipped:
		return false
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", target_alpha, duration)
	await tw.finished
	return not _skipped


func _wait(seconds: float) -> bool:
	if _skipped:
		return false
	await get_tree().create_timer(seconds).timeout
	return not _skipped


func _finish() -> void:
	if _skipped:
		return
	HUD.go_to("res://scenes/cockpit.tscn", COCKPIT_REVEAL_TIME)


func _unhandled_input(event: InputEvent) -> void:
	if _skipped:
		return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		_skipped = true
		HUD.go_to("res://scenes/cockpit.tscn")


func _skip_intro_pref() -> bool:
	if not FileAccess.file_exists(PREFS_PATH):
		return false
	var file := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if not file:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var prefs: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	return prefs.get("skip_intro", false)
