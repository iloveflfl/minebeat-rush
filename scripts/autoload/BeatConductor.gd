extends Node

## GDD 26 [LOCK] - the audio playback position IS the clock.
##
## Nothing in this game counts 3-2-1-GO with a repeating Timer. Every frame the
## conductor asks the music where it is, corrects for the mix buffer and the
## output latency, and converts that to an absolute song beat through the stage
## tempo map. If a frame is dropped, the next frame simply reads a later
## position - visuals resync themselves instead of drifting.

signal beat_crossed(beat_index: int)
signal started

const TEMPO_PATH := "res://assets/data/stage1_tempo.json"

var tempo: TempoMap
var song_time: float = 0.0
var beat: float = 0.0
var running := false

## When there is no audio device (headless runs, or a machine with sound off)
## the conductor falls back to wall time so the game is still playable and
## testable. Everything downstream is unaware of the difference.
var _fallback := false
var _fallback_time := 0.0
var _last_beat_index := -1
var _latency := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	tempo = TempoMap.from_json_file(TEMPO_PATH)
	set_process(false)


## `from_beat` is a development convenience (jump straight to a sector); the
## game itself always starts at 0.
func start(from_beat: float = 0.0) -> void:
	if running:
		return
	_latency = AudioServer.get_output_latency()
	song_time = tempo.time_at_beat(from_beat)
	AudioDirector.start_music(song_time)
	_fallback_time = song_time
	_last_beat_index = int(floor(from_beat))
	beat = from_beat
	running = true
	set_process(true)
	started.emit()


func stop() -> void:
	running = false
	set_process(false)
	AudioDirector.stop_music()


func _process(delta: float) -> void:
	if not running:
		return

	var pos := AudioDirector.clock_playback_position()
	if pos < 0.0:
		_fallback = true
		_fallback_time += delta
		song_time = maxf(song_time, _fallback_time)
	else:
		_fallback = false
		var corrected := pos + AudioServer.get_time_since_last_mix() - _latency
		# get_time_since_last_mix() jitters by a mix buffer; never let the clock
		# walk backwards or a beat could fire twice.
		song_time = maxf(song_time, corrected)

	beat = tempo.beat_at_time(song_time)

	var idx := int(floor(beat))
	while _last_beat_index < idx:
		_last_beat_index += 1
		beat_crossed.emit(_last_beat_index)


# --- convenience -------------------------------------------------------------

func time_at_beat(b: float) -> float:
	return tempo.time_at_beat(b)


func beat_at_time(t: float) -> float:
	return tempo.beat_at_time(t)


func beat_duration() -> float:
	return tempo.beat_duration_at(beat)


func bpm() -> float:
	return tempo.bpm_at_beat(beat)


## Seconds from now until the given song beat. Negative once it has passed.
func seconds_until(b: float) -> float:
	return tempo.time_at_beat(b) - song_time


func using_fallback_clock() -> bool:
	return _fallback
