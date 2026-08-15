class_name CameraDirector
extends Node3D

## GDD 13 - the camera breathes between reading and spectacle.
##
## [LOCK] enforced structurally, not by discipline:
##   * yaw and roll are never written. `rotation` is only ever assigned as
##     Vector3(pitch, 0, 0), so screen-left can never stop being world -X
##     (GDD 7.1, 13, 30).
##   * during a reading phase, shake is driven to zero and dust is suppressed
##     (GDD 13, 23) - a nice explosion must never cover a number (GDD 15.3).

enum View { OPENING, FREE, GROUND, LAUNCH, AIR_RISE, APEX, FALL, LANDING, GLIDE, GATE }

## height above the deck, distance behind the subject, how far ahead it aims, fov
## GROUND and LANDING are recomputed from `frame_depth` so a 3-row sector and a
## 7-row sector are both framed with the whole clue row and the whole candidate
## row comfortably on screen (GDD 27.1: no important number may be cut or hidden).
const VIEWS := {
	# GDD 12.1 step 3: the destination has to be on screen before anything else
	# happens. The stage opens looking straight down the canyon at the Sun Gate,
	# then settles into the quasi-top-down roaming view.
	View.OPENING:   {"h": 6.5,  "back": 17.0, "ahead": 70.0, "fov": 54.0, "snap": 1.1,
					 "aim_y": 4.0},
	View.FREE:      {"h": 17.0, "back": 9.0,  "ahead": 4.0,  "fov": 50.0, "snap": 3.2},
	# GDD 13: the reading view is deliberately long-lens. A narrow FOV keeps the
	# grid big and the perspective distortion low, which is what makes a row of
	# numbers readable at a glance.
	View.GROUND:    {"h": 16.0, "back": 8.0,  "ahead": 7.0,  "fov": 42.0, "snap": 5.0},
	View.LAUNCH:    {"h": 2.4,  "back": 5.0,  "ahead": 1.0,  "fov": 70.0, "snap": 16.0},
	View.AIR_RISE:  {"h": 2.6,  "back": 6.0,  "ahead": 2.0,  "fov": 62.0, "snap": 14.0},
	View.APEX:      {"h": 2.2,  "back": 5.4,  "ahead": 2.0,  "fov": 50.0, "snap": 11.0},
	View.FALL:      {"h": 5.0,  "back": 8.5,  "ahead": 8.0,  "fov": 60.0, "snap": 10.0},
	View.LANDING:   {"h": 16.0, "back": 8.0,  "ahead": 7.0,  "fov": 42.0, "snap": 6.5},
	# GDD 10.2: a scarf glide sags well below the deck, and the sector it just
	# left is falling through the same space. The glide view sits high enough to
	# stay clear of the debris and looks down at the character, so failing is a
	# readable move of its own rather than a screenful of rubble.
	View.GLIDE:     {"h": 15.0, "back": 12.0, "ahead": 8.0,  "fov": 66.0, "snap": 3.0,
					 "aim_y": -3.0},
	# Looks *up* at the gate, so the thing you have been running toward finally
	# fills the frame (GDD 21.1 third "wow" moment).
	View.GATE:      {"h": 11.0, "back": 44.0, "ahead": 22.0, "fov": 62.0, "snap": 1.6,
					 "aim_y": 24.0},
}

## Depth of the deck the reading views have to frame, in metres.
var frame_depth := 11.0

## GDD 13: reading views hold still. Everything else may move.
const READING_VIEWS := [View.OPENING, View.FREE, View.GROUND, View.LANDING]

var view: View = View.FREE
var target: Node3D

var camera: Camera3D
var _pos := Vector3(0, 14, 12)
var _pitch := -50.0
var _fov := 60.0
var _shake := 0.0
var _shake_decay := 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	camera = Camera3D.new()
	camera.current = true
	# A tight depth range: the ink hull sits centimetres off each surface, and at
	# near 0.15 / far 3000 the depth buffer cannot tell them apart.
	camera.far = 2200.0
	camera.near = 0.6
	add_child(camera)
	_rng.randomize()


func set_view(v: View) -> void:
	view = v


func is_reading() -> bool:
	return READING_VIEWS.has(view)


## GDD 13 / 16: explosions get a very short impulse only. Anything longer would
## bleed into the next reading phase.
func impulse(amount: float, decay: float = 7.0) -> void:
	if is_reading():
		amount *= 0.15
	_shake = maxf(_shake, amount)
	_shake_decay = decay


func _params(v: View) -> Dictionary:
	var cfg: Dictionary = (VIEWS[v] as Dictionary).duplicate()
	if v == View.GROUND or v == View.LANDING:
		cfg["h"] = 10.5 + frame_depth * 0.26
		cfg["back"] = 7.0 + frame_depth * 0.18
		cfg["ahead"] = frame_depth * 0.52
	return cfg


func _process(delta: float) -> void:
	if target == null:
		return
	var cfg := _params(view)
	var t: Vector3 = target.global_position

	var want := Vector3(t.x, t.y + float(cfg["h"]), t.z + float(cfg["back"]))
	var snap: float = float(cfg["snap"])
	var k := clampf(snap * delta, 0.0, 1.0)
	# Lateral follow is deliberately lazier than vertical/depth follow so a
	# sideways dash is legible as movement instead of sliding the whole world.
	_pos.x = lerpf(_pos.x, want.x, clampf(snap * 0.45 * delta, 0.0, 1.0))
	_pos.y = lerpf(_pos.y, want.y, k)
	_pos.z = lerpf(_pos.z, want.z, k)

	var aim_z: float = t.z - float(cfg["ahead"])
	var aim_y: float = t.y + float(cfg.get("aim_y", 0.0))
	var flat: float = maxf(0.5, _pos.z - aim_z)
	var want_pitch := rad_to_deg(atan2(-(_pos.y - aim_y), flat))
	_pitch = lerpf(_pitch, want_pitch, clampf(snap * 0.8 * delta, 0.0, 1.0))
	_fov = lerpf(_fov, float(cfg["fov"]), clampf(3.5 * delta, 0.0, 1.0))

	if is_reading():
		_shake = move_toward(_shake, 0.0, delta * 12.0)
	_shake = move_toward(_shake, 0.0, delta * _shake_decay)

	var offset := Vector3.ZERO
	if _shake > 0.001:
		var s := _shake * GameSettings.shake_scale
		offset = Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s),
				_rng.randf_range(-s, s) * 0.4)

	camera.global_position = _pos + offset
	# [LOCK] pitch only. No yaw, no roll, ever.
	camera.rotation_degrees = Vector3(_pitch, 0.0, 0.0)
	camera.fov = _fov


func warp_to_target() -> void:
	if target == null:
		return
	var cfg := _params(view)
	var t := target.global_position
	_pos = Vector3(t.x, t.y + float(cfg["h"]), t.z + float(cfg["back"]))
	_fov = float(cfg["fov"])
	_pitch = rad_to_deg(atan2(-(float(cfg["h"]) - float(cfg.get("aim_y", 0.0))),
			float(cfg["back"]) + float(cfg["ahead"])))


