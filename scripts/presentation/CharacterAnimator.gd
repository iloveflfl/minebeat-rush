class_name CharacterAnimator
extends Node3D

## GDD 14 - the fennec, as an actually articulated character.
##
## The concept sheet is the *reference*, not the asset. Proportions, palette and
## silhouette are taken from it and rebuilt as a jointed rig, because a flat
## cut-out cannot do the things this game needs a character to do: hold a real
## pose at the apex, fold its legs to launch, splay its ears on a hard landing,
## or have volume so it stops intersecting the scenery. The one thing that *is*
## used directly is the drawn face - four expressions, on a plate on the head,
## because that is where the character lives and primitives cannot fake it.
##
## Motion is built on springs rather than lerps. A lerp arrives and stops; a
## spring overshoots slightly and settles, which is what reads as weight. On top
## of the authored key poses there are three procedural layers - ear lag, tail
## chain, scarf ribbon - and per GDD 14.2 [LOCK] those only ever follow: they
## never feed back into the pose or the cell the player is standing on.

enum State { IDLE, DASH, ARMED, LAUNCH, APEX, FALL, LAND, GLIDE, CHEER }

const SPRITES := "res://assets/sprites/"

# Proportions read off the sheet: the ears are nearly half the animal.
const H := 2.70                    ## total height, against a 2 m tile
const HIP_Y := 0.56
const CHEST_Y := 1.35
const HEAD_Y := 1.72
const HEAD_R := 0.34
const EAR_BASE_Y := 1.90
const EAR_LEN := 0.82


class Spring:
	var v := 0.0
	var vel := 0.0
	func step(target: float, stiff: float, damp: float, dt: float) -> float:
		vel += ((target - v) * stiff - vel * damp) * dt
		v += vel * dt
		return v
	func snap(x: float) -> void:
		v = x
		vel = 0.0


var state: State = State.IDLE
var grade: LaunchController.Grade = LaunchController.Grade.PERFECT

var _rig: Node3D
var _hips: Node3D
var _torso: Node3D
var _neck: Node3D
var _head: Node3D
var _face: MeshInstance3D
var _ears: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _tail: Array[Node3D] = []
var _shadow: MeshInstance3D
var _scarf: Array[MeshInstance3D] = []
var _scarf_p := PackedVector3Array()
var _scarf_prev := PackedVector3Array()
var _face_tex: Dictionary = {}
var _face_mat: StandardMaterial3D

# --- animation channels -----------------------------------------------------
var _s_pitch := Spring.new()       ## body lean, degrees
var _s_roll := Spring.new()
var _s_yaw := Spring.new()         ## which way the character is turned
var _s_squash := Spring.new()      ## +1 tall/thin, -1 short/wide
var _s_crouch := Spring.new()      ## hips drop
var _s_legs := Spring.new()        ## 0 straight, 1 fully folded
var _s_arms := Spring.new()        ## -1 back, 0 rest, +1 up and out
var _s_head := Spring.new()
var _s_ear := Spring.new()         ## +1 up alert, -1 swept back
var _s_open := Spring.new()        ## limbs spread (apex / glide)

var _ear_lag := [Spring.new(), Spring.new()]
var _tail_lag := [Spring.new(), Spring.new(), Spring.new()]

var _prev_global := Vector3.ZERO
var _velocity := Vector3.ZERO
var _dash_dir := Vector3.ZERO
var _dash_t := 99.0
var _state_t := 0.0
var _time := 0.0
var _anticipate := 0.0             ## counts down through the wind-up
var _scarf_ready := false


func _ready() -> void:
	_load_faces()
	_build()
	_prev_global = global_position


func _load_faces() -> void:
	for n in ["happy", "surprised", "determined", "worried"]:
		var p: String = SPRITES + "faceonly_" + str(n) + ".png"
		if ResourceLoader.exists(p):
			_face_tex[n] = load(p)


# ---------------------------------------------------------------------------
# rig
# ---------------------------------------------------------------------------

