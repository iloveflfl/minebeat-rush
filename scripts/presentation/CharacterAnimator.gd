class_name CharacterAnimator
extends Node3D

## GDD 14 - the fennec / kangaroo-rat mascot, built procedurally for greybox.
##
## GDD 14.2 [LOCK]: skeleton pose and secondary motion are separate systems.
## The big poses (crouch, smear, rocket stretch, apex opening, comedy flail) are
## authored here as target transforms; the ears and the red scarf are simulated
## and only ever *follow*. That separation is what makes GDD 7.2's "physics
## exact, animation exaggerated" possible - none of this touches the cell the
## player is actually on.

enum State { IDLE, DASH, ARMED, LAUNCH, APEX, FALL, LAND, GLIDE, CHEER }

## GDD 14.1: mascot proportions, sized against a 2 m tile so the silhouette is
## readable from the 45-degree reading camera without competing with the numbers.
const RIG_SCALE := 1.30
const SCARF_SEGMENTS := 8
const SCARF_LEN := 0.16 * RIG_SCALE
const NECK_HEIGHT := 0.80 * RIG_SCALE

var state: State = State.IDLE
var grade: LaunchController.Grade = LaunchController.Grade.PERFECT

var _body_root: Node3D          ## squash / stretch / lean lives here
var _torso: MeshInstance3D
var _head: Node3D
var _ears: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _tail: Node3D
var _scarf_nodes: Array[MeshInstance3D] = []
var _scarf_p: PackedVector3Array = PackedVector3Array()
var _scarf_prev: PackedVector3Array = PackedVector3Array()

var _prev_global := Vector3.ZERO
var _velocity := Vector3.ZERO
var _ear_lag := Vector2.ZERO
var _dash_dir := Vector3.ZERO
var _dash_t := 99.0
var _land_t := 99.0
var _time := 0.0
var _scarf_ready := false


func _ready() -> void:
	scale = Vector3.ONE * RIG_SCALE
	_build_rig()
	_prev_global = global_position
	for i in SCARF_SEGMENTS:
		_scarf_p.append(global_position)
		_scarf_prev.append(global_position)


# ---------------------------------------------------------------------------
# rig
# ---------------------------------------------------------------------------

