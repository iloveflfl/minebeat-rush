class_name CharacterAnimator
extends Node3D

## GDD 14 - the fennec, done the way Paper Mario does a character: the painted
## drawing itself, standing up in the 3D world, jointed so it can act.
##
## The art is the concept sheet, cut into pieces by tools/make_sprites.py:
## body, head (four expressions on one shared canvas) and the two ears. They are
## flat quads parented into a chain - ears hang off the head, the head hangs off
## the body - and everything animates in the character's own 2D plane. That is
## the whole trick: it stays a drawing from every angle the camera can take
## (which is only ever one, because CameraDirector never yaws), while still
## being able to lean, stretch, tilt its head and fan its ears.
##
## Two things a single flat sprite could not do, and the reason for the joints:
##   * hold a real pose at the apex, which is the moment the whole jump exists
##     to show
##   * carry follow-through - the ears and the head lag behind the body, which
##     is what makes a drawing feel like it has weight (GDD 14.2 [LOCK]: the
##     secondary channels only ever follow, they never drive the pose)

enum State { IDLE, DASH, ARMED, LAUNCH, APEX, FALL, LAND, GLIDE, CHEER }

const SPRITES := "res://assets/sprites/"
## Height of the whole character, in metres, against a 2 m tile.
const FIGURE_H := 2.35
## How far the head's chin sinks into the body's collar, as a fraction of the
## head's height. Hides the joint.
const NECK_OVERLAP := 0.22
const SCARF_SEGMENTS := 9
const SCARF_LEN := 0.17


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
var _body: Node3D
var _neck: Node3D
var _head: Node3D
var _head_quad: Node3D
var _head_mat: StandardMaterial3D
var _ears: Array[Node3D] = []
var _shadow: MeshInstance3D
var _scarf: Array[MeshInstance3D] = []
var _scarf_p := PackedVector3Array()
var _scarf_prev := PackedVector3Array()

var _tex: Dictionary = {}
var _meta: Dictionary = {}
var _rig_meta: Dictionary = {}
var _px := 0.004

# --- animation channels -----------------------------------------------------
var _s_lean := Spring.new()        ## whole-body roll, degrees
var _s_squash := Spring.new()      ## +1 tall and thin, -1 short and wide
var _s_rise := Spring.new()        ## body lifts off its feet
var _s_head := Spring.new()        ## head tilt
var _s_ear := Spring.new()         ## +1 straight up, -1 swept back
var _s_fan := Spring.new()         ## ears splayed outward
var _ear_lag := [Spring.new(), Spring.new()]
var _head_lag := Spring.new()

var _facing := 1.0
var _want_facing := 1.0
var _pinch := 1.0                  ## the paper turn: 1 face-on, 0 edge-on
var _prev_global := Vector3.ZERO
var _velocity := Vector3.ZERO
var _dash_dir := Vector3.ZERO
var _dash_t := 99.0
var _state_t := 0.0
var _time := 0.0
var _anticipate := 0.0
var _scarf_ready := false


func _ready() -> void:
	_load_art()
	_build()
	_prev_global = global_position


