class_name FoxFace
extends RefCounted

## The face as a set of numbers, not as four pictures.
##
## It used to be four prebuilt sets of eyes and mouths that were shown and
## hidden one at a time. That approach has a ceiling you hit immediately: it can
## only ever pop between states, and it can never be half surprised, never look
## at anything, and - the thing that reads as dead more than any other - never
## blink. Four faces is four faces however well each one is drawn.
##
## The technique that actually produces a living 2D character is the one Live2D
## is built on: name a handful of scalar parameters and let them drive vertex
## positions directly. Every shape in this file is generated analytically at a
## fixed vertex count from the same parameterisation, so the shapes are not
## alternatives to each other - they are the same shape at different parameter
## values, and every value in between is a real face too.
##
## Two consequences worth stating, because they are what the old approach could
## not do at any price:
##
##   * A blink is not a special case. It is `open` going to zero and back, and
##     it composes with whatever expression is running - you can blink while
##     surprised, and the eye stays surprised through the blink.
##   * The ink outline is not offset geometry. These shapes are analytic, so the
##     outline is the same formula evaluated slightly larger. It is exact, it
##     costs nothing, and it cannot break at extreme values the way a polygon
##     offset can.
##
## Coordinates are the head's local frame, the same one CharacterAnimator lays
## the skull out in.

## Vertices along each of the two arcs that make up an eye or a mouth. Both
## shapes are generated as an upper edge and a lower edge over the same
## parameter, which is what makes any two of them blendable.
const ARC := 14

## The eye's drawn size, shared so that anything positioned relative to the eye
## can ask how big it currently is instead of assuming.
const EYE_W := 0.058
const EYE_H := 0.036


## Half-aperture of an eye at a given openness - the same expression the shape
## function uses, exposed so callers do not have to duplicate it.
static func eye_aperture(open: float) -> float:
	return EYE_H * (0.22 + 0.78 * clampf(open, 0.0, 1.0))


## How far the eye reaches above its centre, arch included.
##
## The brow needs this. Parked at a fixed height it cleared a flat eye and sat
## straight across the top of a bowed one, cutting the peak out of the happy
## squint so each eye rendered as two disconnected strokes - a defect that looks
## exactly like a triangulation failure and is not one.
static func eye_top(open: float, bow: float) -> float:
	return bow * EYE_H + eye_aperture(open)


## Shape a lid-to-lid eye.
##
## `open`   0 shut, 1 wide.
## `bow`    curvature of the eye's centre line: positive arches it upward, which
##          is the closed-with-delight eye. It is deliberately independent of
##          `open`, so a happy squint and a blink are different motions rather
##          than the same one.
## `inflate` grows the shape evenly, for the ink outline.
static func eye(centre: Vector2, w: float, h: float, open: float,
		bow: float, inflate: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	# A shut eye is a bold drawn stroke, not a hairline. Two reasons for the
	# floor being this high: a polygon with near-zero area triangulates to
	# nothing and the eye vanishes at the bottom of every blink, and a closed
	# eye in this style is a confident brush mark - drawn thin it reads as a
	# crack in the face rather than as a contented squint.
	var ap := eye_aperture(open) * (h / EYE_H) + inflate
	var half := w * 0.5 + inflate
	for i in ARC + 1:
		var t := float(i) / float(ARC)
		var s := sin(PI * t)
		pts.append(centre + Vector2(lerpf(-half, half, t), bow * h * s + ap * pow(s, 0.62)))
	# The return edge skips both corners. They are already in the ring from the
	# outward pass, and repeating them puts two identical points side by side,
	# which is enough to make triangulate_polygon give up part-way and return a
	# fan covering only some of the shape - the eye came out as two loose dashes.
	for i in range(ARC - 1, 0, -1):
		var t2 := float(i) / float(ARC)
		var s2 := sin(PI * t2)
		pts.append(centre + Vector2(lerpf(-half, half, t2),
				bow * h * s2 - ap * 0.88 * pow(s2, 0.62)))
	return pts


## Shape a mouth.
##
## `smile`  +1 a full arc up at the corners, -1 the same arc inverted.
## `open`   how far the jaw drops.
static func mouth(centre: Vector2, w: float, h: float, open: float,
		smile: float, inflate: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var half := w * 0.5 + inflate
	var drop := h * (0.05 + 0.95 * clampf(open, 0.0, 1.0)) + inflate
	for i in ARC + 1:
		var t := float(i) / float(ARC)
		var s := sin(PI * t)
		pts.append(centre + Vector2(lerpf(-half, half, t), -smile * h * 0.62 * s + inflate))
	for i in range(ARC - 1, 0, -1):
		var t2 := float(i) / float(ARC)
		var s2 := sin(PI * t2)
		pts.append(centre + Vector2(lerpf(-half, half, t2),
				-smile * h * 0.62 * s2 - drop * pow(s2, 0.7)))
	return pts


## The fur-coloured lid laid over the top of an eye to narrow it.
##
## `angle` is applied by the caller as a rotation; this only shapes the disc.
static func lid(centre: Vector2, w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 22:
		var a := TAU * float(i) / 22.0
		pts.append(centre + Vector2(cos(a) * w, sin(a) * h))
	return pts


# ---------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------

## A face element that is rebuilt every frame from current parameter values.
##
## ImmediateMesh exists for exactly this: geometry whose vertices change per
## frame. Rebuilding an ArrayMesh instead would allocate a new resource sixty
## times a second per element and hand the collector the bill.
class Piece:
	var node: MeshInstance3D
	var _mesh: ImmediateMesh
	var _fill: StandardMaterial3D
	var _ink: StandardMaterial3D

	func _init(parent: Node3D, fill: Color, z: float, ink_width: float = 0.0) -> void:
		_mesh = ImmediateMesh.new()
		node = MeshInstance3D.new()
		node.mesh = _mesh
		node.position.z = z
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		_fill = _flat(fill)
		if ink_width > 0.0:
			_ink = _flat(FoxArt.INK)

	static func _flat(c: Color) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return m

	func set_fill(c: Color) -> void:
		_fill.albedo_color = c

	## `outline` is the same polygon evaluated larger by the caller, or empty.
	func draw(poly: PackedVector2Array, outline: PackedVector2Array,
			scale: float) -> void:
		_mesh.clear_surfaces()
		if _ink != null and outline.size() > 2:
			_emit(outline, _ink, scale, -0.0014)
		if poly.size() > 2:
			_emit(poly, _fill, scale, 0.0)

	func _emit(poly: PackedVector2Array, mat: StandardMaterial3D, scale: float,
			z: float) -> void:
		var idx := Geometry2D.triangulate_polygon(poly)
		if idx.is_empty():
			return
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
		for i in idx:
			var p := poly[i]
			_mesh.surface_set_normal(Vector3(0, 0, 1))
			_mesh.surface_add_vertex(Vector3(p.x * scale, p.y * scale, z))
		_mesh.surface_end()