func _build_rig() -> void:
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)

	var fur := Greybox.mat(Greybox.C_FUR, 0.85)
	var fur_dark := Greybox.mat(Greybox.C_FUR_DARK, 0.85)
	var belly := Greybox.mat(Greybox.C_BELLY, 0.8)
	var dark := Greybox.mat(Color(0.10, 0.09, 0.09), 0.5)
	var scarf := Greybox.mat(Greybox.C_SCARF, 0.7)

	# GDD 14.1: kangaroo-rat body - low, compressed, ready to explode upward.
	_torso = Greybox.mi(Greybox.capsule(0.27, 0.78), fur, Vector3(0, 0.52, 0))
	_torso.rotation_degrees = Vector3(90, 0, 0)
	_body_root.add_child(_torso)
	_body_root.add_child(Greybox.mi(Greybox.capsule(0.20, 0.52), belly, Vector3(0, 0.44, -0.13)))

	# Head
	_head = Node3D.new()
	_head.position = Vector3(0, 0.94, -0.08)
	_body_root.add_child(_head)
	_head.add_child(Greybox.mi(Greybox.sphere(0.25, 14), fur))
	_head.add_child(Greybox.mi(Greybox.capsule(0.12, 0.26), belly, Vector3(0, -0.05, -0.20)))
	_head.add_child(Greybox.mi(Greybox.sphere(0.045, 8), dark, Vector3(0, -0.02, -0.33)))
	for sx in [-1.0, 1.0]:
		_head.add_child(Greybox.mi(Greybox.sphere(0.055, 8), dark,
				Vector3(sx * 0.13, 0.05, -0.21)))

	# GDD 14.1: fennec ears. Oversized, and the loudest secondary-motion channel.
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 0.14, 0.18, 0.02)
		_head.add_child(pivot)
		var ear := Greybox.mi(Greybox.box(Vector3(0.10, 0.60, 0.30)), fur,
				Vector3(0, 0.30, 0))
		pivot.add_child(ear)
		pivot.add_child(Greybox.mi(Greybox.box(Vector3(0.06, 0.42, 0.20)), belly,
				Vector3(0, 0.26, -0.06)))
		pivot.add_child(Greybox.mi(Greybox.box(Vector3(0.11, 0.10, 0.31)), fur_dark,
				Vector3(0, 0.58, 0)))
		pivot.rotation_degrees = Vector3(-8, 0, sx * 12)
		_ears.append(pivot)

	# Hind legs
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.20, 0.30, 0.08)
		_body_root.add_child(leg)
		leg.add_child(Greybox.mi(Greybox.capsule(0.11, 0.34), fur, Vector3(0, -0.06, 0.02)))
		leg.add_child(Greybox.mi(Greybox.box(Vector3(0.15, 0.09, 0.42)), fur_dark,
				Vector3(0, -0.25, -0.10)))
		_legs.append(leg)

	# Forepaws
	for sx in [-1.0, 1.0]:
		_body_root.add_child(Greybox.mi(Greybox.capsule(0.06, 0.22), fur,
				Vector3(sx * 0.20, 0.60, -0.14)))

	# Tail
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.44, 0.22)
	_body_root.add_child(_tail)
	for i in 3:
		_tail.add_child(Greybox.mi(Greybox.capsule(0.075 - i * 0.012, 0.26),
				fur if i < 2 else belly, Vector3(0, -0.04 * i, 0.16 + 0.22 * i)))
	_tail.rotation_degrees = Vector3(-26, 0, 0)

	# GDD 14.1 / 10.2: the red scarf. Colour identity, speed line, and the thing
	# that saves the player when they miss the mine. Simulated in world space so
	# it never inherits the body's squash.
	for i in SCARF_SEGMENTS:
		var w := lerpf(0.30, 0.16, float(i) / float(SCARF_SEGMENTS)) * RIG_SCALE
		var seg := Greybox.mi(Greybox.box(Vector3(w, 0.07 * RIG_SCALE, SCARF_LEN)), scarf)
		seg.top_level = true
		add_child(seg)
		_scarf_nodes.append(seg)
	_body_root.add_child(Greybox.mi(Greybox.capsule(0.20, 0.10), scarf, Vector3(0, 0.80, -0.02)))


# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

func set_state(s: State, g: LaunchController.Grade = LaunchController.Grade.PERFECT) -> void:
	if s == State.LAND and state != State.LAND:
		_land_t = 0.0
	state = s
	grade = g


func notify_dash(dir: Vector2i) -> void:
	_dash_dir = Vector3(float(dir.x), 0.0, -float(dir.y))
	_dash_t = 0.0


func _process(delta: float) -> void:
	_time += delta
	_dash_t += delta
	_land_t += delta

	var g := global_position
	if delta > 0.0:
		_velocity = _velocity.lerp((g - _prev_global) / delta, 0.35)
	_prev_global = g

	# The dash pose is a one-shot smear that settles back into idle on its own,
	# so nothing outside has to remember to clear it.
	if state == State.DASH and _dash_t > 0.42:
		state = State.IDLE

	_update_pose(delta)
	_update_ears(delta)
	_update_scarf(delta)


