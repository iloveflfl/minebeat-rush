class_name FoxArt
extends RefCounted

## The fennec, drawn as vector shapes instead of cut out of a picture.
##
## Every previous attempt sliced the concept sheet into pieces, and every one of
## them failed the same way: a cut through a drawing leaves a straight edge, and
## whatever the cut hid simply does not exist. Rotate the ear and the head shows
## a hole; sink the head to hide the hole and the neck reads as severed. Those
## are not bugs to be patched, they are what cutting up a single flat image
## costs.
##
## So the sheet is used the way a concept sheet is meant to be used: as
## reference. Proportions, palette and silhouette are measured off it and rebuilt
## as closed polygons. Each part is a whole shape with its own outline, so parts
## overlap instead of abutting, nothing has a cut face, and every joint can move
## as far as the pose wants.
##
## Coordinates are normalised: the character is 1.0 tall with its feet at y = 0
## and its centre line at x = 0.

# --- palette, read off the reference -----------------------------------------
const FUR := Color(0.960, 0.855, 0.686)
const FUR_SHADE := Color(0.898, 0.769, 0.573)
const BELLY := Color(1.000, 0.976, 0.933)
const EAR_INNER := Color(0.976, 0.784, 0.729)
const EAR_DEEP := Color(0.949, 0.686, 0.616)
const INK := Color(0.157, 0.118, 0.098)
const SCARF := Color(0.855, 0.290, 0.235)
const SCARF_DARK := Color(0.722, 0.216, 0.176)
## The lighter red the chevron banding on the scarf ends is picked out in.
const SCARF_TRIM := Color(0.957, 0.639, 0.573)
const TAIL_TIP := Color(0.549, 0.361, 0.220)
const NOSE := Color(0.898, 0.612, 0.573)
## The eye is not a black dot. On the reference it is a dark rim around a warm
## amber iris with two white catchlights, and that is most of what makes the
## face read as looking at something rather than as having two holes in it.
const EYE := Color(0.259, 0.157, 0.106)
const IRIS := Color(0.722, 0.420, 0.129)
const EYE_LIGHT := Color(1, 1, 1)
const BLUSH := Color(0.976, 0.729, 0.667)

const OUTLINE := 0.011


# ---------------------------------------------------------------------------
# polygon helpers
# ---------------------------------------------------------------------------

static func ellipse(c: Vector2, r: Vector2, segments: int = 26,
		from_deg: float = 0.0, to_deg: float = 360.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var a0 := deg_to_rad(from_deg)
	var a1 := deg_to_rad(to_deg)
	for i in segments + 1:
		var a := lerpf(a0, a1, float(i) / float(segments))
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts


## A teardrop: wide and round at the base, tapering to a rounded point. This is
## the ear, and it is one closed shape - there is no seam to hide because there
## is no cut.
static func teardrop(base: Vector2, width: float, height: float,
		fullness: float = 0.8) -> PackedVector2Array:
	var steps := 26
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		# Already wide where it meets the head, fullest in the middle, closing to
		# a rounded point. One closed outline, so there is no base to hide.
		var w := width * 0.5 * pow(sin(PI * (0.16 + 0.84 * t)), fullness)
		var y := height * t
		left.append(base + Vector2(-w, y))
		right.append(base + Vector2(w, y))
	var pts := PackedVector2Array()
	pts.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		pts.append(right[i])
	return pts


## Rounded blob from a set of radii around a centre - the workhorse for heads,
## bodies and cheeks. `bumps` adds the fur tufts the reference draws.
static func blob(c: Vector2, r: Vector2, segments: int = 34,
		bumps: int = 0, bump_size: float = 0.0, bump_phase: float = 0.0
		) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var rad := Vector2(r.x, r.y)
		if bumps > 0:
			# A raised cosine, not a clipped one. `max(0, cos)` looks like the same
			# idea but it has a corner everywhere it meets the clamp, and those
			# corners survive at any segment count - the head came out looking
			# chipped from stone rather than drawn.
			var s := 1.0 + bump_size * (0.5 + 0.5 * cos(float(bumps) * a + bump_phase))
			rad *= s
		pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	return pts


## A tapering limb from a to b: a capsule with different end radii.
static func limb(a: Vector2, b: Vector2, r0: float, r1: float,
		segments: int = 12) -> PackedVector2Array:
	var dir := (b - a)
	if dir.length() < 1e-5:
		dir = Vector2.UP
	dir = dir.normalized()
	var n := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	for i in segments + 1:
		var t := PI * float(i) / float(segments)
		pts.append(a + n * cos(t) * r0 - dir * sin(t) * r0)
	for i in segments + 1:
		var t2 := PI * float(i) / float(segments)
		pts.append(b - n * cos(t2) * r1 + dir * sin(t2) * r1)
	return pts


## A curved tapering tail, swept along an arc.
static func sweep(from: Vector2, ctrl: Vector2, to: Vector2,
		r0: float, r1: float, steps: int = 16) -> PackedVector2Array:
	var spine: Array[Vector2] = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		spine.append(from.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in spine.size():
		var t2 := float(i) / float(spine.size() - 1)
		var r := lerpf(r0, r1, t2)
		var d: Vector2
		if i == 0:
			d = (spine[1] - spine[0]).normalized()
		elif i == spine.size() - 1:
			d = (spine[i] - spine[i - 1]).normalized()
		else:
			d = (spine[i + 1] - spine[i - 1]).normalized()
		var nrm := Vector2(-d.y, d.x)
		left.append(spine[i] + nrm * r)
		right.append(spine[i] - nrm * r)
	var out := PackedVector2Array()
	out.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		out.append(right[i])
	return out


# ---------------------------------------------------------------------------
# mesh building
# ---------------------------------------------------------------------------

static func _mesh_from(poly: PackedVector2Array, z: float) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, 1))
	for i in idx:
		var p := poly[i]
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(p.x, p.y, z))
	return st.commit()


static func _flat_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## One drawn shape: the ink outline, then the fill on top of it.
##
## The outline is a real offset of the polygon rather than a scaled copy, so it
## keeps an even weight all the way round however the shape is proportioned -
## which is what makes the result look drawn rather than stamped.
static func shape(parent: Node3D, poly: PackedVector2Array, fill: Color,
		scale: float, z: float = 0.0, outline: float = OUTLINE) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)

	if outline > 0.0:
		var grown := Geometry2D.offset_polygon(poly, outline)
		for g in grown:
			var om := _mesh_from(g, 0.0)
			if om:
				var mi := MeshInstance3D.new()
				mi.mesh = om
				mi.material_override = _flat_material(INK)
				mi.position = Vector3(0, 0, -0.0016)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				holder.add_child(mi)

	var fm := _mesh_from(poly, 0.0)
	if fm:
		var fi := MeshInstance3D.new()
		fi.mesh = fm
		fi.material_override = _flat_material(fill)
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(fi)

	holder.scale = Vector3(scale, scale, 1.0)
	holder.position.z = z
	return holder


## A shape with no outline - for details drawn inside another shape, where an
## outline would read as a crack.
static func detail(parent: Node3D, poly: PackedVector2Array, fill: Color,
		scale: float, z: float = 0.0) -> Node3D:
	return shape(parent, poly, fill, scale, z, 0.0)
