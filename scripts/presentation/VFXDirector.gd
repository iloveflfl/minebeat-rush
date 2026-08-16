class_name VFXDirector
extends Node3D

## GDD 16 - the world reacting, in cartoon grammar.
##
## Cartoon effects are built out of *shapes that grow and shrink*, not out of
## fading textures: a fat white puff that swells and then pops out of existence
## reads as smoke far better than a translucent sprite does, and it survives cel
## shading, which has no soft edges to blend into.
##
## GDD 15.3 reading order still rules everything: number > covered tile >
## obstacle > character > VFX > background. `suppress` is raised by GameDirector
## during a reading phase (GDD 23), and every effect scales itself down or skips
## entirely while it is up. A great explosion that hides a clue is a failed
## explosion (GDD 30).

var suppress := false
## Development: kill every effect so the geometry underneath can be inspected.
var disabled := false

class _Transient extends RefCounted:
	var node: Node3D
	var t := 0.0
	var life := 1.0
	var kind := ""
	var mat: StandardMaterial3D
	var grow := 1.0
	var peak := 0.35          ## fraction of life at which a puff is biggest
	var light: OmniLight3D
	var light_energy := 0.0
	var spin := Vector3.ZERO
	var vel := Vector3.ZERO
	var gravity := 0.0

var _live: Array[_Transient] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _alpha_mat(color: Color, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.blend_mode = (BaseMaterial3D.BLEND_MODE_ADD if additive
			else BaseMaterial3D.BLEND_MODE_MIX)
	m.disable_receive_shadows = true
	return m


func _push(node: Node3D, life: float, kind: String, opts: Dictionary = {}) -> _Transient:
	add_child(node)
	var tr := _Transient.new()
	tr.node = node
	tr.life = life
	tr.kind = kind
	tr.mat = opts.get("mat", null)
	tr.grow = opts.get("grow", 1.0)
	tr.peak = opts.get("peak", 0.35)
	tr.light = opts.get("light", null)
	tr.spin = opts.get("spin", Vector3.ZERO)
	tr.vel = opts.get("vel", Vector3.ZERO)
	tr.gravity = opts.get("gravity", 0.0)
	if tr.light != null:
		tr.light_energy = tr.light.light_energy
	_live.append(tr)
	return tr


func _process(delta: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var tr := _live[i]
		tr.t += delta
		var u := clampf(tr.t / tr.life, 0.0, 1.0)
		if is_instance_valid(tr.node):
			match tr.kind:
				"ring":
					var s := 1.0 + tr.grow * pow(u, 0.4)
					tr.node.scale = Vector3(s, 1.0 + u * 0.5, s)
					if tr.mat:
						tr.mat.albedo_color.a = (1.0 - u) * (1.0 - u) * 0.8
				"flash":
					if tr.light:
						tr.light.light_energy = tr.light_energy * pow(1.0 - u, 2.4)
					if tr.mat:
						tr.mat.albedo_color.a = pow(1.0 - u, 1.6)
					tr.node.scale = Vector3.ONE * (0.2 + tr.grow * pow(u, 0.35))
				"star":
					# Snap out, hang for a beat, then whip back to nothing.
					var s2 := (pow(u / tr.peak, 0.35) if u < tr.peak
							else pow(1.0 - (u - tr.peak) / (1.0 - tr.peak), 1.6))
					tr.node.scale = Vector3.ONE * maxf(0.001, s2 * tr.grow)
					tr.node.rotation += tr.spin * delta
				"puff":
					# Swell fast, hold fat, then pop out. No fading: a cartoon
					# puff *leaves*, it does not dissolve.
					var s3 := (pow(u / tr.peak, 0.5) if u < tr.peak
							else 1.0 - pow((u - tr.peak) / (1.0 - tr.peak), 2.2))
					tr.node.scale = Vector3.ONE * maxf(0.001, s3 * tr.grow)
					tr.vel.y -= tr.gravity * delta
					tr.node.position += tr.vel * delta
					tr.vel = tr.vel.lerp(Vector3.ZERO, clampf(2.4 * delta, 0, 1))
					tr.node.rotation += tr.spin * delta
				"chunk":
					tr.vel.y -= tr.gravity * delta
					tr.node.position += tr.vel * delta
					tr.node.rotation += tr.spin * delta
					if u > 0.7:
						tr.node.scale = Vector3.ONE * tr.grow * (1.0 - (u - 0.7) / 0.3)
				"streak":
					tr.node.position += tr.vel * delta
					tr.node.scale = Vector3(1.0 + u * 2.2, 1.0 - u * 0.7, 1.0 - u * 0.7)
					if tr.mat:
						tr.mat.albedo_color.a = (1.0 - u) * 0.7
			if u >= 1.0:
				tr.node.queue_free()
				_live.remove_at(i)
		else:
			_live.remove_at(i)
		i -= 1


# ---------------------------------------------------------------------------
# cartoon primitives
# ---------------------------------------------------------------------------

## Basis whose +Y axis points along `dir`. Built by hand rather than with
## look_at(), which needs the node to already be inside the tree.
func _aim_y(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.97 else Vector3.FORWARD
	var x := up.cross(dir).normalized()
	var z := dir.cross(x).normalized()
	return Basis(x, dir, z)


## A spiky comic burst. Cones radiating from a core, snapped out in three frames.
func _star(pos: Vector3, radius: float, color: Color, life: float, spikes: int = 11) -> void:
	var n := Node3D.new()
	n.position = pos
	var mat := Greybox.mat(color, 1.0, 0.0, 1.4, 3.2)
	n.add_child(Greybox.mi(Greybox.sphere(radius * 0.42, 10), mat))
	for i in spikes:
		var a := TAU * float(i) / float(spikes) + _rng.randf_range(-0.15, 0.15)
		var b := _rng.randf_range(-0.6, 0.6)
		var len_ := radius * _rng.randf_range(0.8, 1.45)
		var dir := Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b)).normalized()
		var spike := Greybox.mi(Greybox.cone(radius * 0.24, len_, 5), mat, dir * len_ * 0.5)
		spike.basis = _aim_y(dir)
		n.add_child(spike)
	n.scale = Vector3.ONE * 0.001
	_push(n, life, "star", {"grow": 1.0, "peak": 0.16,
			"spin": Vector3(0, _rng.randf_range(-2.0, 2.0), 0)})


## Fat rounded smoke. Kirby smoke is a cluster of circles, never a haze.
func _puffs(pos: Vector3, count: int, spread: float, size: float, color: Color,
		life: float, rise: float = 2.0) -> void:
	var n := maxi(1, int(count * (0.3 if suppress else 1.0)))
	for i in n:
		var a := TAU * float(i) / float(n) + _rng.randf_range(-0.4, 0.4)
		var r := spread * _rng.randf_range(0.35, 1.0)
		var node := Node3D.new()
		node.position = pos + Vector3(cos(a) * r, _rng.randf_range(0.0, spread * 0.4),
				sin(a) * r)
		var s := size * _rng.randf_range(0.65, 1.25)
		var mat := Greybox.mat(color.lightened(_rng.randf_range(0.0, 0.25)), 1.0, 0.0, 0.0, 2.0)
		# Three overlapping balls read as one lumpy cloud from any angle.
		for k in 3:
			node.add_child(Greybox.mi(Greybox.sphere(s * _rng.randf_range(0.6, 1.0), 9), mat,
					Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s) * 0.6,
							_rng.randf_range(-s, s)) * 0.7))
		node.scale = Vector3.ONE * 0.001
		_push(node, life * _rng.randf_range(0.8, 1.2), "puff", {
			"grow": 1.0,
			"peak": _rng.randf_range(0.25, 0.4),
			"vel": Vector3(cos(a), 0.0, sin(a)) * spread * 1.4
					+ Vector3(0, rise * _rng.randf_range(0.5, 1.4), 0),
			"gravity": 1.2,
			"spin": Vector3(0, _rng.randf_range(-1.5, 1.5), 0),
		})


