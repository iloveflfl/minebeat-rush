shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled,
	blend_mix, fog_disabled, shadows_disabled;

// Full-screen ink outline, drawn as a transparent overlay: only the line pixels
// have any alpha, so nothing needs to sample or re-composite the frame.
//
// HAL's own note on Kirby's Return to Dream Land Deluxe is why this is not an
// inverted hull: "the traditional way to display outlines used a technique
// called 'inverted hull', however just using that would result in pixelated
// outlines in areas of overlap between body parts." A screen-space pass has no
// overlap problem at all - every silhouette gets one line of one width.
//
// Two tests, both from depth alone (the normal-roughness buffer is not readable
// from a transparent material):
//   * discontinuity  - the depth jumps across the pixel  -> outer silhouette
//   * curvature      - the depth *slope* breaks          -> creases and corners
// Chunky cartoon geometry is almost all flat faces, so curvature catches the
// box edges that a normal buffer would have given us.

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 line_color : source_color = vec4(0.20, 0.13, 0.16, 1.0);
uniform float thickness : hint_range(0.5, 4.0) = 1.4;
// Larger = more sensitive. Both thresholds scale with distance so a far surface
// seen at a glancing angle does not read as an edge.
uniform float silhouette_sensitivity : hint_range(1.0, 200.0) = 42.0;
uniform float crease_sensitivity : hint_range(1.0, 600.0) = 190.0;
// Lines fade with distance so the canyon does not turn into scribble.
uniform float fade_start : hint_range(1.0, 400.0) = 60.0;
uniform float fade_end : hint_range(1.0, 900.0) = 320.0;
uniform float far_strength : hint_range(0.0, 1.0) = 0.30;
uniform float opacity : hint_range(0.0, 1.0) = 0.9;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).x;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -(view.xyz / view.w).z;
}

void fragment() {
	vec2 texel = thickness / VIEWPORT_SIZE;
	mat4 ip = INV_PROJECTION_MATRIX;

	float d0 = view_depth(SCREEN_UV, ip);
	float edge = 0.0;

	if (d0 < 1500.0) {
		float dl = view_depth(SCREEN_UV + vec2(-texel.x, 0.0), ip);
		float dr = view_depth(SCREEN_UV + vec2(texel.x, 0.0), ip);
		float du = view_depth(SCREEN_UV + vec2(0.0, -texel.y), ip);
		float dd = view_depth(SCREEN_UV + vec2(0.0, texel.y), ip);

		float jump = max(max(abs(dl - d0), abs(dr - d0)), max(abs(du - d0), abs(dd - d0)));
		float curve = abs((dl + dr) * 0.5 - d0) + abs((du + dd) * 0.5 - d0);

		float e_sil = step(d0 / silhouette_sensitivity, jump);
		float e_crease = step(d0 / crease_sensitivity, curve);
		edge = clamp(max(e_sil, e_crease), 0.0, 1.0);

		float fade = 1.0 - smoothstep(fade_start, fade_end, d0);
		edge *= mix(far_strength, 1.0, fade);
	}

	ALBEDO = line_color.rgb;
	ALPHA = edge * line_color.a * opacity;
}
