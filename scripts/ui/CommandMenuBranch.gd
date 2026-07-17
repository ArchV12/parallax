class_name CommandMenuBranch
extends Control

# A single circuit-trace segment in CommandMenu's fan — 2-3 bend points, not
# a straight radial ray (see CommandMenu's own class comment for why), drawn
# progressively as `reveal` tweens 0 -> 1. No shader needed: _draw() walks
# cumulative segment length and draws a polyline up to reveal * total_length,
# interpolating the final partial segment so the tip moves smoothly instead
# of jumping between fixed points. `points` are in the PARENT CommandMenu's
# own local space — this Control fills the same full-rect as its parent so
# no offset translation is needed between the two.

var points: PackedVector2Array = PackedVector2Array()
var stroke_color: Color = Color.WHITE
var stroke_width: float = 1.2

var reveal: float = 0.0:
	set(value):
		reveal = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func total_length() -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


func _draw() -> void:
	if points.size() < 2 or reveal <= 0.0:
		return
	var target := reveal * total_length()
	var drawn := PackedVector2Array()
	drawn.append(points[0])
	var accumulated := 0.0
	for i in range(points.size() - 1):
		var seg_start: Vector2 = points[i]
		var seg_end: Vector2 = points[i + 1]
		var seg_len := seg_start.distance_to(seg_end)
		if accumulated + seg_len >= target:
			var t := (target - accumulated) / seg_len if seg_len > 0.0 else 0.0
			drawn.append(seg_start.lerp(seg_end, t))
			break
		drawn.append(seg_end)
		accumulated += seg_len
	if drawn.size() >= 2:
		draw_polyline(drawn, stroke_color, stroke_width, true)