func _fur(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.specular = 0.0
	return m


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build() -> void:
	var fur := _fur(Greybox.C_FUR)
	var dark := _fur(Greybox.C_FUR_DARK)
	var belly := _fur(Greybox.C_BELLY)
	var pink := _fur(Color(0.97, 0.76, 0.68))
	var scarf_mat := _fur(Greybox.C_SCARF)

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	_hips = _pivot(_rig, Vector3(0, HIP_Y, 0))

	# --- legs: the kangaroo-rat engine. Big folded thighs, long feet. --------
	for sx in [-1.0, 1.0]:
		var leg := _pivot(_hips, Vector3(sx * 0.17, 0.0, 0.02))
		leg.add_child(_part(Greybox.capsule(0.115, 0.30), fur, Vector3(0, -0.13, 0)))
		var foot := _part(Greybox.box(Vector3(0.15, 0.075, 0.34)), belly,
				Vector3(0, -0.30, -0.09))
		leg.add_child(foot)
		_legs.append(leg)

	# --- torso ---------------------------------------------------------------
	_torso = _pivot(_hips, Vector3(0, 0.0, 0))
	var body_h := CHEST_Y - HIP_Y
	_torso.add_child(_part(Greybox.capsule(0.235, body_h * 0.86), fur,
			Vector3(0, body_h * 0.5, 0)))
	_torso.add_child(_part(Greybox.capsule(0.175, body_h * 0.66), belly,
			Vector3(0, body_h * 0.46, 0.11)))
	# The scarf knot, worn where the sheet wears it.
	_torso.add_child(_part(Greybox.cyl(0.235, 0.15, 14), scarf_mat,
			Vector3(0, body_h + 0.02, 0)))

	for sx2 in [-1.0, 1.0]:
		var arm := _pivot(_torso, Vector3(sx2 * 0.21, body_h * 0.72, 0.03))
		arm.add_child(_part(Greybox.capsule(0.062, 0.20), fur, Vector3(0, -0.09, 0)))
		arm.add_child(_part(Greybox.sphere(0.072, 8), belly, Vector3(0, -0.20, 0.01)))
		_arms.append(arm)

	# --- tail: three joints, whipped by a spring chain ----------------------
	var t_parent := _pivot(_torso, Vector3(0, 0.10, 0.20))
	for i in 3:
		var seg := _pivot(t_parent, Vector3(0, 0, 0.0 if i == 0 else 0.20))
		var r := 0.072 - i * 0.012
		seg.add_child(_part(Greybox.capsule(r, 0.20),
				dark if i == 2 else fur, Vector3(0, 0, 0.10)))
		_tail.append(seg)
		t_parent = seg

	# --- head ----------------------------------------------------------------
	_neck = _pivot(_torso, Vector3(0, CHEST_Y - HIP_Y, 0))
	_head = _pivot(_neck, Vector3(0, HEAD_Y - CHEST_Y, 0))
	_head.add_child(_part(Greybox.sphere(HEAD_R, 16), fur, Vector3.ZERO))
	_head.add_child(_part(Greybox.capsule(0.115, 0.16), belly, Vector3(0, -0.05, 0.20)))

	# The drawn face, on a plate across the front of the head. Unshaded so the
	# artwork arrives exactly as painted.
	_face_mat = StandardMaterial3D.new()
	_face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_face_mat.alpha_scissor_threshold = 0.5
	_face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_face_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_face_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_face_mat.albedo_texture = _face_tex.get("happy")
	var fq := QuadMesh.new()
	fq.size = Vector2(0.60, 0.34)
	_face = MeshInstance3D.new()
	_face.mesh = fq
	_face.material_override = _face_mat
	_face.position = Vector3(0, -0.015, HEAD_R * 0.80)
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(_face)

	# --- ears: the loudest channel on the whole character -------------------
	for sx3 in [-1.0, 1.0]:
		var ear := _pivot(_head, Vector3(sx3 * 0.13, EAR_BASE_Y - HEAD_Y, -0.01))
		var shell := _part(Greybox.cone(0.155, EAR_LEN, 10), fur,
				Vector3(0, EAR_LEN * 0.5, 0))
		shell.scale = Vector3(1.0, 1.0, 0.46)
		ear.add_child(shell)
		var inner := _part(Greybox.cone(0.105, EAR_LEN * 0.82, 10), pink,
				Vector3(0, EAR_LEN * 0.46, 0.035))
		inner.scale = Vector3(1.0, 1.0, 0.40)
		ear.add_child(inner)
		_ears.append(ear)

	# --- contact shadow ------------------------------------------------------
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.26, 0.17, 0.24, 0.36)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := CylinderMesh.new()
	disc.top_radius = 0.36
	disc.bottom_radius = 0.36
	disc.height = 0.02
	disc.radial_segments = 18
	_shadow = MeshInstance3D.new()
	_shadow.mesh = disc
	_shadow.material_override = sm
	_shadow.top_level = true
	add_child(_shadow)

	_build_scarf()
	_s_ear.snap(1.0)


