class_name CharacterAnimator
extends Node3D

## GDD 14 - the fennec, built the way Paper Mario builds a character: flat
## painted cut-outs standing up in a 3D world.
##
## The art comes straight off the concept sheet (tools/make_sprites.py cuts it).
## Head and body are separate quads, which is the whole reason for the approach:
##   * the head can lag, tilt and bob behind the body - GDD 14.2 [LOCK] wants
##     secondary motion kept apart from the authored pose, and here it is
##     literally a different object
##   * the face can be swapped for one of the four expressions without anyone
##     having to redraw the body
##   * turning is a pinch, not a rotation: the sprite squashes to nothing on the
##     turn and springs back holding the other view, which is exactly the trick
##     Paper Mario uses and it costs one scale channel
##
## The camera never yaws (CameraDirector [LOCK]), so the quads simply face +Z and
## are always square to the viewer - no billboarding needed at all.

enum State { IDLE, DASH, ARMED, LAUNCH, APEX, FALL, LAND, GLIDE, CHEER }

const SPRITES := "res://assets/sprites/"
## Height of the whole animal, in metres, against a 2 m tile.
const FIGURE_HEIGHT := 1.62
const SCARF_SEGMENTS := 9
const SCARF_LEN := 0.155

## pose -> which body/head art to stand up
const POSE_FRONT := "front"
const POSE_QUARTER := "quarter"
const POSE_SIDE := "side"
const POSE_BACK := "back"

var state: State = State.IDLE
var grade: LaunchController.Grade = LaunchController.Grade.PERFECT

var _root: Node3D                 ## squash / stretch / lean
var _body: MeshInstance3D
var _head: Node3D
var _head_quad: MeshInstance3D
var _shadow: MeshInstance3D
var _scarf: Array[MeshInstance3D] = []
var _scarf_p: PackedVector3Array = PackedVector3Array()
var _scarf_prev: PackedVector3Array = PackedVector3Array()

var _tex: Dictionary = {}         ## name -> Texture2D
var _meta: Dictionary = {}        ## from sprites.json
var _px: float = 0.003            ## metres per source pixel

var _pose := POSE_FRONT
var _face := ""
var _facing := 1.0                ## +1 art faces its drawn way, -1 mirrored
var _pinch := 1.0                 ## paper-turn: horizontal squash, 1 = flat on
var _want_facing := 1.0
var _want_pose := POSE_FRONT

var _prev_global := Vector3.ZERO
var _velocity := Vector3.ZERO
var _dash_dir := Vector3.ZERO
var _dash_t := 99.0
var _land_t := 99.0
var _time := 0.0
var _head_lag := Vector2.ZERO
var _scarf_ready := false


func _ready() -> void:
	_load_art()
	_build()
	_prev_global = global_position
	for i in SCARF_SEGMENTS:
		_scarf_p.append(global_position)
		_scarf_prev.append(global_position)


func _load_art() -> void:
	var f := FileAccess.open(SPRITES + "sprites.json", FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			_meta = (parsed as Dictionary).get("parts", {})
	for n in ["body_front", "body_quarter", "body_side", "body_back",
			"head_front", "head_quarter", "head_side", "head_back",
			"face_happy", "face_surprised", "face_determined", "face_worried"]:
		var path: String = SPRITES + str(n) + ".png"
		if ResourceLoader.exists(path):
			_tex[n] = load(path)

	var front: Dictionary = _meta.get("head_front", {})
	var full_h: float = float(front.get("full_h", 560))
	_px = FIGURE_HEIGHT / maxf(1.0, full_h)


## Paper: alpha-scissored so the cut edge stays crisp and never argues with the
## transparency sort, and unshaded so the painted art arrives exactly as drawn.
func _sprite_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.render_priority = 2
	return m


func _quad(tex: Texture2D) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _sprite_material(tex)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build() -> void:
	_root = Node3D.new()
	_root.name = "Paper"
	add_child(_root)

	# A painted contact shadow. An unshaded cut-out casts nothing useful, and
	# without this the character floats off the deck.
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.24, 0.16, 0.22, 0.34)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.02
	disc.radial_segments = 16
	_shadow.mesh = disc
	_shadow.material_override = sm
	_shadow.position = Vector3(0, 0.02, 0)
	add_child(_shadow)

	_body = _quad(_tex.get("body_front"))
	_root.add_child(_body)

	_head = Node3D.new()
	_root.add_child(_head)
	_head_quad = _quad(_tex.get("head_front"))
	_head.add_child(_head_quad)

	var scarf_mat := StandardMaterial3D.new()
	scarf_mat.albedo_color = Greybox.C_SCARF
	scarf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scarf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	scarf_mat.render_priority = 1
	for i in SCARF_SEGMENTS:
		var w := lerpf(0.30, 0.13, float(i) / float(SCARF_SEGMENTS))
		var seg := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(w, 0.055, SCARF_LEN)
		seg.mesh = b
		seg.material_override = scarf_mat
		seg.top_level = true
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		_scarf.append(seg)

	_apply_art(POSE_FRONT, "")


