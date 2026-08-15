class_name BackdropDirector
extends Node3D

## The world behind the bridge.
##
## Built from the Kirby background research (docs/ARTDIRECTION.md). The four
## rules that mattered:
##
##  1. Ruins must not read as horror. HAL's stated fix for exactly this problem
##     was "a bright blue sky and colourful plant life, like grass and flowers".
##     So the canyon has a river in it, the piers have palms and flowering vines
##     growing out of them, and banners still hang off the stonework. The bridge
##     is "a beautiful place that has merged with nature", not a ruin.
##  2. Depth is built from separated layers, each one paler and bluer than the
##     one in front of it, not from one detailed mesh.
##  3. Every layer moves. Clouds drift, balloons rise, birds cross, sand ribbons
##     blow through. A still background is what made the old one feel dead.
##  4. The background is the least saturated thing on screen, so the deck and
##     the fox stay the most readable (GDD 15.3).
##
## Colour also travels across the stage - dawn through noon to a hot gold
## finale - which is how the player feels progress without a progress bar.

const SKY_TOP := [
	Color(0.36, 0.58, 0.92),   # Learn      - clean morning blue
	Color(0.30, 0.62, 0.95),
	Color(0.34, 0.55, 0.93),
	Color(0.46, 0.46, 0.86),   # Remix      - the sky starts to heat up
	Color(0.62, 0.40, 0.72),   # Finale     - low gold sun
]
const SKY_HORIZON := [
	Color(0.98, 0.92, 0.78),
	Color(1.00, 0.94, 0.76),
	Color(1.00, 0.87, 0.65),
	Color(1.00, 0.79, 0.55),
	Color(1.00, 0.68, 0.44),
]
const SUN_COLOR := [
	Color(1.00, 0.97, 0.88),
	Color(1.00, 0.96, 0.86),
	Color(1.00, 0.92, 0.78),
	Color(1.00, 0.86, 0.68),
	Color(1.00, 0.78, 0.58),
]

const ACT_STAGE := {
	"Intro": 0, "Accident": 0, "Learn": 0, "Master": 1,
	"Escalate": 2, "Remix": 3, "Finale": 4, "Outro": 4,
}

var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial

var _clouds: Array[Node3D] = []
var _floaters: Array[Dictionary] = []
var _birds: Array[Dictionary] = []
var _ribbons: Array[Dictionary] = []
var _stage := 0
var _blend := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _span := 1200.0


func setup(span_length: float, lights: Array) -> void:
	_span = maxf(200.0, span_length)
	_rng.seed = 8801
	sun = lights[0]
	fill = lights[1]
	_build_clouds()
	_build_floaters()
	_build_birds()
	_build_sand_ribbons()
	apply_stage(0, true)


# ---------------------------------------------------------------------------
# palette travel
# ---------------------------------------------------------------------------

func set_act(act: String) -> void:
	_stage = int(ACT_STAGE.get(act, 0))


func apply_stage(idx: int, instant: bool = false) -> void:
	_stage = idx
	if instant:
		_blend = float(idx)
		_push_palette(float(idx))


func _push_palette(f: float) -> void:
	var i := clampi(int(floor(f)), 0, SKY_TOP.size() - 1)
	var j := clampi(i + 1, 0, SKY_TOP.size() - 1)
	var t := clampf(f - float(i), 0.0, 1.0)

	var top: Color = SKY_TOP[i].lerp(SKY_TOP[j], t)
	var hor: Color = SKY_HORIZON[i].lerp(SKY_HORIZON[j], t)
	var sc: Color = SUN_COLOR[i].lerp(SUN_COLOR[j], t)

	if sky_mat:
		sky_mat.sky_top_color = top
		sky_mat.sky_horizon_color = hor
		# Below the horizon stays the pale far-rock violet: that half of the dome
		# is what the reading camera actually looks at, and it has to read as
		# depth haze rather than as sky.
		var haze: Color = Greybox.C_ROCK_FAR.lerp(hor, 0.45)
		sky_mat.ground_horizon_color = haze.lightened(0.3)
		sky_mat.ground_bottom_color = haze.lightened(0.1)
	if env:
		env.fog_light_color = hor.lerp(Greybox.C_ROCK_FAR, 0.45)
		env.ambient_light_color = hor.lerp(Color(0.6, 0.7, 1.0), 0.45)
	if sun:
		sun.light_color = sc
		sun.rotation_degrees = Vector3(lerpf(-52.0, -26.0, f / 4.0), lerpf(28.0, 8.0, f / 4.0), 0)
	if fill:
		fill.light_color = top.lerp(Color(1, 1, 1), 0.35)