func _build_scarf() -> void:
	var mat := _fur(Greybox.C_SCARF)
	for i in 9:
		var w := lerpf(0.30, 0.13, float(i) / 9.0)
		var seg := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(w, 0.05, 0.16)
		seg.mesh = b
		seg.material_override = mat
		seg.top_level = true
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		_scarf.append(seg)
		_scarf_p.append(Vector3.ZERO)
		_scarf_prev.append(Vector3.ZERO)


# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

func set_state(s: State, g: LaunchController.Grade = LaunchController.Grade.PERFECT) -> void:
	if s != state:
		_state_t = 0.0
		# GDD 7.2 step 1: every explosive move gets a wind-up first. A launch or
		# a dash that starts from nothing has no weight.
		if s == State.LAUNCH or s == State.DASH:
			_anticipate = 0.07
	state = s
	grade = g
	_set_face(_face_for(s, g))


func notify_dash(dir: Vector2i) -> void:
	_dash_dir = Vector3(float(dir.x), 0.0, -float(dir.y))
	_dash_t = 0.0
	_anticipate = 0.05


func _face_for(s: State, g: LaunchController.Grade) -> String:
	match s:
		State.ARMED: return "surprised"
		State.LAUNCH: return "determined"
		State.APEX: return "happy" if g == LaunchController.Grade.PERFECT else "surprised"
		State.FALL: return "surprised"
		State.LAND: return "worried" if g == LaunchController.Grade.BAD else "happy"
		State.GLIDE: return "worried"
		State.CHEER: return "happy"
		State.DASH: return "determined"
	return "happy"


func _set_face(name: String) -> void:
	if _face_tex.has(name):
		_face_mat.albedo_texture = _face_tex[name]


# ---------------------------------------------------------------------------
# per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := clampf(delta, 1.0 / 240.0, 1.0 / 24.0)
	_time += dt
	_dash_t += dt
	_state_t += dt
	_anticipate = maxf(0.0, _anticipate - dt)

	var g := global_position
	if delta > 0.0:
		_velocity = _velocity.lerp((g - _prev_global) / delta, 0.35)
	_prev_global = g

	if state == State.DASH and _dash_t > 0.30:
		set_state(State.IDLE)

	_drive_pose(dt)
	_apply_pose(dt)
	_follow_through(dt)
	_update_scarf(dt)