## Stand the two quads up at the right size and stack them at the seam recorded
## when the sheet was cut, so head and body meet exactly where the scarf is.
func _apply_art(pose: String, face: String) -> void:
	_pose = pose
	_face = face

	var body_name := "body_" + pose
	var head_name := "face_" + face if face != "" and _tex.has("face_" + face) else "head_" + pose
	if not _tex.has(body_name):
		return

	var bm: Dictionary = _meta.get(body_name, {})
	var hm_pose: Dictionary = _meta.get("head_" + pose, {})
	var hm: Dictionary = _meta.get(head_name, hm_pose)

	var bw := float(bm.get("w", 200)) * _px
	var bh := float(bm.get("h", 300)) * _px
	var full_h := float(hm_pose.get("full_h", 560))
	var pose_head_h := float(hm_pose.get("h", 280))

	# An expression head is drawn at its own size; match it to the pose head by
	# width so the ears stay the same scale no matter which face is showing.
	var hw_px := float(hm.get("w", 300))
	var hh_px := float(hm.get("h", 280))
	var head_scale := float(hm_pose.get("w", 300)) / maxf(1.0, hw_px)
	var hw := hw_px * head_scale * _px
	var hh := hh_px * head_scale * _px

	(_body.mesh as QuadMesh).size = Vector2(bw, bh)
	_body.material_override = _sprite_material(_tex[body_name])
	_body.position = Vector3(0, bh * 0.5, 0)

	(_head_quad.mesh as QuadMesh).size = Vector2(hw, hh)
	_head_quad.material_override = _sprite_material(_tex.get(head_name, _tex[body_name]))
	_head_quad.position = Vector3(0, hh * 0.5, 0)
	# The pose head's base sits this far up the full figure; the expression head
	# hangs from the same line.
	_head.position = Vector3(0, (full_h - pose_head_h) * _px, 0.01)

	_shadow.scale = Vector3(bw * 1.15, 1.0, bw * 0.85)


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
	if dir.x != 0:
		_want_facing = 1.0 if dir.x > 0 else -1.0


func _process(delta: float) -> void:
	_time += delta
	_dash_t += delta
	_land_t += delta

	var g := global_position
	if delta > 0.0:
		_velocity = _velocity.lerp((g - _prev_global) / delta, 0.35)
	_prev_global = g

	if state == State.DASH and _dash_t > 0.34:
		state = State.IDLE

	_choose_art()
	_update_pose(delta)
	_update_head(delta)
	_update_scarf(delta)