## GDD 7.2 / 11.2: the authored poses. None of these change where the character
## is - only how the moment reads.
func _update_pose(delta: float) -> void:
	var target_scale := Vector3.ONE
	var target_rot := Vector3.ZERO
	var head_rot := Vector3.ZERO
	var tail_rot := Vector3(-26, 0, 0)
	var lerp_rate := 14.0

	match state:
		State.IDLE:
			var bob := sin(_time * 3.1) * 0.02
			target_scale = Vector3(1.0 - bob, 1.0 + bob, 1.0 - bob)
			head_rot = Vector3(sin(_time * 0.7) * 5.0, sin(_time * 0.43) * 16.0, 0)

		State.DASH:
			# Anticipation -> smear -> arrival, compressed into the dash window.
			var u := clampf(_dash_t / Tuning.DASH_TIME, 0.0, 1.4)
			var smear := maxf(0.0, 1.0 - u) * 1.0
			var stretch := 1.0 + 0.42 * smear
			var squash := 1.0 - 0.24 * smear
			if absf(_dash_dir.x) > 0.5:
				target_scale = Vector3(stretch, squash, squash)
				target_rot = Vector3(0, 0, -_dash_dir.x * 22.0 * smear)
			else:
				target_scale = Vector3(squash, squash, stretch)
				target_rot = Vector3(-18.0 * smear, 0, 0)
			target_rot.y = rad_to_deg(atan2(_dash_dir.x, _dash_dir.z)) * 0.25
			lerp_rate = 26.0

		State.ARMED:
			# Standing on a live charge. GDD 12.2: a held breath, ears up.
			var tremble := sin(_time * 22.0) * 0.012
			target_scale = Vector3(1.0 + tremble, 1.0 - tremble * 1.6, 1.0 + tremble)
			target_rot = Vector3(-6, 0, sin(_time * 17.0) * 2.5)
			head_rot = Vector3(14, sin(_time * 9.0) * 8.0, 0)

		State.LAUNCH:
			match grade:
				LaunchController.Grade.PERFECT:
					target_scale = Vector3(0.74, 1.52, 0.74)
					target_rot = Vector3(-24, 0, 0)
				LaunchController.Grade.GOOD:
					target_scale = Vector3(0.84, 1.34, 0.84)
					target_rot = Vector3(-20, 14, 10)
				_:
					target_scale = Vector3(1.06, 1.10, 1.06)
					target_rot = Vector3(-8, 46, 32)
			head_rot = Vector3(-16, 0, 0)
			tail_rot = Vector3(-64, 0, 0)

		State.APEX:
			# GDD 11.1: the pose opens, the scarf opens, the player breathes.
			match grade:
				LaunchController.Grade.PERFECT:
					target_scale = Vector3(1.10, 0.94, 1.10)
					target_rot = Vector3(16, 0, 0)
				LaunchController.Grade.GOOD:
					target_scale = Vector3(1.06, 0.96, 1.06)
					target_rot = Vector3(10, -22, -14)
				_:
					target_scale = Vector3(1.14, 0.90, 1.14)
					target_rot = Vector3(6, 150.0 * sin(_time * 3.0), 40)
			head_rot = Vector3(-8, 0, 0)
			tail_rot = Vector3(-10, 0, 0)
			lerp_rate = 8.0

		State.FALL:
			match grade:
				LaunchController.Grade.PERFECT:
					target_scale = Vector3(0.86, 1.24, 0.86)
					target_rot = Vector3(34, 0, 0)
				LaunchController.Grade.GOOD:
					target_scale = Vector3(0.92, 1.14, 0.92)
					target_rot = Vector3(28, 18, -12)
				_:
					target_scale = Vector3(1.0, 1.0, 1.0)
					target_rot = Vector3(20, 300.0 * sin(_time * 2.2), -55)
			head_rot = Vector3(12, 0, 0)

		State.LAND:
			var lu := clampf(_land_t / 0.26, 0.0, 1.0)
			var punch := (1.0 - lu) * (1.0 - lu)
			match grade:
				LaunchController.Grade.BAD:
					target_scale = Vector3(1.0 + punch * 0.5, 1.0 - punch * 0.45, 1.0 + punch * 0.3)
					target_rot = Vector3(-40.0 * punch, 0, 55.0 * punch)
				_:
					target_scale = Vector3(1.0 + punch * 0.34, 1.0 - punch * 0.34, 1.0 + punch * 0.2)
					target_rot = Vector3(6.0 * punch, 0, 0)
			lerp_rate = 20.0

		State.GLIDE:
			# GDD 10.2: low, unstable, comical - but still moving forward.
			target_scale = Vector3(1.12, 0.88, 1.06)
			target_rot = Vector3(-12 + sin(_time * 5.3) * 9.0, sin(_time * 3.7) * 24.0,
					sin(_time * 4.4) * 26.0)
			head_rot = Vector3(-20, 0, 0)
			tail_rot = Vector3(-70, 0, 0)
			lerp_rate = 7.0

		State.CHEER:
			var hop := absf(sin(_time * 4.0))
			target_scale = Vector3(1.0 - hop * 0.1, 1.0 + hop * 0.16, 1.0 - hop * 0.1)
			target_rot = Vector3(-8, sin(_time * 1.6) * 30.0, 0)
			head_rot = Vector3(-18, 0, 0)

	_body_root.scale = _body_root.scale.lerp(target_scale, clampf(lerp_rate * delta, 0, 1))
	_body_root.rotation_degrees = _body_root.rotation_degrees.lerp(
			target_rot, clampf(lerp_rate * delta, 0, 1))
	_head.rotation_degrees = _head.rotation_degrees.lerp(head_rot, clampf(9.0 * delta, 0, 1))
	_tail.rotation_degrees = _tail.rotation_degrees.lerp(tail_rot, clampf(8.0 * delta, 0, 1))

	# Hind legs tuck in the air, extend for the landing.
	var tuck := 0.0
	match state:
		State.LAUNCH: tuck = 1.0
		State.APEX: tuck = 0.55
		State.FALL: tuck = 0.15
		State.GLIDE: tuck = 0.7
	for i in _legs.size():
		var leg := _legs[i]
		leg.rotation_degrees = leg.rotation_degrees.lerp(
				Vector3(78.0 * tuck, 0, 0), clampf(10.0 * delta, 0, 1))


