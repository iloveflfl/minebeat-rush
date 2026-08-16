class_name FoxPuppet
extends RefCounted

## The character sheet itself, cut into layers and hung on a rig.
##
## Every previous version of this drew a fennec that resembled the reference.
## This one *is* the reference: each part below is the artist's own pixels,
## separated by tools/rig/cut_parts.py and reassembled here in the positions
## they occupied in the drawing. Nothing is redrawn, and nothing is approximated
## - if the layers are put back without moving any of them, the result is the
## original panel, pixel for pixel.
##
## Two things make that possible rather than merely desirable:
##
##   * Cut edges are hidden by layer order. Each ear is cut generously, well
##     inside the head, and the head is drawn over the join. The straight edge
##     is still there; it is never on screen.
##   * What one layer was covering is reconstructed underneath it. The neck
##     beneath the scarf is filled with the chest's own fur, so the scarf can
##     swing right off the body without opening a hole in it.
##
## Parts are quads in the panel's own coordinates, which keeps every number in
## this file checkable against the drawing with a ruler.

const DIR := "res://assets/character/parts/"

## Panel size, part boxes and the floor line, all read from what the cutter
## actually produced.
##
## These were constants until the matte changed and the panel came out four
## pixels narrower, at which point every part in the rig was offset by two
## pixels and nothing said so. Numbers that describe the output of a tool belong
## to that tool.
static var _meta: Dictionary = {}


static func meta() -> Dictionary:
	if _meta.is_empty():
		var f := FileAccess.open(DIR + "parts.json", FileAccess.READ)
		if f == null:
			push_error("FoxPuppet: parts.json missing - run tools/rig")
			return {"panel": [1, 1], "boxes": {}}
		_meta = JSON.parse_string(f.get_as_text())
	return _meta


static func boxes() -> Dictionary:
	return meta().get("boxes", {})


static func panel() -> Vector2:
	var p: Array = meta().get("panel", [1, 1])
	return Vector2(float(p[0]), float(p[1]))


## The line the character stands on: the bottom of the body piece.
static func floor_y() -> float:
	var b: Array = boxes().get("body", [0, 0, 1, 1])
	return float(b[3]) - 3.0


static func centre_x() -> float:
	return panel().x * 0.5


## Metres per panel pixel, for a figure of the given height in metres.
static func scale_for(height_m: float) -> float:
	return height_m / panel().y


## Panel pixel -> rig-local metres, with the feet on the floor and the centre
## line at x = 0.
static func to_local(px: Vector2, s: float) -> Vector2:
	return Vector2((px.x - centre_x()) * s, (floor_y() - px.y) * s)


static func _material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Nearest would crawl at this scale and the art is smooth; but alpha needs
	# to stay sharp, so the cut is done on the texture rather than by the filter.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Drawn after the deck's own transparent surfaces.
	#
	# The clue numbers are transparent decals lying on the tiles, and Godot sorts
	# transparent geometry by origin distance. Standing on a numbered tile put
	# the character and the number at nearly the same depth, and the sort would
	# occasionally pick the number - a blue fragment of a "1" appearing on the
	# fennec's chest. Priority takes the decision away from the tiebreak.
	m.render_priority = 4
	return m


## A flat textured quad carrying one part, hung on a pivot.
##
## `pivot` is where the part turns, in panel pixels - the neck for the head, the
## root for an ear. The quad is offset from the pivot by exactly as much as the
## drawing was, so a part at rest lands back where the artist put it.
static func quad(parent: Node3D, part: String, pivot: Vector2,
		parent_pivot: Vector2, s: float, z: float) -> Node3D:
	var box: Array = boxes()[part]
	var tex: Texture2D = load(DIR + part + ".png")
	if tex == null:
		push_error("FoxPuppet: missing part " + part)
		return null

	var holder := Node3D.new()
	holder.name = part
	# Positions are relative to whatever this hangs from, so a chain of parts
	# does not accumulate the same offset once per link.
	var lp := to_local(pivot, s) - to_local(parent_pivot, s)
	holder.position = Vector3(lp.x, lp.y, z)
	parent.add_child(holder)

	var w: float = (float(box[2]) - float(box[0])) * s
	var h: float = (float(box[3]) - float(box[1])) * s
	var centre_px := Vector2((float(box[0]) + float(box[2])) * 0.5,
			(float(box[1]) + float(box[3])) * 0.5)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(w, h)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(tex)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad's own centre, relative to the pivot it hangs from.
	var c := to_local(centre_px, s) - to_local(pivot, s)
	mi.position = Vector3(c.x, c.y, 0)
	holder.add_child(mi)
	return holder


