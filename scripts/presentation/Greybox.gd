class_name Greybox
extends RefCounted

## Shared meshes and cel-shaded materials.
##
## Palette notes, from the Kirby art-direction research in docs/ARTDIRECTION.md:
##   * The play surface is the most saturated thing on screen. The canyon behind
##     it is deliberately pushed toward pale violet-blue so the deck separates
##     without needing an outline to do all the work (GDD 15.3 reading order).
##   * Nothing is grey. Shade is violet, stone is warm, water is teal. Kirby's
##     ruins read as "the prosperity and joy of what once was", not as decay -
##     HAL's stated fix for ruins feeling like horror was "a bright blue sky and
##     colourful plant life".
##   * Obstacles are violet, not brown, so they can never be confused with a
##     sand-coloured slab (GDD 8.1 / 9.2).

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
const INK := Color(0.22, 0.14, 0.17)

# --- the deck: the most saturated surface in the frame -----------------------
const C_DECK := Color(0.85, 0.72, 0.47)          ## opened slab
const C_DECK_EDGE := Color(0.66, 0.51, 0.33)
const C_COVERED := Color(1.00, 0.91, 0.63)       ## unopened slab, clearly brighter
const C_COVERED_RIM := Color(0.78, 0.55, 0.26)
const C_OBSTACLE := Color(0.44, 0.35, 0.53)      ## GDD 8.1: nothing like a slab
const C_RAIL := Color(0.90, 0.68, 0.42)
const C_PIER := Color(0.80, 0.58, 0.37)
const C_SAND := Color(0.96, 0.86, 0.62)
const C_MINE_BODY := Color(0.24, 0.19, 0.28)
const C_MINE_TRIM := Color(1.00, 0.79, 0.24)

# --- the world ---------------------------------------------------------------
const C_ROCK_NEAR := Color(0.72, 0.60, 0.58)
const C_ROCK_MID := Color(0.66, 0.60, 0.72)
const C_ROCK_FAR := Color(0.62, 0.63, 0.78)      ## aerial perspective, on purpose
const C_WATER := Color(0.31, 0.76, 0.72)
const C_LEAF := Color(0.35, 0.76, 0.42)
const C_LEAF_DARK := Color(0.22, 0.58, 0.36)
const C_TRUNK := Color(0.62, 0.44, 0.28)
const C_FLOWER_A := Color(1.00, 0.48, 0.68)
const C_FLOWER_B := Color(1.00, 0.84, 0.31)
const C_BANNER := Color(0.29, 0.62, 0.92)
const C_CLOUD := Color(1.00, 0.99, 0.97)

# --- the fox -----------------------------------------------------------------
const C_SCARF := Color(1.00, 0.29, 0.30)
const C_FUR := Color(1.00, 0.81, 0.45)
const C_FUR_DARK := Color(0.88, 0.60, 0.25)
const C_BELLY := Color(1.00, 0.97, 0.90)

## GDD 8.1 / 23: strongly separated hues, but the glyph is the primary signal
## and the colour is redundant, so a colour-blind player loses nothing.
const NUMBER_COLORS := [
	Color(0.55, 0.52, 0.45),   # 0 - never drawn, blank slab
	Color(0.13, 0.42, 0.92),   # 1
	Color(0.10, 0.66, 0.31),   # 2
	Color(0.95, 0.24, 0.20),   # 3
	Color(0.46, 0.22, 0.86),   # 4
	Color(0.93, 0.49, 0.09),   # 5
	Color(0.06, 0.70, 0.74),   # 6
	Color(0.15, 0.14, 0.18),   # 7
	Color(0.50, 0.48, 0.56),   # 8
]

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


## A fresh cel-shaded material. Use when the caller needs to animate its colour.
static func toon(color: Color, opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("bands", opts.get("bands", 3.0))
	m.set_shader_parameter("shade_tint", opts.get("shade", Color(0.55, 0.52, 0.72)))
	m.set_shader_parameter("rim_color", opts.get("rim_color", Color(1.0, 0.96, 0.86)))
	m.set_shader_parameter("rim_strength", opts.get("rim", 0.28))
	m.set_shader_parameter("rim_width", opts.get("rim_width", 0.45))
	m.set_shader_parameter("emission_amount", opts.get("emission", 0.0))
	m.set_shader_parameter("grade", opts.get("grade", 0.10))
	if color.a < 1.0:
		m.render_priority = 1
	# The ink is a whole extra draw pass per object. On a phone the background
	# layers give it up entirely - they are the cheapest thing to drop and the
	# least missed, since GDD 15.3 wants them carrying the least line weight
	# anyway.
	var line: float = float(opts.get("outline", 2.6)) * Quality.ink_scale()
	if Quality.is_mobile() and line < 2.4:
		line = 0.0
	if line > 0.0 and color.a >= 1.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE_SHADER
		o.set_shader_parameter("line_color", opts.get("ink", INK))
		o.set_shader_parameter("width_px", line)
		m.next_pass = o
	return m


static func set_albedo(m: Material, color: Color) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("albedo", color)


## Cached shared material, for the thousands of static props that never change.
## `outline` is the ink width in pixels; background layers pass a thin line or
## none at all, so the canyon never competes with the deck (GDD 15.3).
static func mat(color: Color, _rough: float = 1.0, metal: float = 0.0,
		emission: float = 0.0, outline: float = 2.6) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(true), metal, emission, outline]
	if _mats.has(key):
		return _mats[key]
	var opts := {"emission": emission, "outline": outline}
	if metal > 0.4:
		opts["rim"] = 0.9
		opts["bands"] = 4.0
	var m := toon(color, opts)
	_mats[key] = m
	return m


static func box(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var b := BoxMesh.new()
	b.size = size
	_meshes[key] = b
	return b


static func cyl(radius: float, height: float, sides: int = 10) -> CylinderMesh:
	var key := "cyl%.2f_%.2f_%d" % [radius, height, sides]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	_meshes[key] = c
	return c


static func cone(radius: float, height: float, sides: int = 10) -> CylinderMesh:
	var key := "cone%.2f_%.2f_%d" % [radius, height, sides]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	_meshes[key] = c
	return c


static func sphere(radius: float, segs: int = 12) -> SphereMesh:
	var key := "sph%.2f_%d" % [radius, segs]
	if _meshes.has(key):
		return _meshes[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = maxi(4, segs / 2)
	_meshes[key] = s
	return s


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "cap%.2f_%.2f" % [radius, height]
	if _meshes.has(key):
		return _meshes[key]
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 12
	c.rings = 6
	_meshes[key] = c
	return c


static func mi(mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = material
	m.position = pos
	return m


## GDD 15.1: the number is inlaid into the slab, lying flat on the deck so it
## reads as part of the world rather than as a HUD element. Outlined so dust,
## cracks and shadow can never eat it (GDD 15.3).
static func number_label(value: int) -> Label3D:
	var l := Label3D.new()
	l.text = str(value)
	l.font_size = 190
	l.pixel_size = 0.0105
	l.modulate = NUMBER_COLORS[clampi(value, 0, 8)]
	l.outline_size = 56
	l.outline_modulate = Color(1, 0.99, 0.95, 0.97)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.no_depth_test = false
	l.shaded = false
	l.double_sided = true
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.rotation_degrees = Vector3(-72.0, 0.0, 0.0)
	l.position = Vector3(0.0, 0.16, 0.14)
	return l




