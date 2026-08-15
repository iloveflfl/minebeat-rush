class_name BeatRing
extends Node3D

## Why the launch was graded PERFECT, GOOD or BAD, shown instead of explained.
##
## The rule (GDD 11.2) is "the step that puts you on the charge should land on
## the GO downbeat". That is a fine rule and completely invisible, which is the
## complaint this exists to answer.
##
## So the deck under the fox carries the oldest, most readable rhythm-game
## device there is: a wide ring that closes onto a fixed inner ring, arriving
## exactly on the beat. Dash while it is tight and the timing is good. Nobody
## has to be told that - it is the same shape as every "hit it now" indicator
## ever drawn, and it teaches the rule on *every* dash rather than only on the
## one that happens to land on a charge.
##
## It is still not a note highway (GDD 30): it does not scroll, it does not gate
## input, it sits on the world at the player's feet, and it can be switched off.

const OUTER_START := 2.6
const INNER := 0.95

var _outer: MeshInstance3D
var _inner: MeshInstance3D
var _outer_mat: StandardMaterial3D
var _inner_mat: StandardMaterial3D
var _flash := 0.0
var _active := false


func _ready() -> void:
	_inner_mat = _ring_material(Color(1.0, 0.97, 0.86, 0.55))
	_outer_mat = _ring_material(Color(1.0, 0.86, 0.45, 0.5))
	_inner = _make_ring(0.86, 1.0, _inner_mat)
	_outer = _make_ring(0.90, 1.0, _outer_mat)
	add_child(_inner)
	add_child(_outer)
	set_active(false)


func _ring_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


func _make_ring(inner_r: float, outer_r: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner_r
	t.outer_radius = outer_r
	t.rings = 40
	t.ring_segments = 5
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.05, 0)
	return mi


func set_active(on: bool) -> void:
	_active = on and GameSettings.show_beat_ring
	visible = _active


## Call on every beat crossing so the ring can pop.
func pulse() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	if not _active:
		return
	_flash = maxf(0.0, _flash - delta * 4.5)

	var beat: float = BeatConductor.beat
	var frac: float = beat - floor(beat)
	# Closes onto the inner ring, arriving exactly on the beat.
	var s := lerpf(OUTER_START, INNER, pow(frac, 0.85))
	_outer.scale = Vector3(s, 1.0, s)
	_inner.scale = Vector3(INNER, 1.0, INNER)

	# Brightest right as it lands, so the eye is pulled to the moment itself.
	var tight := pow(frac, 3.0)
	_outer_mat.albedo_color.a = 0.16 + 0.5 * tight
	_inner_mat.albedo_color.a = 0.18 + 0.45 * _flash
	var warm := Color(1.0, 0.86, 0.45).lerp(Color(1.0, 1.0, 0.95), tight)
	_outer_mat.albedo_color = Color(warm.r, warm.g, warm.b, _outer_mat.albedo_color.a)