## The authored key poses. One target set per state; the springs do the timing.
func _drive_pose(dt: float) -> void:
	var pitch := 0.0
	var roll := 0.0
	var yaw := 0.0
	var squash := 0.0
	var crouch := 0.0
	var legs := 0.35
	var arms := 0.0
	var head := 0.0
	var ear := 1.0
	var open := 0.0
	var stiff := 170.0
	var damp := 17.0

	match state:
		State.IDLE:
			squash = sin(_time * 3.0) * 0.05
			head = sin(_time * 0.7) * 5.0
			ear = 1.0 + sin(_time * 2.1) * 0.05
			stiff = 90.0

		State.DASH:
			var into := clampf(1.0 - _dash_t / Tuning.DASH_TIME, 0.0, 1.0)
			pitch = -26.0 * into
			roll = -_dash_dir.x * 20.0 * into
			yaw = _dash_dir.x * 46.0
			if _dash_dir.z < -0.5:
				yaw = 165.0
			squash = 0.42 * into
			legs = 0.15
			arms = -0.8
			ear = -0.9
			stiff = 340.0
			damp = 22.0

		State.ARMED:
			crouch = 0.30
			legs = 0.75
			arms = 0.35
			ear = 1.25
			roll = sin(_time * 21.0) * 2.4
			head = 8.0
			stiff = 260.0

		State.LAUNCH:
			# Full extension. Legs snap straight, arms drive back, body stretches.
			pitch = -18.0
			squash = 0.72 if grade == LaunchController.Grade.PERFECT else 0.45
			legs = 0.0
			arms = -1.0
			ear = -1.0
			head = -14.0
			if grade == LaunchController.Grade.BAD:
				roll = 30.0
				yaw = 40.0
			stiff = 420.0
			damp = 20.0

		State.APEX:
			# The pose the whole jump exists to show. Body opens to camera, arms
			# spread up and out, legs tuck, ears fan, head tips back.
			pitch = 12.0
			yaw = 0.0
			squash = -0.14
			crouch = -0.05
			legs = 0.95
			arms = 1.0
			open = 1.0
			ear = 0.55
			head = -16.0
			if grade == LaunchController.Grade.GOOD:
				roll = -12.0
			elif grade == LaunchController.Grade.BAD:
				roll = 150.0 * sin(_time * 2.6)
				open = 0.5
				head = 10.0
			stiff = 120.0
			damp = 13.0

		State.FALL:
			pitch = 34.0
			squash = 0.30
			legs = 0.30
			arms = -0.7
			ear = 0.9
			head = 10.0
			if grade == LaunchController.Grade.BAD:
				roll = 240.0 * sin(_time * 2.2)
			stiff = 150.0

		State.LAND:
			var lu := clampf(_state_t / 0.22, 0.0, 1.0)
			var punch := (1.0 - lu) * (1.0 - lu)
			squash = -0.55 * punch
			crouch = 0.45 * punch
			legs = 0.30 + 0.6 * punch
			arms = 0.5 * punch
			ear = 1.0 - 2.0 * punch
			open = 0.7 * punch
			if grade == LaunchController.Grade.BAD:
				roll = 46.0 * punch
			stiff = 300.0
			damp = 15.0

		State.GLIDE:
			# Flying-squirrel spread: wide, flat, and not remotely in control.
			pitch = -10.0 + sin(_time * 3.4) * 7.0
			roll = sin(_time * 2.6) * 22.0
			yaw = 28.0
			squash = -0.20
			legs = 0.25
			arms = 1.0
			open = 1.0
			ear = 0.2
			stiff = 70.0
			damp = 11.0

		State.CHEER:
			var hop := absf(sin(_time * 4.2))
			squash = -0.12 + hop * 0.30
			crouch = -0.18 * hop
			legs = 0.5 - 0.3 * hop
			arms = 1.0
			ear = 1.2
			head = -10.0
			stiff = 130.0

	# Wind-up: for a moment the character goes the *other* way first.
	if _anticipate > 0.0:
		crouch = 0.55
		legs = 0.9
		squash = -0.35
		arms = -0.4
		pitch *= -0.3

	_s_pitch.step(pitch, stiff, damp, dt)
	_s_roll.step(roll, stiff, damp, dt)
	_s_yaw.step(yaw, stiff * 0.7, damp, dt)
	_s_squash.step(squash, stiff, damp, dt)
	_s_crouch.step(crouch, stiff, damp, dt)
	_s_legs.step(legs, stiff, damp, dt)
	_s_arms.step(arms, stiff * 0.8, damp, dt)
	_s_head.step(head, stiff * 0.6, damp * 0.9, dt)
	_s_ear.step(ear, stiff * 0.5, damp * 0.8, dt)
	_s_open.step(open, stiff * 0.7, damp, dt)


func _apply_pose(_dt: float) -> void:
	# Squash and stretch, with volume roughly preserved so it never looks like
	# a plain scale.
	var s := _s_squash.v
	var sy := 1.0 + s * 0.55
	var sxz := 1.0 / sqrt(maxf(0.2, sy))
	_rig.scale = Vector3(sxz, sy, sxz)
	_rig.rotation_degrees = Vector3(_s_pitch.v, _s_yaw.v, _s_roll.v)

	_hips.position.y = HIP_Y - _s_crouch.v * 0.30

	var fold := _s_legs.v
	var spread := _s_open.v
	for i in _legs.size():
		var sx := -1.0 if i == 0 else 1.0
		_legs[i].rotation_degrees = Vector3(72.0 * fold, 0.0, sx * -22.0 * spread)

	for i in _arms.size():
		var sx2 := -1.0 if i == 0 else 1.0
		var a := _s_arms.v
		_arms[i].rotation_degrees = Vector3(
			-95.0 * maxf(0.0, a) + 55.0 * maxf(0.0, -a),
			0.0,
			sx2 * (18.0 + 62.0 * maxf(0.0, a) * (0.4 + 0.6 * spread)))

	_head.rotation_degrees.x = _s_head.v

	# Contact shadow stays flat on the deck and fades as the character rises.
	var deck_y := _deck_y()
	var lift: float = maxf(0.0, global_position.y - deck_y)
	var f := clampf(1.0 - lift / 7.0, 0.0, 1.0)
	_shadow.visible = f > 0.02
	_shadow.global_position = Vector3(global_position.x, deck_y + 0.035, global_position.z)
	_shadow.scale = Vector3(0.55 + 0.45 * f, 1.0, 0.5 + 0.4 * f)
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = 0.36 * f


