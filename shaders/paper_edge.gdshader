shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled, depth_draw_opaque;

// The white paper edge behind every cut-out piece.
//
// This is the single thing that separates "a sprite standing up in a 3D world"
// from "a piece of paper standing up in a 3D world". The Thousand-Year Door
// remake builds its characters as segmented parts with a white layer that gives
// each piece visible thickness, with the limbs reading as pinned on rather than
// as a seamless drawing - so a cut edge is supposed to be *seen*, and seen as
// paper, which is exactly what a bare alpha-cut quad fails to do.
//
// The piece's own texture supplies only its silhouette here; the colour is the
// stock. Drawn slightly larger and slightly behind the art, it rims every part
// in card and makes the joints read as overlapping cut-outs.

uniform sampler2D shape : source_color, filter_linear_mipmap;
uniform vec4 paper_color : source_color = vec4(1.0, 0.985, 0.96, 1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	float a = texture(shape, UV).a;
	if (a < alpha_cut) {
		discard;
	}
	ALBEDO = paper_color.rgb;
	ALPHA = 1.0;
}
