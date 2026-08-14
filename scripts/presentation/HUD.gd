class_name HUD
extends CanvasLayer

## GDD 22.1 / 30 / 33 - the deliberately quiet UI.
##
## There is no note highway, no HIT LINE, no combo counter, no accuracy percent
## and no answer hint. The only persistent element is an optional four-pip count
## in the corner, and it can be switched off entirely. Everything else appears
## once, at the end of the stage.

signal restart_requested
signal pause_toggled(paused: bool)

const PIP_OFF := Color(1, 1, 1, 0.16)
const PIP_ON := Color(1, 0.93, 0.72, 0.78)
const PIP_GO := Color(1, 0.72, 0.34, 0.95)

var _pips: Array[ColorRect] = []
var _pip_root: Control
var _joystick: Control
var _joy_parts: Array[Control] = []
var _debug: Label
var _results: Control
var _pause: Control
var _vignette: ColorRect

var show_debug := false
var _rebinding := ""
var _rebind_button: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pips()
	_build_joystick()
	_build_debug()
	_build_results()
	_build_pause()


func _style_label(l: Label, size: int, color: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)


# ---------------------------------------------------------------------------
# the four-pip count (GDD 33: "숫자 HUD 최소")
# ---------------------------------------------------------------------------

func _build_pips() -> void:
	_pip_root = Control.new()
	_pip_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pip_root.position = Vector2(-70, -46)
	add_child(_pip_root)
	for i in 4:
		var r := ColorRect.new()
		r.size = Vector2(15, 15)
		r.position = Vector2(i * 26, 0)
		r.color = PIP_OFF
		r.pivot_offset = r.size * 0.5
		_pip_root.add_child(r)
		_pips.append(r)


## `phase` 0..3 within the current four-beat phase; -1 hides the count.
func set_count(phase: int, is_go: bool) -> void:
	_pip_root.visible = GameSettings.show_beat_pips and phase >= 0
	for i in _pips.size():
		var r := _pips[i]
		if phase < 0:
			r.color = PIP_OFF
			continue
		if i < phase:
			r.color = PIP_ON
		elif i == phase:
			r.color = PIP_GO if is_go else PIP_ON
			r.scale = Vector2(1.5, 1.5)
		else:
			r.color = PIP_OFF


func _process(delta: float) -> void:
	for r in _pips:
		r.scale = r.scale.lerp(Vector2.ONE, clampf(9.0 * delta, 0, 1))


# ---------------------------------------------------------------------------
# GDD 12.3 [TEST]: the direction glyph that breaks at the first blast
# ---------------------------------------------------------------------------

func _build_joystick() -> void:
	_joystick = Control.new()
	_joystick.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_joystick.position = Vector2(0, -120)
	add_child(_joystick)
	var dirs := [Vector2(-42, 0), Vector2(0, -42), Vector2(42, 0), Vector2(0, 42)]
	var glyphs := ["◀", "▲", "▶", "▼"]
	for i in 4:
		var l := Label.new()
		l.text = glyphs[i]
		_style_label(l, 30, Color(1, 1, 1, 0.5))
		l.position = dirs[i] - Vector2(12, 18)
		_joystick.add_child(l)
		_joy_parts.append(l)


## The back arrow does not "turn off". It is knocked out of the frame, because
## the real reason is that the deck behind is gone (GDD 12.3).
func break_joystick() -> void:
	if _joy_parts.size() < 4:
		return
	var back := _joy_parts[3]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(back, "position", back.position + Vector2(60, 160), 0.9)
	tw.tween_property(back, "rotation", 3.4, 0.9)
	tw.tween_property(back, "modulate:a", 0.0, 0.9)
	for i in 3:
		var p := _joy_parts[i]
		var t2 := create_tween()
		t2.tween_property(p, "modulate:a", 0.0, 0.7).set_delay(0.9 + i * 0.1)
	var t3 := create_tween()
	t3.tween_property(_joystick, "modulate:a", 0.0, 0.4).set_delay(2.0)


func hide_joystick() -> void:
	_joystick.visible = false


# ---------------------------------------------------------------------------
# debug overlay (F3) - never part of the shipped reading surface
# ---------------------------------------------------------------------------

func _build_debug() -> void:
	_debug = Label.new()
	_debug.position = Vector2(14, 10)
	_style_label(_debug, 14, Color(0.85, 1.0, 0.85))
	_debug.visible = false
	add_child(_debug)


func set_debug_text(t: String) -> void:
	_debug.visible = show_debug
	if show_debug:
		_debug.text = t


# ---------------------------------------------------------------------------
# GDD 22.2 - the one and only results screen
# ---------------------------------------------------------------------------

func _build_results() -> void:
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.visible = false
	add_child(_results)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.05, 0.04, 0.04, 0.86)
	_results.add_child(_vignette)

	var plate := ColorRect.new()
	plate.set_anchors_preset(Control.PRESET_CENTER)
	plate.position = Vector2(-260, -190)
	plate.size = Vector2(520, 400)
	plate.color = Color(0.10, 0.08, 0.07, 0.88)
	_results.add_child(plate)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-230, -170)
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 6)
	_results.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = "DESERT BRIDGE ESCAPED"
	_style_label(title, 40, Color(1, 0.90, 0.66))
	box.add_child(title)

	var body := Label.new()
	body.name = "Body"
	_style_label(body, 22, Color(0.95, 0.93, 0.88))
	box.add_child(body)

	var rank := Label.new()
	rank.name = "Rank"
	_style_label(rank, 54, Color(1, 0.83, 0.42))
	box.add_child(rank)

	var again := Button.new()
	again.text = "RUN IT AGAIN   (R)"
	again.custom_minimum_size = Vector2(240, 44)
	again.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(again)


