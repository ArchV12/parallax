class_name WarpDistortion
extends CanvasLayer

# Full-screen radial blur + chromatic aberration overlay — an
# INTERSTELLAR-EXCLUSIVE effect (2026-07-19; see Cockpit.gd's _process call
# site for the real bug this was — an earlier version drove set_intensity
# unconditionally for every trip, so this showed up on ordinary Sol hops
# too, not just Beyond Light warps). Cockpit builds one per scene load (see
# _build_environment), always present but invisible (intensity 0) unless a
# genuinely interstellar trip is actually driving it — same "stays fully
# hidden until asked for" shape WarpPoints itself already uses, just gated
# harder: WarpPoints stays VISIBLE for every trip and only its tint/speed/
# size get reskinned for interstellar (see that class's own comment);
# WarpDistortion has no plain/default look worth showing at all — chromatic
# aberration's own red/blue channel split inherently reads as a purple
# fringe against WarpPoints' white streaks, which is exactly the "this
# feels different" cue interstellar warp is supposed to have and ordinary
# Sub-Light travel should NOT.
#
# Reads the already-composited screen via a canvas_item shader's
# hint_screen_texture sampler — a handful of samples stepped outward along
# the radial direction from screen center (a cheap directional/zoom blur,
# stronger toward the edges, where real motion blur would read strongest
# too), plus a small chromatic-aberration offset on the R/B channels on top.
# Layer sits above Cockpit's own 3D view/survey UI (so it visibly distorts
# them) but below HUD.gd's own CanvasLayer (layer 100, a separate
# always-on-top autoload) — HUD readouts (ShipStatusStrip, ViewSwitcher,
# ...) stay crisp during a warp instead of smearing along with the 3D view.

const LAYER := 15

var _rect: ColorRect
var _material: ShaderMaterial
var _strength_mult := 1.0  # see set_strength_mult


func _ready() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = _build_material()
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)


# Called every frame by Cockpit alongside WarpPoints.set_target_warp, the
# SAME 0..1 speed fraction — deliberately no separate response/easing curve
# of its own here, this rides WarpPoints' already-eased value rather than
# re-deriving a second one that could drift out of sync with it.
func set_intensity(strength: float) -> void:
	var v := clampf(strength, 0.0, 1.0) * _strength_mult
	_rect.visible = v > 0.001
	if _rect.visible:
		_material.set_shader_parameter("intensity", v)


# Reskin knob mirroring WarpPoints.set_style — an interstellar Beyond Light
# warp reads as more intense than an ordinary Sub-Light burn (see that
# function's own comment for the full reasoning); default 1.0 (no-op) so
# every existing Sub-Light call site is unaffected without changing a line.
func set_strength_mult(mult: float) -> void:
	_strength_mult = mult


static func _build_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

const int SAMPLES = 6;
const float BLUR_SCALE = 0.06;
const float ABERRATION_SCALE = 0.01;

void fragment() {
	vec2 dir = SCREEN_UV - vec2(0.5, 0.5);
	float dist = length(dir);
	vec2 dir_n = dist > 0.0001 ? dir / dist : vec2(0.0);

	// Radial "speed line" blur — average several samples stepped outward
	// along the radial direction, strongest toward the screen edges
	// (dist-scaled) where real motion blur would read strongest too.
	float blur_amount = intensity * dist * BLUR_SCALE;
	vec3 col = vec3(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1) - 0.5;
		col += texture(screen_texture, SCREEN_UV + dir_n * blur_amount * t).rgb;
	}
	col /= float(SAMPLES);

	// Chromatic aberration on top — R/B channels sampled slightly offset
	// outward/inward along the same radial direction.
	float ab = intensity * dist * ABERRATION_SCALE;
	float r = texture(screen_texture, SCREEN_UV + dir_n * ab).r;
	float b = texture(screen_texture, SCREEN_UV - dir_n * ab).b;
	col.r = r;
	col.b = b;

	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