## The straightened long parts, and the curves they were straightened from.
static var _strips: Dictionary = {}


static func strips() -> Dictionary:
	if _strips.is_empty():
		var f := FileAccess.open("res://assets/character/strips/strips.json",
				FileAccess.READ)
		if f == null:
			push_error("FoxPuppet: strips.json missing - run tools/rig")
			return {}
		_strips = JSON.parse_string(f.get_as_text())
	return _strips


## A part that bends: the same artwork, mapped onto a strip that follows a
## simulated strand instead of staying rectangular.
##
## This is the whole reason the sheet had to be cut rather than redrawn. A rigid
## quad can only swing the ear about its root like a signpost. Mapped along a
## strand, the drawing itself curves - the ear whips, the scarf streams - and it
## is still the artist's ear and the artist's scarf doing it.
class BendPart:
	var node: MeshInstance3D
	var strand: FoxChain.Strand
	var _mesh: ImmediateMesh
	var _mat: StandardMaterial3D
	var _half_w: float
	## Panel-space length of the source rectangle, in metres.
	var _len: float

	func _init(parent: Node3D, part: String, parent_pivot: Vector2, s: float,
			z: float, stiffness: float) -> void:
		var info: Dictionary = FoxPuppet.strips().get(part, {})
		if info.is_empty():
			push_error("FoxPuppet: no strip for " + part)
			return
		var tex: Texture2D = load("res://assets/character/strips/" + part + ".png")
		_mat = FoxPuppet._material(tex)
		var strip: Array = info["strip"]
		_half_w = float(strip[0]) * s * 0.5

		# The strand's rest shape is the curve the part was straightened from,
		# expressed relative to its own root. At rest the strip therefore bends
		# back into precisely the arc the artist drew - straightening loses
		# nothing, it only moves the curve from the pixels into the rig.
		root_at_top = bool(info.get("root_at_top", true))
		var nodes: Array = info["nodes"]
		var root_px := Vector2(float(nodes[0][0]), float(nodes[0][1]))
		var rest := PackedVector2Array()
		for nd in nodes:
			var q := FoxPuppet.to_local(Vector2(float(nd[0]), float(nd[1])), s) \
					- FoxPuppet.to_local(root_px, s)
			rest.append(q)
		_len = 0.0
		for i in range(1, rest.size()):
			_len += rest[i].distance_to(rest[i - 1])

		var holder := Node3D.new()
		holder.name = part
		var lp := FoxPuppet.to_local(root_px, s) \
				- FoxPuppet.to_local(parent_pivot, s)
		holder.position = Vector3(lp.x, lp.y, z)
		parent.add_child(holder)

		_mesh = ImmediateMesh.new()
		node = MeshInstance3D.new()
		node.mesh = _mesh
		node.material_override = _mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(node)

		strand = FoxChain.Strand.new(rest, stiffness)

	## Lateral shift of the strip's centre line, for fine alignment.
	var centre_offset := 0.0
	## Whether the part's root is the top row of its straightened strip.
	var root_at_top := true

	func draw() -> void:
		var p := strand.p
		var n := p.size()
		if n < 2:
			return
		_mesh.clear_surfaces()
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
		for i in n:
			var d: Vector2
			if i == 0:
				d = p[1] - p[0]
			elif i == n - 1:
				d = p[n - 1] - p[n - 2]
			else:
				d = p[i + 1] - p[i - 1]
			if d.length() < 1e-6:
				d = Vector2.UP
			d = d.normalized()
			var nr := Vector2(-d.y, d.x)
			var c := p[i] + nr * centre_offset
			var v := float(i) / float(n - 1)
			# The strand always runs root to tip. Which image row the root is
			# depends on how the part was drawn, so the texture is read in
			# whichever direction puts the root row at the root node.
			if not root_at_top:
				v = 1.0 - v
			_mesh.surface_set_uv(Vector2(0.0, v))
			_mesh.surface_add_vertex(Vector3(c.x - nr.x * _half_w,
					c.y - nr.y * _half_w, 0.0))
			_mesh.surface_set_uv(Vector2(1.0, v))
			_mesh.surface_add_vertex(Vector3(c.x + nr.x * _half_w,
					c.y + nr.y * _half_w, 0.0))
		_mesh.surface_end()