func show_results(stats: Dictionary) -> void:
	var body := _results.find_child("Body", true, false) as Label
	var rank := _results.find_child("Rank", true, false) as Label
	var title := _results.find_child("Title", true, false) as Label
	title.text = str(stats.get("title", "DESERT BRIDGE ESCAPED"))
	body.text = "\n".join([
		"Mine Launches      %2d / %d" % [stats.get("launches", 0), stats.get("sectors", 0)],
		"Scarf Glides       %2d" % stats.get("glides", 0),
		"Perfect Launches   %2d" % stats.get("perfect", 0),
		"Longest Streak     %2d" % stats.get("streak", 0),
		"Best Route         %s" % stats.get("route", "MAIN"),
	])
	rank.text = "Rank   %s" % stats.get("rank", "A")
	_results.visible = true
	_results.modulate.a = 0.0
	create_tween().tween_property(_results, "modulate:a", 1.0, 1.2)


func hide_results() -> void:
	_results.visible = false


# ---------------------------------------------------------------------------
# GDD 23 - accessibility / options
# ---------------------------------------------------------------------------

func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	add_child(_pause)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.05, 0.06, 0.78)
	_pause.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-210, -210)
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	_pause.add_child(box)

	var t := Label.new()
	t.text = "OPTIONS"
	_style_label(t, 32, Color(1, 0.90, 0.66))
	box.add_child(t)

	box.add_child(_slider_row("Camera shake", GameSettings.shake_scale,
			func(v: float) -> void:
				GameSettings.shake_scale = v
				GameSettings.save()))
	box.add_child(_slider_row("Music", GameSettings.music_volume,
			func(v: float) -> void:
				GameSettings.music_volume = v
				GameSettings.save()))
	box.add_child(_slider_row("Sound", GameSettings.sfx_volume,
			func(v: float) -> void:
				GameSettings.sfx_volume = v
				GameSettings.save()))

	box.add_child(_check_row("Adjacency hint when stuck", GameSettings.adjacency_hint_enabled,
			func(v: bool) -> void:
				GameSettings.adjacency_hint_enabled = v
				GameSettings.save()))
	box.add_child(_check_row("Show count pips", GameSettings.show_beat_pips,
			func(v: bool) -> void:
				GameSettings.show_beat_pips = v
				GameSettings.save()))

	var kt := Label.new()
	kt.text = "Keys  -  click, then press a key"
	_style_label(kt, 18, Color(0.85, 0.85, 0.85))
	box.add_child(kt)
	for action in ["dash_left", "dash_forward", "dash_right"]:
		box.add_child(_key_row(action))

	var reset := Button.new()
	reset.text = "Reset keys"
	reset.pressed.connect(func() -> void:
		GameSettings.reset_binds()
		_refresh_key_labels())
	box.add_child(reset)

	var restart := Button.new()
	restart.text = "Restart stage  (R)"
	restart.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(restart)


func _slider_row(label: String, value: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(220, 0)
	_style_label(l, 18, Color(0.95, 0.95, 0.95))
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(180, 24)
	s.value_changed.connect(func(v: float) -> void: on_change.call(v))
	row.add_child(s)
	return row


func _check_row(label: String, value: bool, on_change: Callable) -> Control:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = value
	c.toggled.connect(func(v: bool) -> void: on_change.call(v))
	return c


func _key_row(action: String) -> Control:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = action.replace("dash_", "").to_upper()
	l.custom_minimum_size = Vector2(220, 0)
	_style_label(l, 18, Color(0.95, 0.95, 0.95))
	row.add_child(l)
	var b := Button.new()
	b.name = "key_" + action
	b.custom_minimum_size = Vector2(180, 30)
	b.text = _key_text(action)
	b.pressed.connect(func() -> void:
		_rebinding = action
		_rebind_button = b
		b.text = "press a key...")
	row.add_child(b)
	return row


func _key_text(action: String) -> String:
	var keys: Array = GameSettings.binds.get(action, [])
	var names := PackedStringArray()
	for k in keys:
		names.append(OS.get_keycode_string(int(k)))
	return " / ".join(names)


func _refresh_key_labels() -> void:
	for action in ["dash_left", "dash_forward", "dash_right"]:
		var b := _pause.find_child("key_" + action, true, false) as Button
		if b:
			b.text = _key_text(action)


func _input(event: InputEvent) -> void:
	if _rebinding != "" and event is InputEventKey and event.is_pressed():
		var key := (event as InputEventKey).physical_keycode
		GameSettings.rebind(_rebinding, key, 0)
		_rebinding = ""
		_rebind_button = null
		_refresh_key_labels()
		get_viewport().set_input_as_handled()


## These live on the HUD rather than on GameDirector because the HUD keeps
## processing while the tree is paused - otherwise Escape could pause the game
## but never unpause it.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		pause_toggled.emit(toggle_pause())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		restart_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_toggle"):
		show_debug = not show_debug
		set_debug_text("")
		get_viewport().set_input_as_handled()


func toggle_pause() -> bool:
	_pause.visible = not _pause.visible
	if _pause.visible:
		_refresh_key_labels()
	return _pause.visible


func is_paused() -> bool:
	return _pause.visible