## Solid tumbling debris. Reads as weight, which is what sells the explosion.
func _chunks(pos: Vector3, count: int, speed: float, color: Color, life: float) -> void:
	var n := maxi(1, int(count * (0.35 if suppress else 1.0)))
	for i in n:
		var a := _rng.randf_range(0.0, TAU)
		var s := _rng.randf_range(0.18, 0.5)
		var node := Greybox.mi(Greybox.box(Vector3(s, s * 0.7, s * 1.2)),
				Greybox.mat(color, 1.0, 0.0, 0.0, 2.0), Vector3.ZERO)
		var holder := Node3D.new()
		holder.position = pos + Vector3(0, 0.4, 0)
		holder.add_child(node)
		_push(holder, life, "chunk", {
			"grow": 1.0,
			"vel": Vector3(cos(a), _rng.randf_range(0.7, 2.0), sin(a)) * speed
					* _rng.randf_range(0.4, 1.0),
			"gravity": 22.0,
			"spin": Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9),
					_rng.randf_range(-9, 9)),
		})


func _shock_ring(pos: Vector3, color: Color, grow: float, life: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.85
	t.outer_radius = 1.3
	t.rings = 22
	t.ring_segments = 6
	var m := _alpha_mat(color)
	var node := Node3D.new()
	node.position = pos + Vector3(0, 0.18, 0)
	node.add_child(Greybox.mi(t, m))
	_push(node, life, "ring", {"mat": m, "grow": grow})


# ---------------------------------------------------------------------------
# GDD 16 event table
# ---------------------------------------------------------------------------

## The charge fires. GDD 12.2 / 16: short bright flash, comic star, a shock ring
## on the deck, fat smoke and real debris - and the character silhouette punching
## straight out of the middle of it.
func mine_launch(pos: Vector3, big: bool = false) -> void:
	if disabled:
		return
	var k := 2.0 if big else 1.0

	var flash := Node3D.new()
	flash.position = pos + Vector3(0, 1.0, 0)
	var fm := _alpha_mat(Color(1.0, 0.95, 0.72, 1.0))
	flash.add_child(Greybox.mi(Greybox.sphere(0.75 * k, 12), fm))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.84, 0.48)
	lamp.light_energy = 22.0 * k
	lamp.omni_range = 40.0 * k
	flash.add_child(lamp)
	_push(flash, 0.26, "flash", {"mat": fm, "grow": 1.7, "light": lamp})

	_star(pos + Vector3(0, 1.2, 0), 1.7 * k, Color(1.0, 0.93, 0.55), 0.34, 11)
	_star(pos + Vector3(0, 1.2, 0), 1.0 * k, Color(1.0, 1.0, 0.95), 0.20, 8)
	_shock_ring(pos, Color(1.0, 0.92, 0.68, 0.55), 2.8 * k, 0.32)
	# GDD 16: the smoke opens as a *ring* at deck level so the character punches
	# up through the hole in the middle of it. A ball of smoke centred on the
	# character would swallow the silhouette, which is the one thing this shot
	# exists to show.
	_puffs(pos + Vector3(0, 0.3, 0), 9, 3.4 * k, 0.78 * k, Color(0.99, 0.96, 0.90), 0.8, 1.5)
	_puffs(pos + Vector3(0, 0.2, 0), 6, 2.2 * k, 0.6 * k, Color(0.99, 0.89, 0.72), 0.62, 1.0)
	_chunks(pos, 16, 11.0 * k, Greybox.C_DECK_EDGE, 1.5)