func _load_art() -> void:
	var f := FileAccess.open(SPRITES + "sprites.json", FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			_meta = (parsed as Dictionary).get("parts", {})
			_rig_meta = (parsed as Dictionary).get("rig", {})
	for n in ["body_front", "body_quarter", "body_side", "body_back", "rig_ear_l", "rig_ear_r",
			"rig_head_happy", "rig_head_surprised",
			"rig_head_determined", "rig_head_worried"]:
		var p: String = SPRITES + str(n) + ".png"
		if ResourceLoader.exists(p):
			_tex[n] = load(p)

	# One scale for every piece, so the cut-out reassembles at exactly the
	# proportions it was drawn at.
	var body_h := float((_meta.get("body_front", {}) as Dictionary).get("h", 309))
	var head_h := float((_meta.get("rig_head_happy", {}) as Dictionary).get("h", 150))
	var ear_h := float((_meta.get("rig_ear_l", {}) as Dictionary).get("h", 130))
	var stack := body_h + (head_h * (1.0 - NECK_OVERLAP)) + ear_h * 0.86
	_px = FIGURE_H / maxf(1.0, stack)


const PAPER_EDGE := preload("res://shaders/paper_edge.gdshader")
## How far the card sticks out past the drawing, as a fraction of the piece.
const EDGE_GROW := 0.045
## How far the card sits behind the drawing. Enough to catch the light as a
## separate surface, small enough that the piece still reads as one object.
const EDGE_DEPTH := 0.020


## One cut-out piece: the drawing, plus the card it was cut from.
##
## The card is the same silhouette in paper stock, a little larger and a little
## behind. That white rim is what makes a piece read as *paper* rather than as a
## sprite, and it is why the ears stopped looking severed - a cut edge is
## supposed to be visible, it just has to be visibly card.
func _paper(tex: Texture2D, size: Vector2) -> Node3D:
	var holder := Node3D.new()

	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = size * (1.0 + EDGE_GROW)
	back.mesh = bq
	var bm := ShaderMaterial.new()
	bm.shader = PAPER_EDGE
	bm.set_shader_parameter("shape", tex)
	bm.set_shader_parameter("paper_color", Color(1.0, 0.985, 0.95))
	back.material_override = bm
	back.position = Vector3(0, 0, -EDGE_DEPTH)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(back)

	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var q := QuadMesh.new()
	q.size = size
	var art := MeshInstance3D.new()
	art.name = "Art"
	art.mesh = q
	art.material_override = m
	art.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(art)
	return holder


func _art_of(piece: Node3D) -> MeshInstance3D:
	return piece.get_node("Art") as MeshInstance3D


func _size_of(name: String) -> Vector2:
	var d: Dictionary = _meta.get(name, {})
	return Vector2(float(d.get("w", 100)), float(d.get("h", 100))) * _px


func _build() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	# --- body: origin at the feet -------------------------------------------
	var bs := _size_of("body_front")
	_body = _paper(_tex.get("body_front"), bs)
	_body.position = Vector3(0, bs.y * 0.5, 0)
	_rig.add_child(_body)

	# --- head, sunk into the collar so the joint never shows -----------------
	var hs := _size_of("rig_head_happy")
	_neck = Node3D.new()
	_neck.position = Vector3(0, bs.y - hs.y * NECK_OVERLAP, 0.004)
	_rig.add_child(_neck)

	_head = Node3D.new()
	_neck.add_child(_head)
	_head_quad = _paper(_tex.get("rig_head_happy"), hs)
	_head_quad.position = Vector3(0, hs.y * 0.5, 0)
	_head_mat = _art_of(_head_quad).material_override as StandardMaterial3D
	_head.add_child(_head_quad)

	# --- ears, pivoting on their own bases ----------------------------------
	# The pivots come out of the cutting tool in source-image pixels, so they
	# land exactly where the ears were drawn rather than being eyeballed here.
	var frame: Dictionary = _rig_meta.get("_frame", {})
	var fw := float(frame.get("w", 285))
	for side in ["l", "r"]:
		var key: String = "rig_ear_" + str(side)
		var es := _size_of(key)
		var pm: Dictionary = _rig_meta.get(key, {})
		# The pivot sits *inside* the skull, not on the crown. An ear cut from a
		# sheet has a straight bottom edge; hinging it at the top of the head
		# leaves that edge sitting on the silhouette where it reads as a
		# severed ear. Hinged low and drawn behind, the head's own painted ear
		# roots cover the cut - which is how a paper doll is pinned together.
		var pivot := Node3D.new()
		pivot.position = Vector3(
			(float(pm.get("pivot_x", fw * 0.5)) - fw * 0.5) * _px,
			hs.y * 0.52,
			-0.008)
		_head.add_child(pivot)
		var quad: Node3D = _paper(_tex.get(key), es)
		quad.position = Vector3(0, es.y * 0.5, 0)
		pivot.add_child(quad)
		_ears.append(pivot)

	_build_shadow()
	_build_scarf()
	_s_ear.snap(1.0)


func _build_shadow() -> void:
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.26, 0.17, 0.24, 0.34)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := CylinderMesh.new()
	disc.top_radius = 0.40
	disc.bottom_radius = 0.40
	disc.height = 0.02
	disc.radial_segments = 18
	_shadow = MeshInstance3D.new()
	_shadow.mesh = disc
	_shadow.material_override = sm
	_shadow.top_level = true
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


