shader_type spatial;
render_mode cull_back, specular_disabled, diffuse_lambert;

// Flat cel shading. Light is quantised into a few hard bands and the shadow
// band is *tinted* rather than darkened, which is what keeps a cartoon frame
// looking painted instead of dim.
//
// Kirby's Return to Dream Land Deluxe uses cel shading precisely so the
// characters and the action separate from the backgrounds - "so the action is
// never too distracting, despite its vividness". Same job here: the deck, the
// numbers and the fox have to pop off the canyon behind them (GDD 15.3).

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float bands : hint_range(2.0, 5.0, 1.0) = 3.0;
uniform float terminator : hint_range(0.0, 0.3) = 0.03;
// The colour a surface falls to when it is fully in shade. Warm sand shading
// toward violet reads as sunlight, not as "the lights went out".
uniform vec4 shade_tint : source_color = vec4(0.55, 0.52, 0.72, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.86, 1.0);
uniform float rim_strength : hint_range(0.0, 3.0) = 0.7;
uniform float rim_width : hint_range(0.01, 1.0) = 0.45;
uniform float emission_amount : hint_range(0.0, 6.0) = 0.0;
// Cheap vertical gradient so big flat slabs are not a single dead colour.
uniform float grade : hint_range(0.0, 1.0) = 0.10;

varying float v_height;

void vertex() {
	v_height = clamp((VERTEX.y + 1.0) * 0.25, 0.0, 1.0);
}

void fragment() {
	vec3 base = albedo.rgb * (1.0 - grade + grade * (0.6 + 0.8 * v_height));
	ALBEDO = base;
	ALPHA = albedo.a;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// Rim light. This is the single cheapest thing that makes a flat-shaded
	// object read as a drawn shape rather than as untextured geometry.
	float f = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_width, 1.0, f);
	EMISSION = rim_color.rgb * rim * rim_strength + base * emission_amount;
}

uniform float shadow_depth : hint_range(0.0, 1.0) = 0.45;

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	// A slightly soft terminator stops the band edge from crawling on curved
	// surfaces without turning the whole thing back into a gradient.
	float lit = smoothstep(-terminator, terminator, ndl) * clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	lit = clamp(lit * 1.35, 0.0, 1.0);

	float b = max(2.0, bands);
	float stepped = clamp(floor(lit * b) / (b - 1.0), 0.0, 1.0);

	// Cast shadow is folded in as one more band rather than multiplied through.
	// Multiplying would drive a shadowed surface to black, and on big flat decks
	// any shadow-map acne then shows up as hard black blotches - which is
	// exactly what large cel-shaded surfaces cannot afford. HAL made the same
	// call on Return to Dream Land Deluxe: "subtler, more handsome shadows".
	float sh = smoothstep(0.3, 0.7, ATTENUATION);
	float level = stepped * mix(shadow_depth, 1.0, sh);

	vec3 shade = mix(shade_tint.rgb, vec3(1.0), level);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * shade;
}
