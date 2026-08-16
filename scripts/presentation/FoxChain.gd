class_name FoxChain
extends RefCounted

## Parts that bend, as opposed to parts that pivot.
##
## Everything in the rig until now was a rigid polygon rotating about a point.
## That is fine for a forearm and completely wrong for the three things that
## actually define this character's silhouette: ears nearly as tall as it is, a
## long tail, and a scarf whose two ends reach the floor. A rigid ear cannot
## whip. A rigid scarf cannot stream. Rotating them about their roots only ever
## swings a stiff plank, which is why the figure read as assembled no matter how
## well the poses were tuned.
##
## Each of those parts is a strand of points simulated with Verlet integration
## in the rig's own 2D plane, with the drawn shape generated along the strand
## every frame. Two properties are worth having explicitly:
##
##   * The strand is driven by the *character's* acceleration, injected as a
##     pseudo-force, not by any authored animation. So the scarf trails on the
##     way up and overshoots at the top because the character moved, not because
##     someone drew it doing that - and it stays correct for launches, glides
##     and landings that nobody anticipated.
##   * Stiffness is one number per strand, blending between cloth and cartilage.
##     The same code gives an ear that holds its shape but lags, and a scarf end
##     that hangs and swings.


## A chain of points that keeps its segment lengths and, optionally, its shape.
class Strand:
	var p: PackedVector2Array          ## current positions, strand-local
	var q: PackedVector2Array          ## previous positions (Verlet)
	var rest: PackedVector2Array       ## the pose it wants to hold
	var seg: float                     ## segment length
	var stiffness: float               ## 0 cloth, 1 cartilage
	var damping := 0.86

	func _init(rest_shape: PackedVector2Array, stiff: float) -> void:
		rest = rest_shape
		stiffness = stiff
		p = rest_shape.duplicate()
		q = rest_shape.duplicate()
		seg = 0.0
		if rest.size() > 1:
			seg = rest[0].distance_to(rest[1])

	## One step. `accel` is the pseudo-force from the character's own motion and
	## `gravity` is world down expressed in this strand's local frame - both have
	## to be transformed by the caller, because the rig leans and flips and the
	## strand has no idea that it does.
	func step(dt: float, accel: Vector2, gravity: Vector2) -> void:
		var a := (accel + gravity) * dt * dt
		for i in range(1, p.size()):
			var v := (p[i] - q[i]) * damping
			q[i] = p[i]
			p[i] += v + a
		# The root is welded to whatever it hangs off.
		p[0] = rest[0]
		q[0] = rest[0]
		_solve()

	func _solve() -> void:
		# A few relaxation passes. Segment length first, because a strand that
		# stretches reads as rubber immediately, then the pull back toward the
		# rest pose, which is what stops an ear from folding in half.
		for _pass in 4:
			for i in range(1, p.size()):
				var d := p[i] - p[i - 1]
				var l := d.length()
				if l > 1e-6:
					p[i] = p[i - 1] + d * (seg / l)
			if stiffness > 0.0:
				for i in range(1, p.size()):
					# Rest attraction is applied in the parent's frame, so a bent
					# strand straightens from the root outward rather than
					# snapping back as a whole.
					var want := p[i - 1] + (rest[i] - rest[i - 1])
					p[i] = p[i].lerp(want, stiffness)

	## Shove the whole strand, for an impact the character should feel.
	func kick(v: Vector2) -> void:
		for i in range(1, p.size()):
			var f := float(i) / float(p.size() - 1)
			q[i] -= v * f


# ---------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------

## The outline of a tapered ribbon laid along a strand, with a rounded tip.
##
## Widths are per node, so one call draws an ear that is broad at the skull and
## pointed at the tip, and another draws a scarf end of even width.
static func ribbon(p: PackedVector2Array, widths: PackedFloat32Array,
		inflate: float = 0.0) -> PackedVector2Array:
	var n := p.size()
	if n < 2:
		return PackedVector2Array()
	var nrm: Array[Vector2] = []
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
		nrm.append(Vector2(-d.y, d.x))
	var out := PackedVector2Array()
	for i in n - 1:
		out.append(p[i] + nrm[i] * (widths[i] + inflate))
	# Rounded cap, so the tip is a drawn point rather than a cut edge.
	#
	# The sweep runs left rim -> tip -> right rim, which is the only ordering
	# that keeps the ring simple. Starting it at the tip instead walks forward,
	# back across the ribbon and out behind it: the polygon self-intersects,
	# triangulation returns nothing, and the entire ear silently fails to draw.
	var tip_d := (p[n - 1] - p[n - 2]).normalized()
	var tw: float = widths[n - 1] + inflate
	for k in 7:
		var a := PI * float(k) / 6.0
		out.append(p[n - 1] + nrm[n - 1] * cos(a) * tw + tip_d * sin(a) * tw * 0.9)
	for i in range(n - 2, -1, -1):
		out.append(p[i] - nrm[i] * (widths[i] + inflate))
	return out


