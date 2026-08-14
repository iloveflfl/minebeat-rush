class_name VFXDirector
extends Node3D

## GDD 16 - the world reacting.
##
## GDD 15.3 [priority]: number > covered tile > obstacle > character > VFX >
## background. Every effect here is short, low, or aimed away from the deck the
## player is about to read. `suppress` is raised by GameDirector during a
## reading phase (GDD 23) and effects downscale themselves accordingly.

var suppress := false

class _Transient extends RefCounted:
	var node: Node3D
	var t := 0.0
	var life := 1.0
	var kind := ""
	var mat: StandardMaterial3D
	var grow := 1.0
	var light: OmniLight3D
	var light_energy := 0.0

var _live: Array[_Transient] = []


func _alpha_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


func _push(node: Node3D, life: float, kind: String, mat: StandardMaterial3D = null,
		grow: float = 1.0, light: OmniLight3D = null) -> void:
	add_child(node)
	var tr := _Transient.new()
	tr.node = node
	tr.life = life
	tr.kind = kind
	tr.mat = mat
	tr.grow = grow
	tr.light = light
	if light != null:
		tr.light_energy = light.light_energy
	_live.append(tr)


func _process(delta: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var tr := _live[i]
		tr.t += delta
		var u := clampf(tr.t / tr.life, 0.0, 1.0)
		if is_instance_valid(tr.node):
			match tr.kind:
				"ring":
					var s := 1.0 + tr.grow * pow(u, 0.45)
					tr.node.scale = Vector3(s, 1.0 + u * 0.4, s)
					if tr.mat:
						tr.mat.albedo_color.a = (1.0 - u) * (1.0 - u) * 0.75
				"flash":
					if tr.light:
						tr.light.light_energy = tr.light_energy * pow(1.0 - u, 2.2)
					if tr.mat:
						tr.mat.albedo_color.a = pow(1.0 - u, 2.0)
					tr.node.scale = Vector3.ONE * (1.0 + tr.grow * u)
				"fade":
					if tr.mat:
						tr.mat.albedo_color.a = 1.0 - u
			if u >= 1.0:
				tr.node.queue_free()
				_live.remove_at(i)
		else:
			_live.remove_at(i)
		i -= 1


# ---------------------------------------------------------------------------
# GDD 16 event table
# ---------------------------------------------------------------------------

## The mine fires. Short bright flash, a shock ring on the deck, a dust cone,
## and the character silhouette punching out of it.
func mine_launch(pos: Vector3, big: bool = false) -> void:
	var scale := 2.0 if big else 1.0

	var flash := Node3D.new()
	flash.position = pos + Vector3(0, 1.0, 0)
	var fm := _alpha_mat(Color(1.0, 0.86, 0.55, 1.0))
	flash.add_child(Greybox.mi(Greybox.sphere(1.5 * scale, 12), fm))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.80, 0.45)
	lamp.light_energy = 26.0 * scale
	lamp.omni_range = 34.0 * scale
	flash.add_child(lamp)
	_push(flash, 0.42, "flash", fm, 2.2, lamp)

	# The ring is deliberately small and short. A wide flat disc would sit on
	# top of the clue row and hide it (GDD 15.3 / 30).
	_shock_ring(pos, Color(1.0, 0.90, 0.62, 0.5), 2.6 * scale, 0.30)
	_burst(pos, 44, 13.0 * scale, Color(0.85, 0.70, 0.45), 2.4)
	_burst(pos, 22, 8.0 * scale, Color(0.35, 0.31, 0.27), 3.0)


func landing(pos: Vector3, grade: LaunchController.Grade) -> void:
	var power := 1.0
	if grade == LaunchController.Grade.BAD:
		power = 1.35
	_shock_ring(pos, Color(0.88, 0.80, 0.62, 0.40), 2.4 * power, 0.36)
	_burst(pos, 20, 4.5 * power, Color(0.82, 0.72, 0.55), 1.1)


func scarf_deploy(pos: Vector3) -> void:
	_shock_ring(pos, Color(0.90, 0.35, 0.28, 0.45), 2.0, 0.35)


func collapse_burst(pos: Vector3, width: float) -> void:
	_burst(pos, 40, width * 0.8, Color(0.78, 0.68, 0.52), 3.2)
	_burst(pos, 18, width * 0.5, Color(0.42, 0.36, 0.30), 3.6)


## GDD 7.2 step 4: a small kick of grit as the character snaps onto the cell.
func dash_puff(pos: Vector3) -> void:
	if suppress:
		return
	_burst(pos, 5, 1.4, Color(0.86, 0.78, 0.60), 0.5)


func _shock_ring(pos: Vector3, color: Color, grow: float, life: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.25
	t.rings = 24
	t.ring_segments = 6
	var m := _alpha_mat(color)
	var node := Node3D.new()
	node.position = pos + Vector3(0, 0.14, 0)
	node.add_child(Greybox.mi(t, m))
	_push(node, life, "ring", m, grow)


func _burst(pos: Vector3, amount: int, speed: float, color: Color, life: float) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 62.0
	pm.initial_velocity_min = speed * 0.35
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -17.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.10
	pm.scale_max = 0.34
	p.process_material = pm
	p.draw_pass_1 = Greybox.box(Vector3(0.2, 0.2, 0.2))
	p.material_override = Greybox.mat(color)
	p.amount = maxi(1, int(amount * (0.35 if suppress else 1.0)))
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.position = pos + Vector3(0, 0.3, 0)
	_push(p, life + 0.4, "none")
	p.emitting = true