func _build_scarf() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Greybox.C_SCARF
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in SCARF_SEGMENTS:
		var w := lerpf(0.34, 0.15, float(i) / float(SCARF_SEGMENTS))
		var seg := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(w, 0.05, SCARF_LEN)
		seg.mesh = b
		seg.material_override = m
		seg.top_level = true
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		_scarf.append(seg)
		_scarf_p.append(Vector3.ZERO)
		_scarf_prev.append(Vector3.ZERO)


# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

## Every entry into a state picks a different take on it. A character that hits
## the identical pose 44 times in a row stops reading as a performance, which is
## the single loudest thing separating a rig that "works" from one that is alive.
var _variant := 0
var _idle_beat := 0.0
var _flick := 0.0


func set_state(s: State, g: LaunchController.Grade = LaunchController.Grade.PERFECT) -> void:
	if s != state:
		_state_t = 0.0
		_variant = randi() % 3
		# GDD 7.2 step 1: wind up before anything explosive.
		if s == State.LAUNCH:
			_anticipate = 0.08
	state = s
	grade = g
	_set_body(_body_for(s))
	_set_face(_face_for(s, g))


func notify_dash(dir: Vector2i) -> void:
	_dash_dir = Vector3(float(dir.x), 0.0, -float(dir.y))
	_dash_t = 0.0
	_anticipate = 0.04
	if dir.x != 0:
		_want_facing = 1.0 if dir.x > 0 else -1.0


func _face_for(s: State, g: LaunchController.Grade) -> String:
	match s:
		State.ARMED: return "surprised"
		State.LAUNCH: return "determined" if _variant != 2 else "surprised"
		State.APEX:
			# Four expressions were drawn; a jump that always pulls the same one
			# is three of them wasted.
			if g == LaunchController.Grade.PERFECT:
				return ["happy", "determined", "happy"][_variant]
			return "surprised" if _variant == 0 else "worried"
		State.FALL: return "surprised" if _variant != 1 else "worried"
		State.LAND: return "worried" if g == LaunchController.Grade.BAD else "happy"
		State.GLIDE: return "worried"
		State.CHEER: return "happy"
		State.DASH: return "determined"
	return "happy"


var _body_pose := "front"


## The sheet drew the animal four times with the limbs in four different
## places. Swapping which one is standing up is how a cut-out changes its arms
## and legs - there is nothing to rotate, so the pose has to come from the art.
func _set_body(pose: String) -> void:
	var key := "body_" + pose
	if _body_pose == pose or not _tex.has(key):
		return
	_body_pose = pose
	var bs := _size_of(key)
	var art := _art_of(_body)
	(art.mesh as QuadMesh).size = bs
	(art.material_override as StandardMaterial3D).albedo_texture = _tex[key]
	var back := _body.get_child(0) as MeshInstance3D
	(back.mesh as QuadMesh).size = bs * (1.0 + EDGE_GROW)
	(back.material_override as ShaderMaterial).set_shader_parameter("shape", _tex[key])
	_body.position = Vector3(0, bs.y * 0.5, 0)
	# The head rides on top of whichever body is up, so the collar keeps meeting
	# the chin no matter which one that is.
	var hs := _size_of("rig_head_happy")
	_neck.position = Vector3(0, bs.y - hs.y * NECK_OVERLAP, 0.004)


func _body_for(s: State) -> String:
	match s:
		State.LAUNCH:
			return "side" if _variant == 0 else "quarter"
		State.APEX:
			return ["front", "quarter", "side"][_variant]
		State.FALL:
			return "quarter" if _variant != 2 else "side"
		State.GLIDE:
			return "side"
		State.DASH:
			return "quarter"
		State.CHEER:
			return "quarter" if _variant == 1 else "front"
	return "front"


func _set_face(name: String) -> void:
	var key := "rig_head_" + name
	if not _tex.has(key):
		return
	if _head_mat:
		_head_mat.albedo_texture = _tex[key]
	# The card behind has to follow, or the paper edge keeps the old silhouette.
	var back := _head_quad.get_child(0) as MeshInstance3D
	if back and back.material_override is ShaderMaterial:
		(back.material_override as ShaderMaterial).set_shader_parameter("shape", _tex[key])


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

	_drive(dt)
	_apply(dt)
	_follow_through(dt)
	_update_scarf(dt)


