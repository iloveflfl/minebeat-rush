extends Node

## GDD 17 + 25: music, structural sound, explosions, character foley, mix state.
##
## The music is four stems recorded as one continuous take against the stage
## tempo map, all started on the same frame. Arrangement is done by fading stems
## per Act, so the bar downbeats always sit exactly on the GO beats no matter
## how the player plays (GDD 26 [LOCK] - audio is the master clock).

const STEMS := ["drums", "bass", "lead", "atmos", "drive"]
const SFX_POOL := 20

## Per-Act stem mix. GDD 18: the arrangement grows, the rules do not.
## "drive" is the 16th-note layer; it is what stops the middle of the stage from
## sagging once the novelty of the first blast has worn off.
const ACT_MIX := {
	"Intro":    {"drums": 0.00, "bass": 0.35, "lead": 0.00, "atmos": 1.00, "drive": 0.00},
	"Accident": {"drums": 0.75, "bass": 0.85, "lead": 0.00, "atmos": 1.00, "drive": 0.25},
	"Learn":    {"drums": 0.80, "bass": 0.90, "lead": 0.40, "atmos": 0.80, "drive": 0.30},
	"Master":   {"drums": 1.00, "bass": 1.00, "lead": 0.75, "atmos": 0.60, "drive": 0.70},
	"Escalate": {"drums": 1.00, "bass": 1.00, "lead": 0.95, "atmos": 0.45, "drive": 0.95},
	"Remix":    {"drums": 1.00, "bass": 1.00, "lead": 1.00, "atmos": 0.40, "drive": 1.00},
	"Finale":   {"drums": 1.00, "bass": 1.00, "lead": 1.00, "atmos": 0.75, "drive": 1.00},
	"Outro":    {"drums": 0.00, "bass": 0.30, "lead": 0.25, "atmos": 1.00, "drive": 0.00},
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
		p.stream = _load_stream("res://assets/audio/music_%s" % s)
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


## Music ships as Vorbis (small enough for a phone to stream), one-shots stay as
## WAV (instant decode, which matters for a sound that has to land on a beat).
## Either extension is accepted so a local build with raw WAV stems still runs.
func _load_stream(base: String) -> AudioStream:
	if _cache.has(base):
		return _cache[base]
	var st: AudioStream = null
	for ext in [".ogg", ".wav"]:
		var path: String = base + str(ext)
		if ResourceLoader.exists(path):
			st = load(path)
			if st != null:
				break
	if st == null:
		push_warning("AudioDirector: missing %s(.ogg|.wav)" % base)
	_cache[base] = st
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
	var stream := _load_stream("res://assets/audio/%s" % name)
	if stream == null:
		return
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	p.stream = stream
	p.pitch_scale = clampf(pitch + randf_range(-pitch_jitter, pitch_jitter), 0.05, 4.0)
	var g := volume * GameSettings.sfx_volume
	p.volume_db = -80.0 if g <= 0.001 else linear_to_db(g)
	p.play()