# ---------------------------------------------------------------------------
# layers
# ---------------------------------------------------------------------------

## Layer 1 - big soft cloud banks. Chunky rounded blobs, never wispy: a cartoon
## cloud has to read as a shape at any distance.
func _build_clouds() -> void:
	var white := Greybox.mat(Greybox.C_CLOUD, 1.0, 0.0, 0.10, 0.0)
	var shade := Greybox.mat(Color(0.86, 0.90, 0.99), 1.0, 0.0, 0.04, 0.0)
	for i in int(34 * Quality.prop_density()):
		var cloud := Node3D.new()
		var far := _rng.randf_range(160.0, 460.0)
		cloud.position = Vector3(
			_rng.randf_range(-500.0, 500.0),
			_rng.randf_range(28.0, 150.0),
			-_rng.randf_range(20.0, _span))
		var puffs := _rng.randi_range(4, 7)
		var scale := _rng.randf_range(6.0, 17.0)
		for p in puffs:
			var r := scale * _rng.randf_range(0.55, 1.0)
			cloud.add_child(Greybox.mi(Greybox.sphere(r, 10),
					shade if p % 3 == 2 else white,
					Vector3(_rng.randf_range(-scale, scale) * 1.5,
							_rng.randf_range(-scale, scale) * 0.28,
							_rng.randf_range(-scale, scale) * 0.5)))
		cloud.set_meta("drift", _rng.randf_range(0.6, 2.4))
		cloud.set_meta("depth", far)
		add_child(cloud)
		_clouds.append(cloud)


## Layer 2 - things that hang in the air between the canyon walls. Lanterns and
## balloons left by the people who built the bridge: proof the place was loved.
func _build_floaters() -> void:
	var silk := [Greybox.C_FLOWER_A, Greybox.C_BANNER, Greybox.C_FLOWER_B,
			Color(0.55, 0.85, 0.55), Color(0.98, 0.55, 0.35)]
	for i in int(46 * Quality.prop_density()):
		var n := Node3D.new()
		var col: Color = silk[i % silk.size()]
		var r := _rng.randf_range(1.1, 2.6)
		n.add_child(Greybox.mi(Greybox.sphere(r, 10), Greybox.mat(col, 1.0, 0.0, 0.25, 1.4)))
		n.add_child(Greybox.mi(Greybox.cone(r * 0.5, r * 0.7, 8),
				Greybox.mat(col.darkened(0.25)), Vector3(0, -r * 0.85, 0)))
		n.add_child(Greybox.mi(Greybox.box(Vector3(0.07, r * 2.4, 0.07)),
				Greybox.mat(Color(0.85, 0.80, 0.66)), Vector3(0, -r * 2.2, 0)))
		n.position = Vector3(
			_rng.randf_range(-70.0, 70.0),
			_rng.randf_range(-42.0, 16.0),
			-_rng.randf_range(10.0, _span))
		add_child(n)
		_floaters.append({
			"node": n,
			"base": n.position,
			"bob": _rng.randf_range(0.5, 1.3),
			"phase": _rng.randf_range(0.0, TAU),
			"amp": _rng.randf_range(0.8, 2.4),
		})