## The authored key poses. One target set per state; the springs give the timing,
## the overshoot and the settle.
func _drive(dt: float) -> void:
	var lean := 0.0
	var squash := 0.0
	var rise := 0.0
	var head := 0.0
	var ear := 1.0
	var fan := 0.0
	var stiff := 180.0
	var damp := 17.0

	match state:
		State.IDLE:
			squash = sin(_time * 3.0) * 0.045
			head = sin(_time * 0.8) * 4.0
			ear = 1.0 + sin(_time * 2.2) * 0.06
			# An idle that only breathes is a mannequin. Every couple of seconds
			# it does something small and unrepeated instead.
			_idle_beat -= dt
			if _idle_beat <= 0.0:
				_idle_beat = randf_range(1.4, 3.2)
				_flick = 1.0
				_variant = randi() % 3
			_flick = maxf(0.0, _flick - dt * 2.4)
			match _variant:
				0:
					ear += _flick * 0.9                 # ear flick
				1:
					head += _flick * 22.0               # look around
				_:
					squash -= _flick * 0.16             # a little bob
					fan = _flick * 0.35
			stiff = 90.0

		State.DASH:
			var into := clampf(1.0 - _dash_t / Tuning.DASH_TIME, 0.0, 1.0)
			lean = -_dash_dir.x * 26.0 * into
			squash = 0.38 * into
			head = _dash_dir.x * 16.0 * into
			ear = -0.9
			stiff = 340.0
			damp = 21.0

		State.ARMED:
			squash = -0.10
			lean = sin(_time * 22.0) * 2.6
			head = 6.0
			ear = 1.3
			stiff = 260.0

		State.LAUNCH:
			squash = 0.85 if grade == LaunchController.Grade.PERFECT else 0.55
			rise = 0.10
			head = -12.0
			ear = -1.0
			if grade == LaunchController.Grade.BAD:
				lean = 34.0
			stiff = 430.0
			damp = 20.0

		State.APEX:
			# The pose the jump exists to show: the drawing opens out, the ears
			# fan wide, the head tips back, and it hangs there for a beat.
			squash = -0.18
			rise = 0.05
			lean = -6.0
			head = -18.0
			ear = 0.5
			fan = 1.0
			# Three takes on the same beat, so the apex is never the same twice.
			match _variant:
				0:
					lean = -6.0 + sin(_time * 2.2) * 5.0    # a slow proud turn
				1:
					squash = -0.26                          # wide open, arms out
					head = -24.0
				_:
					lean = 14.0                             # a cocky back-lean
					head = -10.0
			if grade == LaunchController.Grade.GOOD:
				lean = -16.0
			elif grade == LaunchController.Grade.BAD:
				lean = 150.0 * sin(_time * 2.4)
				fan = 0.4
				head = 12.0
			stiff = 110.0
			damp = 12.0

		State.FALL:
			squash = 0.34
			lean = 8.0
			head = 14.0
			ear = 1.1
			if grade == LaunchController.Grade.BAD:
				lean = 240.0 * sin(_time * 2.1)
			stiff = 150.0

		State.LAND:
			var lu := clampf(_state_t / 0.22, 0.0, 1.0)
			var punch := (1.0 - lu) * (1.0 - lu)
			squash = -0.62 * punch
			ear = 1.0 - 2.4 * punch
			fan = 0.8 * punch
			if grade == LaunchController.Grade.BAD:
				lean = 44.0 * punch
			stiff = 300.0
			damp = 14.0

		State.GLIDE:
			squash = -0.24
			lean = sin(_time * 2.7) * 24.0
			head = sin(_time * 3.3) * 12.0
			ear = 0.15
			fan = 1.0
			stiff = 70.0
			damp = 10.0

		State.CHEER:
			var hop := absf(sin(_time * 4.2))
			squash = -0.10 + hop * 0.34
			rise = hop * 0.16
			head = -12.0
			ear = 1.25
			fan = 0.5
			stiff = 130.0

	if _anticipate > 0.0:
		squash = -0.40
		rise = -0.05
		ear = 1.4
		lean *= -0.3

	_s_lean.step(lean, stiff, damp, dt)
	_s_squash.step(squash, stiff, damp, dt)
	_s_rise.step(rise, stiff, damp, dt)
	_s_head.step(head, stiff * 0.6, damp * 0.9, dt)
	_s_ear.step(ear, stiff * 0.5, damp * 0.8, dt)
	_s_fan.step(fan, stiff * 0.6, damp, dt)


