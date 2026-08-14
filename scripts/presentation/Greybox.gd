class_name Greybox
extends RefCounted

## Shared meshes and materials for the greybox build.
##
## GDD 32.3: art is minimal at this stage, but tile / number / obstacle
## legibility is held to shipping standard, because that is the one thing the
## core loop cannot be tuned without.
## GDD 15.3 reading order: number > covered tile > obstacle > character > VFX > background.

const C_DECK := Color(0.72, 0.65, 0.52)          ## opened slab
const C_DECK_EDGE := Color(0.50, 0.43, 0.33)
const C_COVERED := Color(0.89, 0.79, 0.58)       ## unopened slab, clearly brighter
const C_COVERED_RIM := Color(0.60, 0.48, 0.30)
const C_OBSTACLE := Color(0.33, 0.29, 0.24)      ## GDD 8.1: nothing like a slab
const C_RAIL := Color(0.63, 0.55, 0.43)
const C_PIER := Color(0.55, 0.48, 0.38)
const C_MINE_BODY := Color(0.13, 0.12, 0.11)
const C_MINE_TRIM := Color(0.72, 0.55, 0.22)
const C_SAND := Color(0.83, 0.72, 0.48)
const C_SCARF := Color(0.83, 0.20, 0.16)
const C_FUR := Color(0.90, 0.72, 0.42)
const C_FUR_DARK := Color(0.72, 0.52, 0.28)
const C_BELLY := Color(0.97, 0.93, 0.85)

## GDD 8.1 / 23: strongly separated hues, but the glyph is the primary signal
## and the colour is redundant, so a colour-blind player loses nothing.
const NUMBER_COLORS := [
	Color(0.55, 0.52, 0.45),   # 0 - never drawn, blank slab
	Color(0.16, 0.40, 0.82),   # 1
	Color(0.14, 0.52, 0.24),   # 2
	Color(0.78, 0.18, 0.14),   # 3
	Color(0.15, 0.18, 0.52),   # 4
	Color(0.53, 0.13, 0.13),   # 5
	Color(0.10, 0.50, 0.52),   # 6
	Color(0.12, 0.11, 0.10),   # 7
	Color(0.40, 0.38, 0.36),   # 8
]

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


static func mat(color: Color, rough: float = 0.92, metal: float = 0.0,
		emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), rough, metal, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
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


## GDD 15.1: the number is engraved into the slab, lying flat on the deck so it
## reads as part of the world rather than as a HUD element. Outlined so dust and
## shadow can never eat it (GDD 15.3).
static func number_label(value: int) -> Label3D:
	var l := Label3D.new()
	l.text = str(value)
	l.font_size = 190
	l.pixel_size = 0.0105
	l.modulate = NUMBER_COLORS[clampi(value, 0, 8)]
	l.outline_size = 52
	l.outline_modulate = Color(1, 0.98, 0.93, 0.96)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.no_depth_test = false
	l.shaded = false
	l.double_sided = true
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Lie flat on the deck, then tip slightly toward the reading camera.
	l.rotation_degrees = Vector3(-72.0, 0.0, 0.0)
	# Sits proud of the slab so cracks, dust and debris pass under it, never
	# across it (GDD 15.3, GDD 30 "퍼즐 단서가 ... 가려지는 아트" is banned).
	l.position = Vector3(0.0, 0.16, 0.14)
	return l
