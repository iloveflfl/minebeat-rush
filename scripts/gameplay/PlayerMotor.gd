class_name PlayerMotor
extends Node3D

## GDD 7 [LOCK] - free tile dash.
##
## Deliberate invariants, each of which is a [LOCK] in the design document:
##   * This file does not reference BeatConductor at all. The rhythm can never
##     gate, quantise or refuse a dash (GDD 6, 7.1, 30).
##   * Directions are screen-relative and the camera never yaws or rolls, so
##     LEFT is always world -X and RIGHT is always world +X (GDD 7.1, 13).
##   * A dash ends exactly on the destination cell centre. Momentum is a purely
##     visual thing owned by CharacterAnimator (GDD 7.2 "물리는 정확,
##     애니메이션은 과장").

signal dash_started(dir: Vector2i, to_cell: Vector2i)
signal dash_arrived(cell: Vector2i)
signal dash_rejected(dir: Vector2i)

var grid: MineGrid
var cell: Vector2i = Vector2i.ZERO
var origin: Vector3 = Vector3.ZERO
var deck_width: int = 3
var sand_cells: Dictionary = {}

## Only the Act 0 free-roam intro allows stepping backwards. After the first
## blast the deck behind the player literally is not there any more (GDD 7.1).
var allow_back := false
var input_enabled := true
## False while LaunchController owns the character's position, so the ground
## motor can never fight the ballistic curve for the same transform.
var owns_position := true

var _dashing := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _elapsed := 0.0
var _duration := Tuning.DASH_TIME
var _dir := Vector2i.ZERO
var _buffered := Vector2i.ZERO
var _buffer_age := 0.0

## Wall-clock time (seconds since process start) of the last arrival, used by
## GameDirector to grade how close the arrival was to the GO downbeat.
var last_arrival_time := -1.0


## How high the walkable surface of a cell is above the deck plane. An unopened
## slab is a raised button, so standing on one has to actually put the character
## on top of it - without this the feet sink through the tile they are on.
func surface_height(c: Vector2i) -> float:
	if grid != null and grid.state_at(c) == MineGrid.Cell.COVERED:
		return Tuning.COVERED_RISE
	return 0.0


## Position of a cell relative to `origin`. Kept separate from origin so the
## deck can settle underneath the player (GDD 6.1) without invalidating a dash
## that is already in flight.
func local_cell_pos(c: Vector2i) -> Vector3:
	return Vector3(
		(float(c.x) - float(deck_width - 1) * 0.5) * Tuning.TILE,
		surface_height(c),
		-float(c.y) * Tuning.TILE)


func cell_to_world(c: Vector2i) -> Vector3:
	return origin + local_cell_pos(c)


func place_on(g: MineGrid, deck_origin: Vector3, at: Vector2i, sand: Dictionary = {}) -> void:
	grid = g
	origin = deck_origin
	deck_width = g.width
	cell = at
	sand_cells = sand
	_dashing = false
	_buffered = Vector2i.ZERO
	owns_position = true
	position = cell_to_world(at)


## Where the character actually is right now, mid-dash included.
func world_position() -> Vector3:
	return position


func is_dashing() -> bool:
	return _dashing


func dash_dir() -> Vector2i:
	return _dir


## 0 at the start of the current dash, 1 on arrival. Drives the smear pose.
func dash_progress() -> float:
	if not _dashing:
		return 1.0
	return clampf(_elapsed / maxf(1e-5, _duration), 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not event.is_pressed() or event.is_echo():
		return
	var d := Vector2i.ZERO
	if event.is_action_pressed("dash_left"):
		d = MineGrid.MOVE_LEFT
	elif event.is_action_pressed("dash_right"):
		d = MineGrid.MOVE_RIGHT
	elif event.is_action_pressed("dash_forward"):
		d = MineGrid.MOVE_FORWARD
	elif allow_back and event.is_action_pressed("dash_back"):
		d = MineGrid.MOVE_BACK
	if d == Vector2i.ZERO:
		return

	inject(d)


## Same path a key press takes. Used by the development auto-play driver so it
## exercises exactly the code a human hits, not a shortcut around it.
func inject(d: Vector2i) -> void:
	if _dashing:
		# One buffered input. GDD 7.2 step 5: animation must never eat an input.
		_buffered = d
		_buffer_age = 0.0
	else:
		_try_dash(d)


func _try_dash(d: Vector2i) -> bool:
	if grid == null:
		return false
	var target := cell + d
	# GDD 30: a blocked dash is simply refused. It is never a death, never a
	# stagger the player has to wait out.
	if not grid.is_walkable(target):
		dash_rejected.emit(d)
		return false

	_dir = d
	_from = local_cell_pos(cell)
	_to = local_cell_pos(target)
	_elapsed = 0.0
	_duration = Tuning.DASH_TIME_SAND if sand_cells.has(target) else Tuning.DASH_TIME
	_dashing = true
	cell = target
	dash_started.emit(d, target)
	return true


func _process(delta: float) -> void:
	if _buffered != Vector2i.ZERO:
		_buffer_age += delta
		if _buffer_age > Tuning.INPUT_BUFFER:
			_buffered = Vector2i.ZERO

	if not owns_position:
		return

	if _dashing:
		_elapsed += delta
		var u := clampf(_elapsed / _duration, 0.0, 1.0)
		# Hard out of the start, settle into the destination.
		var e := 1.0 - pow(1.0 - u, 2.6)
		# A small hop over the gap between two tile tops, so stepping up onto a
		# raised slab reads as a step rather than as a slide.
		var hop := sin(u * PI) * 0.10
		position = origin + _from.lerp(_to, e) + Vector3(0, hop, 0)
		if u >= 1.0:
			_finish_dash()
	else:
		# origin.y is driven by GameDirector from the live sector body, so the
		# player settles with the deck as it takes damage (GDD 6.1).
		position = origin + local_cell_pos(cell)


func _finish_dash() -> void:
	_dashing = false
	# [LOCK] exact cell centre. No drift, ever.
	position = cell_to_world(cell)
	last_arrival_time = Time.get_ticks_msec() / 1000.0
	dash_arrived.emit(cell)

	if _buffered != Vector2i.ZERO:
		var d := _buffered
		_buffered = Vector2i.ZERO
		_try_dash(d)


## Used when the launch or glide takes over: the motor stops driving position.
func release() -> void:
	_dashing = false
	_buffered = Vector2i.ZERO
	input_enabled = false
	owns_position = false
