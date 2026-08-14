extends Node

## GDD 17 + 25: music, structural sound, explosions, character foley, mix state.
##
## The music is four stems recorded as one continuous take against the stage
## tempo map, all started on the same frame. Arrangement is done by fading stems
## per Act, so the bar downbeats always sit exactly on the GO beats no matter
## how the player plays (GDD 26 [LOCK] - audio is the master clock).

const STEMS := ["drums", "bass", "lead", "atmos"]
const SFX_POOL := 16

## Per-Act stem mix. GDD 18: the arrangement grows, the rules do not.
const ACT_MIX := {
	"Intro":    {"drums": 0.00, "bass": 0.35, "lead": 0.00, "atmos": 1.00},
	"Accident": {"drums": 0.70, "bass": 0.85, "lead": 0.00, "atmos": 1.00},
	"Learn":    {"drums": 0.75, "bass": 0.90, "lead": 0.35, "atmos": 0.85},
	"Master":   {"drums": 0.95, "bass": 1.00, "lead": 0.70, "atmos": 0.70},
	"Escalate": {"drums": 1.00, "bass": 1.00, "lead": 0.95, "atmos": 0.60},
	"Remix":    {"drums": 1.00, "bass": 1.00, "lead": 1.00, "atmos": 0.55},
	"Finale":   {"drums": 1.00, "bass": 1.00, "lead": 1.00, "atmos": 0.90},
	"Outro":    {"drums": 0.00, "bass": 0.30, "lead": 0.20, "atmos": 1.00},
}

var _players: Dictionary = {}          ## stem name -> AudioStreamPlayer
var _target_gain: Dictionary = {}
var _current_gain: Dictionary = {}
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _cache: Dictionary = {}
var _clock_player: AudioStreamPlayer = null

var started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in STEMS:
		var p := AudioStreamPlayer.new()
		p.stream = _load_stream("res://assets/audio/music_%s.wav" % s)
		p.bus = "Master"
		p.volume_db = -80.0
		add_child(p)
		_players[s] = p
		_target_gain[s] = 0.0
		_current_gain[s] = 0.0
	_clock_player = _players["atmos"]

	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx.append(p)

	set_act("Intro", true)


func _load_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path)
	if st == null:
		push_warning("AudioDirector: missing %s" % path)
	_cache[path] = st
	return st


## Starts every stem on the same frame. This is the moment song time exists.
## `from_seconds` is only ever non-zero for the development jump-to-sector flag.
func start_music(from_seconds: float = 0.0) -> void:
	if started:
		return
	started = true
	for s in STEMS:
		(_players[s] as AudioStreamPlayer).play(from_seconds)


## Pausing has to stop the stems too, or the master clock would keep running
## while the game is frozen and everything would resume out of phase.
func set_paused(p: bool) -> void:
	for s in STEMS:
		(_players[s] as AudioStreamPlayer).stream_paused = p


func stop_music() -> void:
	started = false
	for s in STEMS:
		(_players[s] as AudioStreamPlayer).stop()


## Raw playback position of the clock stem, in seconds. BeatConductor corrects
## this for mix latency; nothing else should call it.
func clock_playback_position() -> float:
	if _clock_player == null or not _clock_player.playing:
		return -1.0
	return _clock_player.get_playback_position()


func music_length() -> float:
	if _clock_player == null or _clock_player.stream == null:
		return 0.0
	return _clock_player.stream.get_length()


func set_act(act: String, instant: bool = false) -> void:
	var mix: Dictionary = ACT_MIX.get(act, ACT_MIX["Learn"])
	for s in STEMS:
		_target_gain[s] = float(mix.get(s, 0.0))
		if instant:
			_current_gain[s] = _target_gain[s]
			_apply(s)


func _process(delta: float) -> void:
	for s in STEMS:
		var cur: float = _current_gain[s]
		var tgt: float = _target_gain[s]
		if absf(cur - tgt) > 0.001:
			_current_gain[s] = move_toward(cur, tgt, delta * 0.9)
			_apply(s)


func _apply(s: String) -> void:
	var p: AudioStreamPlayer = _players[s]
	var g: float = float(_current_gain[s]) * GameSettings.music_volume
	p.volume_db = -80.0 if g <= 0.001 else linear_to_db(g)


## GDD 16 / 17: one-shot world sound. `pitch_jitter` keeps repeated dashes and
## footfalls from turning into a machine gun.
func play(name: String, volume: float = 1.0, pitch: float = 1.0, pitch_jitter: float = 0.0) -> void:
	var stream := _load_stream("res://assets/audio/%s.wav" % name)
	if stream == null:
		return
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	p.stream = stream
	p.pitch_scale = clampf(pitch + randf_range(-pitch_jitter, pitch_jitter), 0.05, 4.0)
	var g := volume * GameSettings.sfx_volume
	p.volume_db = -80.0 if g <= 0.001 else linear_to_db(g)
	p.play()
