class_name EarthTransmissionBanner
extends Control

# Centered "EARTH TRANSMISSION" notification (Docs/Science and Knowledge
# System.md's own mockup) — a blueprint unlocking (Research.blueprint_unlocked,
# Knowledge requirements met, NOT actually crafted/granted yet — see
# Cockpit._build_survey_ui's connection) no longer pops this panel open
# directly (2026-07-18 ask). It now first shows a small "Incoming Earth
# Transmission" button in this same spot; only the player choosing to click
# it opens the actual panel with the tech's unlock_text. No auto-dismiss on
# the panel itself — the unlock_text is meant to be read, not glanced at.
#
# Multiple blueprints can unlock before the player gets around to clicking —
# queue_transmission() queues them (_pending) rather than dropping or
# overwriting; the incoming button reappears for the next one once the
# current panel is dismissed.

const PANEL_WIDTH := 420.0

var _panel: UIPanel
var _title_label: Label
var _body_label: Label
var _incoming_button: UIButton
var _pending: Array[TechnologyDef] = []
var _showing_panel := false


# This Control is Cockpit-scene-local — the WHOLE Cockpit scene frees on any
# scene change (GO-ing anywhere), which would otherwise leave AudioManager's
# dedicated incoming_transmission.ogg player looping forever in the
# background with nothing left able to stop it (the Control that "owned"
# that state is gone). Defensive stop regardless of whether the button
# happened to be visible at the moment of teardown.
func _exit_tree() -> void:
	AudioManager.stop_incoming_transmission_loop()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_incoming_button = UIButton.new()
	_incoming_button.text = "Incoming Earth Transmission"
	_incoming_button.solid = true
	_incoming_button.custom_minimum_size = Vector2(PANEL_WIDTH, 44)
	_incoming_button.visible = false
	_incoming_button.pressed.connect(_on_incoming_pressed)
	center.add_child(_incoming_button)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.visible = false
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)
	vbox.add_child(UIPanel.build_title_header("Earth Transmission"))

	var milestone_label := Label.new()
	milestone_label.text = "Scientific Milestone Achieved"
	milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	milestone_label.add_theme_font_size_override("font_size", 12)
	milestone_label.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(milestone_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_body_label)

	var dismiss := UIButton.new()
	dismiss.text = "DISMISS"
	dismiss.solid = true
	dismiss.shimmer_enabled = false
	dismiss.custom_minimum_size = Vector2(0, 34)
	dismiss.pressed.connect(_on_dismiss_pressed)
	vbox.add_child(dismiss)


# Queues a blueprint-unlock notification — shows the "Incoming Earth
# Transmission" button immediately only if nothing is currently showing
# (neither the button nor the open panel); otherwise it waits its turn.
func queue_transmission(tech: TechnologyDef) -> void:
	_pending.append(tech)
	if not _showing_panel and not _incoming_button.visible:
		_set_incoming_visible(true)


func _on_incoming_pressed() -> void:
	_set_incoming_visible(false)
	var tech: TechnologyDef = _pending.pop_front()
	_showing_panel = true
	_title_label.text = tech.display_name
	_body_label.text = tech.unlock_text
	_panel.visible = true
	_panel.open_animated()


# Reveals the next queued incoming-transmission button, if any, once the
# current one's been read and dismissed — not tracked via _panel.visible
# (close_animated only tweens scale/modulate, it never flips .visible back
# off, so that flag alone isn't a reliable "is a transmission showing" test).
func _on_dismiss_pressed() -> void:
	AudioManager.technology_unlocked()
	_panel.close_animated()
	_showing_panel = false
	if not _pending.is_empty():
		_set_incoming_visible(true)


# Single choke point for the button's visibility so it can never end up out
# of sync with AudioManager's looped sfx/incoming_transmission.ogg — every
# call site above goes through this instead of setting _incoming_button.
# visible directly, so the sfx is guaranteed to loop for exactly as long as
# the button is actually showing (user ask: looped while visible, nothing
# more). The spoken voiceover/incoming_transmission.ogg line fires once,
# right here, each time the button transitions to visible (a fresh queued
# item reappearing counts as "appearing" again, same as the very first one).
func _set_incoming_visible(v: bool) -> void:
	_incoming_button.visible = v
	if v:
		AudioManager.start_incoming_transmission_loop()
		AudioManager.incoming_transmission_vo()
	else:
		AudioManager.stop_incoming_transmission_loop()