## Layer 3 - birds crossing the canyon. Two triangles and a sine wave; the whole
## point is that something alive moves through the frame every few seconds.
func _build_birds() -> void:
	var body := Greybox.mat(Color(0.28, 0.26, 0.36))
	for i in int(22 * Quality.prop_density()):
		var flock := Node3D.new()
		for b in _rng.randi_range(3, 6):
			var bird := Node3D.new()
			bird.position = Vector3(_rng.randf_range(-5, 5), _rng.randf_range(-2, 2),
					_rng.randf_range(-5, 5))
			for s in [-1.0, 1.0]:
				var wing := Greybox.mi(Greybox.box(Vector3(1.5, 0.12, 0.5)), body,
						Vector3(s * 0.8, 0, 0))
				wing.rotation_degrees = Vector3(0, 0, s * -20.0)
				bird.add_child(wing)
			flock.add_child(bird)
		flock.position = Vector3(_rng.randf_range(-90, 90), _rng.randf_range(-22, 34),
				-_rng.randf_range(20.0, _span))
		add_child(flock)
		_birds.append({
			"node": flock,
			"base": flock.position,
			"speed": _rng.randf_range(5.0, 11.0) * (1.0 if i % 2 == 0 else -1.0),
			"phase": _rng.randf_range(0.0, TAU),
		})


## Layer 4 - sand catching the light as it blows down the canyon. Long thin
## quads that only exist to put motion between the player and the far wall.
func _build_sand_ribbons() -> void:
	var haze := Greybox.mat(Color(1.0, 0.93, 0.74, 0.5), 1.0, 0.0, 0.5, 0.0)
	for i in int(26 * Quality.prop_density()):
		var r := Greybox.mi(Greybox.box(Vector3(_rng.randf_range(14.0, 40.0), 0.5, 1.2)), haze)
		r.position = Vector3(_rng.randf_range(-80, 80), _rng.randf_range(-55, 14),
				-_rng.randf_range(10.0, _span))
		r.rotation_degrees = Vector3(0, _rng.randf_range(-20, 20), _rng.randf_range(-9, 9))
		add_child(r)
		_ribbons.append({
			"node": r,
			"base": r.position,
			"speed": _rng.randf_range(9.0, 22.0),
			"phase": _rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_time += delta
	_blend = move_toward(_blend, float(_stage), delta * 0.22)
	_push_palette(_blend)

	for c in _clouds:
		c.position.x += float(c.get_meta("drift")) * delta

	for f in _floaters:
		var n: Node3D = f["node"]
		var base: Vector3 = f["base"]
		n.position.y = base.y + sin(_time * float(f["bob"]) + float(f["phase"])) * float(f["amp"])
		n.position.x = base.x + sin(_time * 0.31 + float(f["phase"])) * 1.6

	for b in _birds:
		var n2: Node3D = b["node"]
		var base2: Vector3 = b["base"]
		var s: float = float(b["speed"])
		n2.position.x = wrapf(base2.x + _time * s, -140.0, 140.0)
		n2.position.y = base2.y + sin(_time * 0.8 + float(b["phase"])) * 2.4
		n2.rotation_degrees.y = 0.0 if s > 0.0 else 180.0
		for bird in n2.get_children():
			var flap := sin(_time * 8.0 + float(b["phase"])) * 26.0
			var kids := bird.get_children()
			if kids.size() >= 2:
				(kids[0] as Node3D).rotation_degrees.z = -20.0 - flap
				(kids[1] as Node3D).rotation_degrees.z = 20.0 + flap

	for r in _ribbons:
		var n3: Node3D = r["node"]
		var base3: Vector3 = r["base"]
		n3.position.x = wrapf(base3.x + _time * float(r["speed"]), -110.0, 110.0)
		n3.position.y = base3.y + sin(_time * 0.6 + float(r["phase"])) * 1.4



