// Idle diagonal light-sweep for HUD-styled controls (UIButton/UIPanel).
// Lives on a dedicated full-rect overlay quad, NOT the control's own
// background — a Control like Button issues multiple separate draw calls
// (its StyleBox rect, then each text glyph), and a shader applied to the
// Button itself would run independently per draw call rather than as one
// coherent sweep across the whole visible area. A plain transparent
// ColorRect gives this a single quad with clean 0-1 UV to animate across.
//
// chamfer_px > 0 clips the sweep to the same asymmetric chamfered-hexagon
// silhouette UIButton draws for accent buttons (top-left/bottom-right
// corners cut) — otherwise the overlay's plain rect shape would poke the
// sweep past the drawn polygon's cut corners. Leave chamfer_px at 0 for
// plain rect controls (no clipping needed).
shader_type canvas_item;

uniform float speed : hint_range(0.0, 4.0) = 0.5;
uniform float band_width : hint_range(0.02, 0.6) = 0.25;
// Tweened between idle and hover values by the owning control.
uniform float intensity : hint_range(0.0, 2.0) = 0.25;
uniform vec4 sweep_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float chamfer_px = 0.0;
uniform vec2 rect_size = vec2(100.0, 40.0);

void fragment() {
	float diag = (UV.x + UV.y) * 0.5;
	float phase = fract(diag - TIME * speed);
	float band = smoothstep(0.0, band_width, phase) * smoothstep(band_width * 2.0, band_width, phase);

	float clip = 1.0;
	if (chamfer_px > 0.0) {
		vec2 p = UV * rect_size;
		// Same two diagonal cut lines as the polygon: near (0,0), cut where
		// x + y < chamfer_px; near (w,h), cut where the mirrored sum does.
		// smoothstep over ~1.5px anti-aliases the clip edge.
		float top_left = smoothstep(0.0, 1.5, (p.x + p.y) - chamfer_px);
		float bottom_right = smoothstep(0.0, 1.5, ((rect_size.x - p.x) + (rect_size.y - p.y)) - chamfer_px);
		clip = top_left * bottom_right;
	}

	COLOR = sweep_color;
	COLOR.a = band * intensity * clip;
}