func _apply(dt: float) -> void:
	# The paper turn: squash flat, flip, spring back out.
	var pinch_target := 1.0 if _facing == _want_facing else 0.0
	_pinch = move_toward(_pinch, pinch_target, dt * 11.0)
	if _pinch <= 0.03 and _facing != _want_facing:
		_facing = _want_facing
	if _facing == _want_facing:
		_pinch = move_toward(_pinch, 1.0, dt * 11.0)

	# Squash and stretch with the area roughly preserved, so it reads as the
	# drawing deforming rather than as a scale slider.
	var sy := 1.0 + _s_squash.v * 0.60
	var sx := 1.0 / maxf(0.25, sy)
	_rig.scale = Vector3(sx * maxf(0.02, _pinch) * _facing, sy, 1.0)
	_rig.rotation_degrees = Vector3(0, 0, _s_lean.v)
	_rig.position.y = _s_rise.v

	_head.rotation_degrees.z = _s_head.v + _head_lag.v

	var deck_y := _deck_y()
	var lift: float = maxf(0.0, global_position.y - deck_y)
	var f := clampf(1.0 - lift / 7.0, 0.0, 1.0)
	_shadow.visible = f > 0.02
	_shadow.global_position = Vector3(global_position.x, deck_y + 0.035, global_position.z)
	_shadow.scale = Vector3(0.6 + 0.4 * f, 1.0, 0.5 + 0.4 * f)
	(_shadow.material_override as StandardMaterial3D).albedo_color.a = 0.34 * f


func _deck_y() -> float:
	var p := get_parent()
	if p is PlayerMotor:
		var pm := p as PlayerMotor
		return pm.origin.y + pm.surface_height(pm.cell)
	return 0.0


## GDD 14.2 [LOCK]: the ears and the head only ever follow. Driven by how fast
## the body is actually moving, never by the state machine.
func _follow_through(dt: float) -> void:
	_head_lag.step(clampf(-_velocity.x * 2.2, -26.0, 26.0), 130.0, 14.0, dt)

	var vert := clampf(-_velocity.y * 1.6, -60.0, 60.0)
	var lat := clampf(-_velocity.x * 2.8, -50.0, 50.0)
	for i in _ears.size():
		var sx := -1.0 if i == 0 else 1.0
		var lag: float = _ear_lag[i].step(vert * 0.5 + lat * 0.4, 110.0, 12.0, dt)
		# Straight up when alert, swept back when moving fast, fanned wide open
		# at the apex and on a hard landing.
		var base := lerpf(46.0, -6.0, clampf(_s_ear.v * 0.5 + 0.5, 0.0, 1.0))
		var twitch := sin(_time * 5.4 + float(i) * 1.7) * 1.6
		_ears[i].rotation_degrees.z = sx * (base + _s_fan.v * 34.0) + lag * 0.45 + twitch


func _update_scarf(dt: float) -> void:
	if _scarf.is_empty():
		return
	var anchor := _neck.global_position + Vector3(0, 0.04, -0.06)
	if not _scarf_ready:
		for i in _scarf_p.size():
			_scarf_p[i] = anchor
			_scarf_prev[i] = anchor
		_scarf_ready = true

	var open := 1.0 if state == State.GLIDE else 0.0
	var drag := 0.90 - 0.14 * open
	var gravity := Vector3(0, -9.5 + 7.0 * open, 0)
	var breeze := Vector3(2.4 * sin(_time * 1.9) + 0.9, 0.6, -1.5 - 0.7 * open)
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
				_scarf_p[i] = a + d / l * SCARF_LEN
			if grounded and _scarf_p[i].y < floor_y:
				_scarf_p[i].y = floor_y
			# Always behind the paper: a ribbon drifting toward the camera
			# simply erases the character.
			_scarf_p[i].z = minf(_scarf_p[i].z, global_position.z - 0.05)

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