## GDD 14: which cut-out is standing up right now.
func _choose_art() -> void:
	var pose := POSE_FRONT
	var face := ""
	match state:
		State.IDLE:
			pose = POSE_FRONT
		State.DASH:
			if absf(_dash_dir.x) > 0.5:
				pose = POSE_SIDE
			elif _dash_dir.z < 0.0:
				pose = POSE_BACK       # running away from the camera
			else:
				pose = POSE_FRONT
		State.ARMED:
			pose = POSE_FRONT
			face = "surprised"
		State.LAUNCH:
			pose = POSE_QUARTER
			face = "determined"
		State.APEX:
			pose = POSE_FRONT
			face = "happy" if grade == LaunchController.Grade.PERFECT else "surprised"
		State.FALL:
			pose = POSE_QUARTER
			face = "surprised"
		State.LAND:
			pose = POSE_FRONT
			face = "happy" if grade != LaunchController.Grade.BAD else "worried"
		State.GLIDE:
			pose = POSE_SIDE
			face = "worried"
		State.CHEER:
			pose = POSE_FRONT
			face = "happy"

	_want_pose = pose
	if pose != _pose or face != _face:
		# Swap at the pinch, so the change is hidden inside the paper turn.
		if _pinch < 0.45 or _pose == POSE_FRONT or pose == _pose:
			_apply_art(pose, face)
		elif _pose != pose:
			_pinch = minf(_pinch, 0.35)


func _update_pose(delta: float) -> void:
	var target_scale := Vector3.ONE
	var target_rot := Vector3.ZERO
	var rate := 14.0

	match state:
		State.IDLE:
			var bob := sin(_time * 3.4) * 0.03
			target_scale = Vector3(1.0 - bob, 1.0 + bob, 1.0)
		State.DASH:
			var u := clampf(_dash_t / Tuning.DASH_TIME, 0.0, 1.4)
			var smear := maxf(0.0, 1.0 - u)
			target_scale = Vector3(1.0 + 0.30 * smear, 1.0 - 0.22 * smear, 1.0)
			target_rot = Vector3(0, 0, -_dash_dir.x * 16.0 * smear)
			rate = 26.0
		State.ARMED:
			var tr := sin(_time * 24.0) * 0.02
			target_scale = Vector3(1.0 + tr, 1.0 - tr * 1.5, 1.0)
			target_rot = Vector3(0, 0, sin(_time * 19.0) * 3.0)
		State.LAUNCH:
			match grade:
				LaunchController.Grade.PERFECT:
					target_scale = Vector3(0.72, 1.55, 1.0)
				LaunchController.Grade.GOOD:
					target_scale = Vector3(0.84, 1.34, 1.0)
					target_rot = Vector3(0, 0, 12)
				_:
					target_scale = Vector3(1.10, 1.06, 1.0)
					target_rot = Vector3(0, 0, 34)
		State.APEX:
			target_scale = Vector3(1.12, 0.92, 1.0)
			target_rot = Vector3(0, 0, 0.0 if grade == LaunchController.Grade.PERFECT
					else sin(_time * 3.0) * 26.0)
			rate = 8.0
		State.FALL:
			target_scale = Vector3(0.86, 1.22, 1.0)
			target_rot = Vector3(0, 0, 0.0 if grade == LaunchController.Grade.PERFECT
					else -22.0)
		State.LAND:
			var lu := clampf(_land_t / 0.24, 0.0, 1.0)
			var punch := (1.0 - lu) * (1.0 - lu)
			if grade == LaunchController.Grade.BAD:
				target_scale = Vector3(1.0 + punch * 0.55, 1.0 - punch * 0.48, 1.0)
				target_rot = Vector3(0, 0, 46.0 * punch)
			else:
				target_scale = Vector3(1.0 + punch * 0.38, 1.0 - punch * 0.36, 1.0)
			rate = 20.0
		State.GLIDE:
			target_scale = Vector3(1.10, 0.92, 1.0)
			target_rot = Vector3(0, 0, sin(_time * 4.6) * 20.0)
			rate = 7.0
		State.CHEER:
			var hop := absf(sin(_time * 4.4))
			target_scale = Vector3(1.0 - hop * 0.10, 1.0 + hop * 0.18, 1.0)

	# The paper turn: pinch flat, swap, spring back.
	var pinch_target := 1.0 if _facing == _want_facing else 0.0
	_pinch = move_toward(_pinch, pinch_target, delta * 9.0)
	if _pinch <= 0.02 and _facing != _want_facing:
		_facing = _want_facing
		_apply_art(_want_pose, _face)
	if _facing == _want_facing:
		_pinch = move_toward(_pinch, 1.0, delta * 9.0)

	var k := clampf(rate * delta, 0.0, 1.0)
	_root.scale = _root.scale.lerp(
			Vector3(target_scale.x * maxf(0.02, _pinch) * _facing, target_scale.y, 1.0), k)
	_root.rotation_degrees = _root.rotation_degrees.lerp(target_rot, k)

	# The contact shadow stays on the deck and shrinks as the character rises.
	var lift: float = maxf(0.0, global_position.y - origin_y())
	_shadow.visible = lift < 6.0
	var f := clampf(1.0 - lift / 6.0, 0.0, 1.0)
	_shadow.global_position = Vector3(global_position.x, origin_y() + 0.03, global_position.z)
	_shadow.scale = Vector3(0.5 + 0.5 * f, 1.0, 0.4 + 0.4 * f)


