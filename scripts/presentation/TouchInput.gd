class_name TouchInput
extends CanvasLayer

## GDD 23 / 33: the same three-direction control, mapped to a phone.
##
## Two ways in, because a casual player will try one or the other without being
## told:
##   * tap  - the screen is three tall zones, left / forward / right
##   * flick - a swipe in any of those three directions does the same thing
##
## Both synthesise the ordinary dash actions and push them through
## Input.parse_input_event(), so touch travels the exact same path as a key
## press. PlayerMotor still decides what is legal, which means the GDD 7.1
## [LOCK] rules (no diagonals, no back outside Act 0) hold for free.
##
## GDD 30 forbids an on-screen note highway or answer hints; these zones are
## unlit by default and only flash the moment they are touched, so they read as
## feedback rather than as UI.

const SWIPE_MIN := 34.0        ## px before a drag counts as a flick
const FLASH_TIME := 0.22

var enabled := false

var _zones: Array[ColorRect] = []
var _flash := [0.0, 0.0, 0.0]
var _drag_start: Dictionary = {}   ## touch index -> start position
var _consumed: Dictionary = {}


func _ready() -> void:
	layer = 5                       ## under the HUD, over the world
	process_mode = Node.PROCESS_MODE_PAUSABLE
	enabled = Quality.is_mobile() or DisplayServer.is_touchscreen_available()
	visible = enabled
	_build_zones()


func _build_zones() -> void:
	var tints := [
		Color(1.0, 0.95, 0.80, 0.0),
		Color(1.0, 0.95, 0.80, 0.0),
		Color(1.0, 0.95, 0.80, 0.0),
	]
	for i in 3:
		var r := ColorRect.new()
		r.color = tints[i]
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.anchor_left = float(i) / 3.0
		r.anchor_right = float(i + 1) / 3.0
		# The forward zone stops short of the bottom edge so a thumb resting
		# there does not fire a dash.
		r.anchor_top = 0.30
		add_child(r)
		_zones.append(r)


func _dir_for_zone(zone: int) -> String:
	match zone:
		0: return "dash_left"
		2: return "dash_right"
		_: return "dash_forward"


func _zone_at(x: float) -> int:
	var w := float(get_viewport().get_visible_rect().size.x)
	return clampi(int(x / maxf(1.0, w) * 3.0), 0, 2)


func _fire(action: String, zone: int) -> void:
	if not enabled:
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	if zone >= 0:
		_flash[zone] = FLASH_TIME


func _input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_drag_start[t.index] = t.position
			_consumed[t.index] = false
		else:
			# A touch that was never dragged far enough is a tap on a zone.
			if not bool(_consumed.get(t.index, false)):
				var zone := _zone_at(t.position.x)
				if t.position.y > get_viewport().get_visible_rect().size.y * 0.30:
					_fire(_dir_for_zone(zone), zone)
			_drag_start.erase(t.index)
			_consumed.erase(t.index)

	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if bool(_consumed.get(d.index, false)) or not _drag_start.has(d.index):
			return
		var delta: Vector2 = d.position - (_drag_start[d.index] as Vector2)
		if delta.length() < SWIPE_MIN:
			return
		_consumed[d.index] = true
		if absf(delta.x) > absf(delta.y):
			if delta.x < 0.0:
				_fire("dash_left", 0)
			else:
				_fire("dash_right", 2)
		elif delta.y < 0.0:
			_fire("dash_forward", 1)
		else:
			# A downward flick is only meaningful during the Act 0 free roam;
			# PlayerMotor refuses it everywhere else (GDD 7.1 [LOCK]).
			_fire("dash_back", -1)


func _process(delta: float) -> void:
	if not enabled:
		return
	for i in 3:
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta)
		_zones[i].color.a = (_flash[i] / FLASH_TIME) * 0.16
