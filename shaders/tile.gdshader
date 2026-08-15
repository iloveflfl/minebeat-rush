shader_type spatial;
render_mode cull_back, specular_disabled, diffuse_lambert;

// The Minesweeper board, drawn properly.
//
// GDD 8.1 wants a player to recognise the grid as Minesweeper from a single
// screenshot, and GDD 15.1 wants the opened/unopened height difference readable
// from a distance. The thing that actually carries that recognition is not the
// colour - it is the *bevel*: an unopened cell is a raised button lit from one
// corner, an opened cell is a flat recessed slab inside a crisp grid line.
//
// Doing it in the shader instead of with geometry means the bevel stays exactly
// the same width in world space on every tile, the grid lines never z-fight,
// and there is no extra draw call per tile.

uniform vec4 face_color : source_color = vec4(1.0, 0.91, 0.63, 1.0);
uniform vec4 bevel_light : source_color = vec4(1.0, 0.98, 0.88, 1.0);
uniform vec4 bevel_dark : source_color = vec4(0.74, 0.52, 0.26, 1.0);
uniform vec4 border_color : source_color = vec4(0.42, 0.30, 0.20, 1.0);
uniform float bevel_width : hint_range(0.0, 0.4) = 0.13;
uniform float border_width : hint_range(0.0, 0.1) = 0.028;
// 1 = unopened raised button, 0 = opened recessed slab.
uniform float covered : hint_range(0.0, 1.0) = 1.0;

uniform vec4 shade_tint : source_color = vec4(0.55, 0.52, 0.72, 1.0);
uniform float bands : hint_range(2.0, 5.0, 1.0) = 3.0;
uniform float shadow_depth : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 uv = UV;
	float d_far = uv.y;
	float d_near = 1.0 - uv.y;
	float d_left = uv.x;
	float d_right = 1.0 - uv.x;
	float edge = min(min(d_left, d_right), min(d_far, d_near));

	vec3 c = face_color.rgb;

	if (covered > 0.5) {
		if (edge < bevel_width) {
			// Whichever edge is nearest owns the pixel, which mitres the corners
			// for free. Far and left catch the light, near and right fall away.
			bool lit = (d_far <= d_left && d_far <= d_right && d_far <= d_near)
					|| (d_left <= d_far && d_left <= d_right && d_left <= d_near);
			c = lit ? bevel_light.rgb : bevel_dark.rgb;
		}
	} else {
		// An opened slab is slightly darker toward its edges, so the recess
		// reads even where two opened cells sit side by side.
		c = mix(face_color.rgb * 0.88, face_color.rgb, smoothstep(0.0, 0.22, edge));
	}

	if (edge < border_width) {
		c = border_color.rgb;
	}

	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float lit = smoothstep(-0.03, 0.03, ndl) * clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	lit = clamp(lit * 1.35, 0.0, 1.0);
	float b = max(2.0, bands);
	float stepped = clamp(floor(lit * b) / (b - 1.0), 0.0, 1.0);
	float sh = smoothstep(0.3, 0.7, ATTENUATION);
	float level = stepped * mix(shadow_depth, 1.0, sh);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * mix(shade_tint.rgb, vec3(1.0), level);
}