func origin_y() -> float:
	var p := get_parent()
	if p is PlayerMotor:
		return (p as PlayerMotor).origin.y
	return 0.0


## GDD 14.2 [LOCK]: the head is a separate part and it only ever follows.
func _update_head(delta: float) -> void:
	var lag := Vector2(clampf(-_velocity.x * 1.6, -22, 22), clampf(_velocity.y * 0.8, -16, 16))
	if state == State.APEX:
		lag *= 0.4
	_head_lag = _head_lag.lerp(lag, clampf(9.0 * delta, 0, 1))
	var wob := sin(_time * 5.2) * 1.6
	_head.rotation_degrees = Vector3(0, 0, _head_lag.x + wob)
	_head.position.y = lerpf(_head.position.y, _head.position.y, 1.0)


func _update_scarf(delta: float) -> void:
	if _scarf.is_empty():
		return
	# Behind the paper, never in front of it. The character is a flat cut-out and
	# a ribbon drifting toward the camera simply erases the body.
	var anchor := global_position + Vector3(0, FIGURE_HEIGHT * 0.52, -0.06)
	if not _scarf_ready:
		for i in SCARF_SEGMENTS:
			_scarf_p[i] = anchor
			_scarf_prev[i] = anchor
		_scarf_ready = true

	var dt := clampf(delta, 1.0 / 240.0, 1.0 / 30.0)
	var open := 1.0 if state == State.GLIDE else 0.0
	var drag := 0.90 - 0.16 * open
	var gravity := Vector3(0, -9.0 + 7.0 * open, 0)
	# Mostly sideways, so the ribbon reads as a silhouette beside the character
	# rather than as a bar pointing at the viewer.
	var breeze := Vector3(2.6 * sin(_time * 1.9) + 1.2, 0.7, -1.2 - 0.6 * open)
	var push := -_velocity * (0.9 + 0.8 * open) + breeze

	for i in SCARF_SEGMENTS:
		var cur := _scarf_p[i]
		var vel := (cur - _scarf_prev[i]) * drag
		_scarf_prev[i] = cur
		_scarf_p[i] = cur + vel + (gravity + push) * dt * dt * 30.0

	var grounded := state in [State.IDLE, State.DASH, State.ARMED, State.LAND, State.CHEER]
	var floor_y := origin_y() + 0.10
	for _pass in 2:
		_scarf_p[0] = anchor
		for i in range(1, SCARF_SEGMENTS):
			var a := _scarf_p[i - 1]
			var d := _scarf_p[i] - a
			var l := d.length()
			if l > 1e-5:
				_scarf_p[i] = a + d / l * SCARF_LEN
			if grounded and _scarf_p[i].y < floor_y:
				_scarf_p[i].y = floor_y
			# Hard rule: stay behind the paper.
			_scarf_p[i].z = minf(_scarf_p[i].z, global_position.z - 0.05)

	for i in range(1, SCARF_SEGMENTS):
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
