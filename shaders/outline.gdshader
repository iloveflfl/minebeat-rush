shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, fog_disabled;

// Ink outline, run as a next_pass behind every cel-shaded surface.
//
// HAL's warning about inverted hulls on Kirby's Return to Dream Land Deluxe was
// that "just using that would result in pixelated outlines in areas of overlap
// between body parts" - the hull tears wherever a mesh has split normals, which
// is every hard edge of every box.
//
// The fix here is to expand along the direction from the object's centre rather
// than along the surface normal. Every mesh in this game is a centred primitive
// (box, cylinder, cone, sphere, capsule), so that direction is continuous across
// a hard edge and the hull stays watertight - no tearing, no doubled lines.
//
// Only VERTEX is touched. Writing POSITION directly and rebuilding the clip
// coordinate by hand breaks the relationship the depth test needs against the
// base pass, and the "outline" then paints over the whole surface instead of
// only its silhouette.

uniform vec4 line_color : source_color = vec4(0.22, 0.14, 0.17, 1.0);
// Line thickness in pixels at a 720p viewport, held constant with distance.
uniform float width_px : hint_range(0.0, 12.0) = 2.6;
// Beyond this the line thins out, so the far canyon does not become scribble.
uniform float fade_start : hint_range(5.0, 400.0) = 70.0;
uniform float fade_end : hint_range(10.0, 900.0) = 300.0;
uniform float far_scale : hint_range(0.0, 1.0) = 0.25;

void vertex() {
	vec3 dir = length(VERTEX) > 0.0001 ? normalize(VERTEX) : NORMAL;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = max(0.05, distance(world, CAMERA_POSITION_WORLD));
	float fade = mix(1.0, far_scale, smoothstep(fade_start, fade_end, dist));
	// 0.00107 keeps one unit of width_px at roughly one pixel for a 42-degree
	// vertical FOV at 720p; scaling by distance holds that width as the camera
	// pulls back.
	VERTEX += dir * (width_px * dist * 0.00107 * fade);
}

void fragment() {
	ALBEDO = line_color.rgb;
}