func _deck_y() -> float:
	var p := get_parent()
	if p is PlayerMotor:
		var pm := p as PlayerMotor
		return pm.origin.y + pm.surface_height(pm.cell)
	return 0.0


## GDD 14.2 [LOCK]: ears and tail only ever follow. Driven by how fast the body
## is actually moving, never by the state machine.
func _follow_through(dt: float) -> void:
	var lat := clampf(-_velocity.x * 2.4, -55.0, 55.0)
	var vert := clampf(-_velocity.y * 1.5, -70.0, 70.0)

	for i in _ears.size():
		var sx := -1.0 if i == 0 else 1.0
		var target := vert + lat * sx * 0.35
		var lag: float = _ear_lag[i].step(target, 120.0, 13.0, dt)
		var base := lerpf(58.0, -14.0, clampf(_s_ear.v * 0.5 + 0.5, 0.0, 1.0))
		var fan := _s_open.v * 26.0
		_ears[i].rotation_degrees = Vector3(
			base + lag * 0.5 + sin(_time * 5.0 + float(i)) * 1.8,
			0.0,
			sx * (10.0 + fan + lag * 0.25))

	var whip := clampf(_velocity.z * 5.0, -50.0, 50.0)
	for i in _tail.size():
		var t: float = _tail_lag[i].step(whip - _s_pitch.v * 0.5, 90.0 - i * 18.0, 11.0, dt)
		_tail[i].rotation_degrees = Vector3(
			-24.0 + t * 0.4 + _s_open.v * 18.0,
			sin(_time * 3.0 + float(i) * 0.8) * 5.0,
			0.0)


func _update_scarf(dt: float) -> void:
	if _scarf.is_empty():
		return
	var anchor := _torso.global_position + Vector3(0, (CHEST_Y - HIP_Y) * 0.98, 0)
	if not _scarf_ready:
		for i in _scarf_p.size():
			_scarf_p[i] = anchor
			_scarf_prev[i] = anchor
		_scarf_ready = true

	var open := 1.0 if state == State.GLIDE else 0.0
	var drag := 0.90 - 0.14 * open
	var gravity := Vector3(0, -9.5 + 7.0 * open, 0)
	var breeze := Vector3(2.2 * sin(_time * 1.9) + 0.8, 0.6, -1.4 - 0.7 * open)
	var push := -_velocity * (0.85 + 0.8 * open) + breeze

	for i in _scarf_p.size():
		var cur := _scarf_p[i]
		var vel := (cur - _scarf_prev[i]) * drag
		_scarf_prev[i] = cur
		_scarf_p[i] = cur + vel + (gravity + push) * dt * dt * 30.0

	var grounded := state in [State.IDLE, State.DASH, State.ARMED, State.LAND, State.CHEER]
	var floor_y := _deck_y() + 0.08
	for _pass in 2:
		_scarf_p[0] = anchor
		for i in range(1, _scarf_p.size()):
			var a := _scarf_p[i - 1]
			var d := _scarf_p[i] - a
			var l := d.length()
			if l > 1e-5:
				_scarf_p[i] = a + d / l * 0.16
			if grounded and _scarf_p[i].y < floor_y:
				_scarf_p[i].y = floor_y

	for i in range(1, _scarf.size()):
		var a2 := _scarf_p[i - 1]
		var b2 := _scarf_p[i]
		var mid := (a2 + b2) * 0.5
		var dir := b2 - a2
		if dir.length() < 1e-4:
			dir = Vector3(0, 0, 1)
		dir = dir.normalized()
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		_scarf[i].global_position = mid
		_scarf[i].look_at(mid + dir, up, true)
	_scarf[0].visible = false