func landing(pos: Vector3, grade: LaunchController.Grade) -> void:
	if disabled:
		return
	var power := 1.35 if grade == LaunchController.Grade.BAD else 1.0
	_shock_ring(pos, Color(0.95, 0.88, 0.70, 0.45), 1.9 * power, 0.32)
	_puffs(pos, 6, 1.5 * power, 0.6 * power, Color(1.0, 0.96, 0.86), 0.5, 1.2)
	if grade == LaunchController.Grade.PERFECT:
		_star(pos + Vector3(0, 0.6, 0), 1.5, Color(1.0, 0.98, 0.80), 0.24, 7)
	elif grade == LaunchController.Grade.BAD:
		# GDD 11.2: BAD is "ungracefully successful", so it gets the comedy dust.
		_puffs(pos, 5, 2.2, 0.75, Color(0.96, 0.90, 0.78), 0.75, 2.2)
		_chunks(pos, 4, 4.0, Greybox.C_DECK_EDGE, 0.9)


func scarf_deploy(pos: Vector3) -> void:
	if disabled:
		return
	_star(pos + Vector3(0, 0.9, 0), 2.0, Greybox.C_SCARF.lightened(0.25), 0.3, 9)
	_puffs(pos, 5, 1.4, 0.6, Color(1.0, 0.82, 0.80), 0.6, 1.6)


func collapse_burst(pos: Vector3, width: float) -> void:
	if disabled:
		return
	_puffs(pos, 10, width * 0.45, width * 0.16, Color(0.98, 0.92, 0.80), 1.3, 1.4)
	_chunks(pos, 12, width * 0.55, Greybox.C_DECK_EDGE, 1.8)


## GDD 7.2 step 4: a kick of grit and a smear line as the character snaps onto
## the destination cell. Small, but it is what makes a 0.09 s dash feel like a
## move instead of a teleport.
func dash_puff(pos: Vector3, dir: Vector3 = Vector3.ZERO) -> void:
	if suppress:
		return
	_puffs(pos - dir * 0.4, 2, 0.5, 0.24, Color(1.0, 0.95, 0.84), 0.3, 0.8)
	if dir.length() > 0.1:
		var m := _alpha_mat(Color(1.0, 0.97, 0.88, 0.7), false)
		var streak := Node3D.new()
		streak.position = pos + Vector3(0, 0.55, 0) - dir * 0.7
		streak.add_child(Greybox.mi(Greybox.box(Vector3(1.1, 0.10, 0.10)), m))
		# The bar is long on X, so aim X down the dash direction.
		var b := _aim_y(dir)
		streak.basis = Basis(b.y, -b.x, b.z)
		_push(streak, 0.18, "streak", {"mat": m, "vel": dir * 2.0})

