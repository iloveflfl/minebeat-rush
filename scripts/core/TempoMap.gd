class_name TempoMap
extends RefCounted

## Piecewise-constant tempo map. Converts between absolute song beats and
## absolute song seconds. GDD 26: everything (damage stages, apex, landing) is
## expressed in beats and resolved through this map, so nothing drifts against
## the music when the BPM curve steps up.

var _segs: Array[Dictionary] = []
var _seg_time: PackedFloat64Array = PackedFloat64Array()


func _init(segments: Array = []) -> void:
	if segments.is_empty():
		segments = [{"beat": 0.0, "bpm": 100.0}]
	set_segments(segments)


static func from_json_file(path: String) -> TempoMap:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "TempoMap: cannot open %s" % path)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert(parsed is Dictionary, "TempoMap: %s is not a JSON object" % path)
	return TempoMap.new((parsed as Dictionary).get("segments", []))


func set_segments(segments: Array) -> void:
	_segs.clear()
	for s in segments:
		_segs.append({"beat": float(s["beat"]), "bpm": float(s["bpm"])})
	_segs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["beat"] < b["beat"])
	if _segs.is_empty() or _segs[0]["beat"] > 0.0:
		_segs.insert(0, {"beat": 0.0, "bpm": 100.0})

	_seg_time.resize(_segs.size())
	_seg_time[0] = 0.0
	for i in range(1, _segs.size()):
		var db: float = _segs[i]["beat"] - _segs[i - 1]["beat"]
		_seg_time[i] = _seg_time[i - 1] + db * (60.0 / float(_segs[i - 1]["bpm"]))


func _index_for_beat(beat: float) -> int:
	var idx := 0
	for i in _segs.size():
		if _segs[i]["beat"] <= beat:
			idx = i
		else:
			break
	return idx


func _index_for_time(t: float) -> int:
	var idx := 0
	for i in _seg_time.size():
		if _seg_time[i] <= t:
			idx = i
		else:
			break
	return idx


func bpm_at_beat(beat: float) -> float:
	return float(_segs[_index_for_beat(beat)]["bpm"])


## Length of one beat, in seconds, at the given song beat.
func beat_duration_at(beat: float) -> float:
	return 60.0 / bpm_at_beat(beat)


func time_at_beat(beat: float) -> float:
	var i := _index_for_beat(beat)
	return _seg_time[i] + (beat - float(_segs[i]["beat"])) * (60.0 / float(_segs[i]["bpm"]))


func beat_at_time(t: float) -> float:
	var i := _index_for_time(t)
	return float(_segs[i]["beat"]) + (t - _seg_time[i]) * (float(_segs[i]["bpm"]) / 60.0)