## Position and frame at a fraction along the strand, for anything that has to
## ride on it - a pattern band, a fringe, an inner-ear streak.
static func frame_at(p: PackedVector2Array, t: float) -> Array:
	var n := p.size()
	var x: float = clampf(t, 0.0, 1.0) * float(n - 1)
	var i: int = clampi(int(floor(x)), 0, n - 2)
	var f := x - float(i)
	var pos := p[i].lerp(p[i + 1], f)
	var d := (p[i + 1] - p[i]).normalized()
	return [pos, d, Vector2(-d.y, d.x)]


## A straight rest strand pointing in `dir`, used to seed ears, tails and scarves.
static func straight(root: Vector2, dir: Vector2, length: float,
		nodes: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d := dir.normalized()
	for i in nodes:
		out.append(root + d * (length * float(i) / float(nodes - 1)))
	return out


## A rest strand bent along an arc - the tail's resting curl, the scarf's drape.
static func arc(root: Vector2, from_deg: float, to_deg: float, length: float,
		nodes: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pos := root
	out.append(pos)
	var stepl := length / float(nodes - 1)
	for i in range(1, nodes):
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i - 1) / float(nodes - 2)))
		pos += Vector2(cos(a), sin(a)) * stepl
		out.append(pos)
	return out


## One drawn strand: an ImmediateMesh rebuilt every frame, ink under fill.
class Ribbon:
	var node: MeshInstance3D
	var _mesh: ImmediateMesh
	var _mats: Array[StandardMaterial3D] = []
	var _ink: StandardMaterial3D

	func _init(parent: Node3D, z: float, inked: bool) -> void:
		_mesh = ImmediateMesh.new()
		node = MeshInstance3D.new()
		node.mesh = _mesh
		node.position.z = z
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		if inked:
			_ink = _flat(FoxArt.INK)

	static func _flat(c: Color) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return m

	func begin() -> void:
		_mesh.clear_surfaces()

	## Layers are emitted in call order, each a little in front of the last, so
	## an inner-ear shape or a pattern band lands on top of the ribbon it rides.
	func layer(poly: PackedVector2Array, colour: Color, scale: float,
			depth: float) -> void:
		if poly.size() < 3:
			return
		var idx := Geometry2D.triangulate_polygon(poly)
		if idx.is_empty():
			return
		var mat := _pick(colour)
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
		for i in idx:
			var pt := poly[i]
			_mesh.surface_set_normal(Vector3(0, 0, 1))
			_mesh.surface_add_vertex(Vector3(pt.x * scale, pt.y * scale, depth))
		_mesh.surface_end()

	func ink(poly: PackedVector2Array, scale: float, depth: float) -> void:
		if _ink == null:
			return
		layer_with(poly, _ink, scale, depth)

	func layer_with(poly: PackedVector2Array, mat: StandardMaterial3D,
			scale: float, depth: float) -> void:
		if poly.size() < 3:
			return
		var idx := Geometry2D.triangulate_polygon(poly)
		if idx.is_empty():
			return
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
		for i in idx:
			var pt := poly[i]
			_mesh.surface_set_normal(Vector3(0, 0, 1))
			_mesh.surface_add_vertex(Vector3(pt.x * scale, pt.y * scale, depth))
		_mesh.surface_end()

	## Materials are cached by colour. Creating one per frame per layer is the
	## kind of thing that does not show up until the profiler is opened.
	func _pick(c: Color) -> StandardMaterial3D:
		for m in _mats:
			if m.albedo_color.is_equal_approx(c):
				return m
		var nm := _flat(c)
		_mats.append(nm)
		return nm
