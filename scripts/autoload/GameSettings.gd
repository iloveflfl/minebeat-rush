extends Node

## GDD 23: accessibility and UX options, plus the input map. Actions are
## registered in code rather than baked into project.godot so that remapping is
## a first-class feature instead of an afterthought.

## Settings live next to the project rather than in the OS user directory, so a
## portable install on an external drive keeps everything on that drive. Falls
## back to user:// if the project folder is not writable.
var _save_path := ""


func _resolve_save_path() -> String:
	if _save_path != "":
		return _save_path
	var dir := ProjectSettings.globalize_path("res://user_data")
	if DirAccess.make_dir_recursive_absolute(dir) == OK:
		_save_path = dir.path_join("settings.cfg")
	else:
		_save_path = "user://settings.cfg"
	return _save_path

## GDD 7.1 [LOCK]: three ground actions. "dash_back" exists only for the Act 0
## free-roam intro and is refused by PlayerMotor for the rest of the game.
const DEFAULT_BINDS := {
	"dash_left": [KEY_LEFT, KEY_A],
	"dash_forward": [KEY_UP, KEY_W],
	"dash_right": [KEY_RIGHT, KEY_D],
	"dash_back": [KEY_DOWN, KEY_S],
	"ui_pause": [KEY_ESCAPE],
	"debug_toggle": [KEY_F3],
	"restart": [KEY_R],
}

## GDD 23: camera shake 0-100%.
var shake_scale: float = 1.0
## GDD 23: optional adjacency hint. Highlights which cells a clue *counts*,
## never which cell is the answer (GDD 30 forbids that).
var adjacency_hint_enabled: bool = true
## GDD 33: the count HUD stays minimal; this can turn it off entirely.
var show_beat_pips: bool = true
var music_volume: float = 0.9
var sfx_volume: float = 1.0

var binds: Dictionary = {}

signal settings_changed


func _ready() -> void:
	binds = _default_binds_copy()
	_load()
	apply_input_map()


func _default_binds_copy() -> Dictionary:
	var d := {}
	for a in DEFAULT_BINDS:
		d[a] = (DEFAULT_BINDS[a] as Array).duplicate()
	return d


func apply_input_map() -> void:
	for action in binds:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.5)
		for key in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(key)
			InputMap.action_add_event(action, ev)


func rebind(action: String, keycode: int, slot: int = 0) -> void:
	if not binds.has(action):
		return
	var arr: Array = binds[action]
	while arr.size() <= slot:
		arr.append(keycode)
	arr[slot] = keycode
	apply_input_map()
	save()
	settings_changed.emit()


func reset_binds() -> void:
	binds = _default_binds_copy()
	apply_input_map()
	save()
	settings_changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("accessibility", "shake_scale", shake_scale)
	cfg.set_value("accessibility", "adjacency_hint", adjacency_hint_enabled)
	cfg.set_value("accessibility", "beat_pips", show_beat_pips)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("input", "binds", binds)
	cfg.save(_resolve_save_path())


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_resolve_save_path()) != OK:
		return
	shake_scale = cfg.get_value("accessibility", "shake_scale", shake_scale)
	adjacency_hint_enabled = cfg.get_value("accessibility", "adjacency_hint", adjacency_hint_enabled)
	show_beat_pips = cfg.get_value("accessibility", "beat_pips", show_beat_pips)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	var b: Variant = cfg.get_value("input", "binds", null)
	if b is Dictionary:
		for a in DEFAULT_BINDS:
			if (b as Dictionary).has(a):
				binds[a] = (b as Dictionary)[a]
