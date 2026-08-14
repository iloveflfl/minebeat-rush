class_name LaunchController
extends RefCounted

## GDD 11 + 25.1: the whole flight is one pure function of the song beat.
## Nothing here reads the scene tree, nothing integrates per-frame velocity, so
## a dropped frame can never make the character drift away from the music - the
## next frame simply samples the correct point again (GDD 26 [LOCK]).
##
## GDD 11.2 [LOCK]: the grade is recorded for pose / sound / VFX only. It is
## deliberately absent from sample(), and a test asserts that.

enum Grade { PERFECT, GOOD, BAD }
enum Mode { IDLE, LAUNCH, GLIDE }

var mode: Mode = Mode.IDLE
var grade: Grade = Grade.PERFECT

var go_beat: float = 0.0
var end_beat: float = 0.0
var apex_beat: float = 0.0

var from_pos: Vector3 = Vector3.ZERO
var to_pos: Vector3 = Vector3.ZERO
var apex_height: float = 0.0

var _tempo: TempoMap
var _t0: float = 0.0
var _t_apex: float = 0.0
var _t1: float = 0.0


func setup(tempo: TempoMap) -> void:
	_tempo = tempo


func _arm(start_beat: float, from_world: Vector3, to_world: Vector3) -> void:
	go_beat = start_beat
	apex_beat = start_beat + float(Tuning.APEX_BEAT_OFFSET)
	end_beat = start_beat + float(Tuning.AIR_BEATS)
	from_pos = from_world
	to_pos = to_world
	_t0 = _tempo.time_at_beat(go_beat)
	_t_apex = _tempo.time_at_beat(apex_beat)
	_t1 = _tempo.time_at_beat(end_beat)


## GDD 10.1 / 11.1: the escape mine fires and throws the player across the
## broken span. Airtime is always AIR_BEATS, the apex always lands on air beat 2.
func begin_launch(start_beat: float, from_world: Vector3, to_world: Vector3, g: Grade) -> void:
	mode = Mode.LAUNCH
	grade = g
	_arm(start_beat, from_world, to_world)
	# GDD 6.3: h = g*(T/2)^2 / 2 for a symmetric ballistic arc of total time T.
	var half := _t1 - _t0
	apex_height = 0.5 * Tuning.LAUNCH_GRAVITY * pow(half * 0.5, 2.0)


## GDD 10.2 [LOCK]: missing the mine is not death. The sector falls, the red
## scarf opens, and the blast updraft carries the player to the same next deck
## on the same downbeat - lower, wobblier, and funnier.
func begin_glide(start_beat: float, from_world: Vector3, to_world: Vector3) -> void:
	mode = Mode.GLIDE
	grade = Grade.BAD
	_arm(start_beat, from_world, to_world)
	apex_height = 0.0


## Normalised flight progress, 0 at the launch GO, 1 at the landing GO.
func progress(beat: float) -> float:
	if end_beat <= go_beat:
		return 1.0
	return clampf((beat - go_beat) / (end_beat - go_beat), 0.0, 1.0)


## The one function that defines where the character is in the air.
func sample(beat: float) -> Vector3:
	if mode == Mode.IDLE:
		return from_pos

	var t := _tempo.time_at_beat(beat)
	var s := clampf((t - _t0) / maxf(1e-6, _t1 - _t0), 0.0, 1.0)

	var flat := from_pos.lerp(to_pos, s)
	var y := flat.y

	if mode == Mode.LAUNCH:
		# Two half-parabolas that meet with zero vertical speed at the apex.
		# Splitting them this way keeps the apex pinned to air beat 2 even when
		# the BPM steps up in the middle of the flight.
		if t <= _t_apex:
			var u := (_t_apex - t) / maxf(1e-6, _t_apex - _t0)
			y += apex_height * (1.0 - u * u)
		else:
			var u2 := (t - _t_apex) / maxf(1e-6, _t1 - _t_apex)
			y += apex_height * (1.0 - u2 * u2)
		return Vector3(flat.x, y, flat.z)

	# --- scarf glide -------------------------------------------------------
	var dip := 0.0
	if s <= 0.35:
		var f := s / 0.35
		dip = -Tuning.GLIDE_DROP * f * f          # the deck drops out from under you
	else:
		var r := (s - 0.35) / 0.65
		dip = -Tuning.GLIDE_DROP * pow(1.0 - r, 1.6)   # the scarf catches the updraft
	var wobble := Tuning.GLIDE_WOBBLE * sin(s * PI * 3.0) * sin(PI * s)
	return Vector3(flat.x + wobble, y + dip, flat.z)


## GDD 11.2: how the arrival on the escape mine lined up with the GO downbeat.
## Cosmetic only.
static func grade_for(seconds_early: float, exempt: bool) -> Grade:
	if exempt:
		return Grade.PERFECT
	var e := absf(seconds_early)
	if e <= Tuning.PERFECT_WINDOW:
		return Grade.PERFECT
	if e <= Tuning.GOOD_WINDOW:
		return Grade.GOOD
	return Grade.BAD


static func grade_name(g: Grade) -> String:
	match g:
		Grade.PERFECT: return "PERFECT"
		Grade.GOOD: return "GOOD"
		_: return "BAD"