## GDD 7.2 step 3 / 14.2: ears lie back against acceleration. Pure follow-through,
## never authored per state.
func _update_ears(delta: float) -> void:
	var local_v := _velocity
	var lag := Vector2(clampf(-local_v.x * 3.4, -55, 55), clampf(local_v.z * 3.0, -70, 70))
	if state == State.APEX:
		lag *= 0.35
	_ear_lag = _ear_lag.lerp(lag, clampf(8.0 * delta, 0, 1))
	for i in _ears.size():
		var sx := -1.0 if i == 0 else 1.0
		var wob := sin(_time * 6.0 + float(i) * 2.1) * 3.0
		_ears[i].rotation_degrees = Vector3(
			-8.0 + _ear_lag.y + wob,
			0.0,
			sx * 12.0 + _ear_lag.x * 0.5 + wob * sx * 0.4)


## GDD 14.2 [LOCK]: the scarf tip is procedural. A verlet ribbon anchored at the
## neck, pushed by the character's own motion.
func _update_scarf(delta: float) -> void:
	var anchor := global_position + Vector3(0, NECK_HEIGHT, 0)
	if not _scarf_ready:
		for i in SCARF_SEGMENTS:
			_scarf_p[i] = anchor
			_scarf_prev[i] = anchor
		_scarf_ready = true

	var dt := clampf(delta, 1.0 / 240.0, 1.0 / 30.0)
	var open := 1.0 if state == State.GLIDE else 0.0
	var drag := 0.90 - 0.16 * open
	var gravity := Vector3(0, -9.0 + 7.0 * open, 0)
	# A standing breeze down the canyon, so the scarf reads as a trailing ribbon
	# instead of hanging like a rope even when the character is still.
	var breeze := Vector3(0.9 * sin(_time * 1.7), 0.6, 5.0 + 3.0 * open)
	var push := -_velocity * (0.9 + 0.8 * open) + breeze

	for i in SCARF_SEGMENTS:
		var cur := _scarf_p[i]
		var vel := (cur - _scarf_prev[i]) * drag
		_scarf_prev[i] = cur
		_scarf_p[i] = cur + vel + (gravity + push) * dt * dt * 30.0

	# On the deck the ribbon must not sink through the stone.
	var grounded := state in [State.IDLE, State.DASH, State.ARMED, State.LAND, State.CHEER]
	var floor_y := global_position.y + 0.10

	# Two constraint passes keep the ribbon from stretching.
	for _pass in 2:
		_scarf_p[0] = anchor
		for i in range(1, SCARF_SEGMENTS):
			var a := _scarf_p[i - 1]
			var b := _scarf_p[i]
			var d := b - a
			var l := d.length()
			if l > 1e-5:
				_scarf_p[i] = a + d / l * SCARF_LEN
			if grounded and _scarf_p[i].y < floor_y:
				_scarf_p[i].y = floor_y

	for i in range(1, SCARF_SEGMENTS):
		var a := _scarf_p[i - 1]
		var b := _scarf_p[i]
		var seg := _scarf_nodes[i]
		var mid := (a + b) * 0.5
		var dir := b - a
		if dir.length() < 1e-4:
			dir = Vector3(0, 0, 1)
		dir = dir.normalized()
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		seg.global_position = mid
		seg.look_at(mid + dir, up, true)
	_scarf_nodes[0].visible = false
