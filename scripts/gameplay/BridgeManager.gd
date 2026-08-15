class_name BridgeManager
extends Node3D

## GDD 25: streams one enormous bridge sector by sector.
##
## GDD 5.1 [LOCK]: from the first frame to the last this has to read as a single
## physical stone bridge that spans a canyon, with the destination already
## visible in the distance. The "sectors" are a logic and streaming convenience;
## nothing on screen may look like a chain of floating islands (GDD 30).

const LIVE_BEHIND := 1
const LIVE_AHEAD := 3

var stage: Stage1Data.BuiltStage
var intro_data: SectorData
var intro_grid: MineGrid
var intro_sector: BridgeSector

var _sectors: Dictionary = {}   ## index -> BridgeSector
var _world: Node3D
var _gate: Node3D


func setup(built: Stage1Data.BuiltStage) -> void:
	stage = built
	_world = Node3D.new()
	_world.name = "Structure"
	add_child(_world)
	_build_canyon()
	_build_continuous_structure()
	_build_sun_gate()


# ---------------------------------------------------------------------------
# the Act 0 approach deck (GDD 12.1) - the same bridge, before anything breaks
# ---------------------------------------------------------------------------

func build_intro_deck() -> BridgeSector:
	intro_grid = Stage1Data.build_intro_grid()
	intro_data = SectorData.new()
	intro_data.id = "A0"
	intro_data.act = "Intro"
	# The intro deck is built as a grid rather than as an ASCII board: it has no
	# puzzle to prove, so it never goes through the sector validator.
	intro_data.width = Stage1Data.INTRO_WIDTH
	intro_data.length = Stage1Data.INTRO_LENGTH
	intro_data.world_z = 0.0
	intro_data.mine_cells = [Stage1Data.INTRO_MINE]

	intro_sector = BridgeSector.new()
	intro_sector.name = "IntroDeck"
	intro_sector.build(intro_data, intro_grid, -1)
	add_child(intro_sector)
	return intro_sector


# ---------------------------------------------------------------------------
# streaming
# ---------------------------------------------------------------------------

func ensure_range(center_index: int) -> void:
	for i in range(center_index - LIVE_BEHIND, center_index + LIVE_AHEAD + 1):
		if i < 0 or i >= stage.sectors.size() or sector(i) != null:
			continue
		var s := BridgeSector.new()
		s.name = "Sector_%02d_%s" % [i, stage.sectors[i].id]
		s.build(stage.sectors[i], stage.grids[i], i)
		add_child(s)
		_sectors[i] = s


## A collapsed sector frees itself once its debris has fallen out of sight, so
## the lookup has to assume any entry may already be gone.
func sector(index: int) -> BridgeSector:
	var s: Variant = _sectors.get(index, null)
	if s == null or not is_instance_valid(s):
		_sectors.erase(index)
		return null
	return s as BridgeSector


func data_at(index: int) -> SectorData:
	return stage.sectors[index]


func grid_at(index: int) -> MineGrid:
	return stage.grids[index]


func drop_sector(index: int) -> void:
	if _sectors.has(index):
		_sectors.erase(index)


# ---------------------------------------------------------------------------
# the permanent structure: canyon, piers, ruined spans, destination
# ---------------------------------------------------------------------------

## GDD 5.1 + the Kirby research: a gorge with a river and things growing in it,
## laid out in three depth bands that get paler and bluer as they recede. HAL's
## fix for ruins reading as horror was literally "a bright blue sky and colourful
## plant life" - so this canyon is alive, not abandoned.
func _build_canyon() -> void:
	var far_z := stage.gate_z - 200.0
	var span := absf(far_z) + 460.0
	# Thin ink on the mid band, none at all on the far band and the canyon floor.
	# GDD 15.3: the background must never carry as much line weight as the deck.
	var near_rock := Greybox.mat(Greybox.C_ROCK_NEAR, 1.0, 0.0, 0.0, 1.6)
	var mid_rock := Greybox.mat(Greybox.C_ROCK_MID, 1.0, 0.0, 0.0, 1.2)
	var far_rock := Greybox.mat(Greybox.C_ROCK_FAR, 1.0, 0.0, 0.0, 0.0)
	var floor_mat := Greybox.mat(Color(0.86, 0.78, 0.58), 1.0, 0.0, 0.0, 0.0)
	var water := Greybox.mat(Greybox.C_WATER, 1.0, 0.0, 0.22, 0.0)
	var leaf := Greybox.mat(Greybox.C_LEAF, 1.0, 0.0, 0.0, 1.6)
	var leaf_dark := Greybox.mat(Greybox.C_LEAF_DARK, 1.0, 0.0, 0.0, 1.6)

	# Canyon floor with a river running the whole length of it.
	_world.add_child(Greybox.mi(Greybox.box(Vector3(560.0, 8.0, span)),
			floor_mat, Vector3(0, -134.0, far_z * 0.5)))
	_world.add_child(Greybox.mi(Greybox.box(Vector3(46.0, 1.2, span)),
			water, Vector3(0, -129.4, far_z * 0.5)))

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for side in [-1.0, 1.0]:
		# Far band - almost sky-coloured. This is the aerial-perspective layer.
		_world.add_child(Greybox.mi(Greybox.box(Vector3(160.0, 260.0, span)),
				far_rock, Vector3(side * 260.0, -10.0, far_z * 0.5)))
		var z := 40.0
		while z > far_z:
			# Mid band - stacked mesas with green tops.
			var w := rng.randf_range(24.0, 62.0)
			var h := rng.randf_range(60.0, 190.0)
			var x: float = side * rng.randf_range(112.0, 190.0)
			var mesa := Greybox.mi(Greybox.box(Vector3(w, h, rng.randf_range(28.0, 78.0))),
					mid_rock if rng.randf() > 0.45 else far_rock,
					Vector3(x, -74.0 + h * 0.5, z))
			mesa.rotation_degrees = Vector3(0, rng.randf_range(-16, 16), 0)
			_world.add_child(mesa)
			if rng.randf() > 0.35:
				_world.add_child(Greybox.mi(Greybox.box(Vector3(w * 0.95, 3.0, w * 0.6)),
						leaf if rng.randf() > 0.5 else leaf_dark,
						Vector3(x, -74.0 + h + 1.0, z)))

			# Near band - warm rock shelves close to the bridge, with palms.
			if rng.randf() > 0.45:
				var sh := rng.randf_range(10.0, 28.0)
				var sx: float = side * rng.randf_range(52.0, 84.0)
				var sy := rng.randf_range(-70.0, -18.0)
				_world.add_child(Greybox.mi(
						Greybox.box(Vector3(rng.randf_range(16.0, 34.0), sh,
								rng.randf_range(14.0, 30.0))),
						near_rock, Vector3(sx, sy, z + rng.randf_range(-14, 14))))
				for p in rng.randi_range(1, 3):
					_add_palm(Vector3(sx + rng.randf_range(-8, 8), sy + sh * 0.5,
							z + rng.randf_range(-10, 10)), rng)
			z -= rng.randf_range(42.0, 84.0)

	_build_distant_arches(far_z, rng)


## Big readable silhouettes crossing the canyon in the middle distance: the
## older aqueducts this bridge replaced. Kirby backgrounds are built out of a
## few large simple shapes rather than a lot of small detail, and these are what
## stop the space between the deck and the far wall from being empty air.
func _build_distant_arches(far_z: float, rng: RandomNumberGenerator) -> void:
	var stone := Greybox.mat(Greybox.C_ROCK_MID.lerp(Greybox.C_PIER, 0.4), 1.0, 0.0, 0.0, 1.2)
	var pale := Greybox.mat(Greybox.C_ROCK_FAR.lerp(Greybox.C_ROCK_MID, 0.3), 1.0, 0.0, 0.0, 0.0)
	var z := -260.0
	var idx := 0
	while z > far_z + 120.0:
		var deep := idx % 2 == 1
		var m := pale if deep else stone
		var y := rng.randf_range(-82.0, -38.0)
		var tilt := rng.randf_range(-7.0, 7.0)
		var arch := Node3D.new()
		arch.position = Vector3(rng.randf_range(-30.0, 30.0), y, z)
		arch.rotation_degrees = Vector3(0, rng.randf_range(-26.0, 26.0), tilt)
		# Deck across the gorge...
		arch.add_child(Greybox.mi(Greybox.box(Vector3(320.0, 7.0, 12.0)), m, Vector3.ZERO))
		# ...on a row of legs, with a few arches already fallen through.
		for k in 9:
			if rng.randf() < 0.22:
				continue
			var lx := -140.0 + float(k) * 35.0
			var lh := rng.randf_range(40.0, 90.0)
			arch.add_child(Greybox.mi(Greybox.box(Vector3(9.0, lh, 10.0)), m,
					Vector3(lx, -lh * 0.5 - 3.0, 0)))
			arch.add_child(Greybox.mi(Greybox.box(Vector3(26.0, 5.0, 11.0)), m,
					Vector3(lx + 17.0, -6.0, 0)))
		if rng.randf() > 0.5:
			arch.add_child(Greybox.mi(Greybox.box(Vector3(46.0, 4.0, 13.0)), m,
					Vector3(rng.randf_range(-90, 90), 5.5, 0)))
		_world.add_child(arch)
		z -= rng.randf_range(190.0, 320.0)
		idx += 1


## A cartoon palm: one leaning trunk and a spray of fat rounded fronds. Small,
## cheap, and the single strongest signal that this place is not dead.
func _add_palm(at: Vector3, rng: RandomNumberGenerator) -> void:
	var palm := Node3D.new()
	palm.position = at
	palm.rotation_degrees = Vector3(rng.randf_range(-8, 8), rng.randf_range(0, 360),
			rng.randf_range(-8, 8))
	var h := rng.randf_range(7.0, 14.0)
	palm.add_child(Greybox.mi(Greybox.cyl(0.55, h, 7), Greybox.mat(Greybox.C_TRUNK),
			Vector3(0, h * 0.5, 0)))
	var fronds := rng.randi_range(5, 7)
	for i in fronds:
		var a := TAU * float(i) / float(fronds)
		var frond := Greybox.mi(Greybox.box(Vector3(6.5, 0.45, 2.0)),
				Greybox.mat(Greybox.C_LEAF if i % 2 == 0 else Greybox.C_LEAF_DARK),
				Vector3(cos(a) * 3.0, h + 0.4, sin(a) * 3.0))
		frond.rotation_degrees = Vector3(0, -rad_to_deg(a), rng.randf_range(-24, -8))
		palm.add_child(frond)
	_world.add_child(palm)


## GDD 5.1 / 9.1: piers march the whole length of the canyon on their own rhythm,
## independent of where the gameplay sector boundaries happen to fall, and every
## broken span leaves its stumps behind. That is what makes the gaps read as
## "this bridge is broken here" instead of "these platforms are separate".
func _build_continuous_structure() -> void:
	var pier := Greybox.mat(Greybox.C_PIER, 0.95)
	var stone := Greybox.mat(Greybox.C_DECK_EDGE, 0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	var z := 6.0
	while z > stage.gate_z - 20.0:
		var group := Node3D.new()
		group.position = Vector3(0, 0, z)
		_world.add_child(group)
		for side in [-1.0, 1.0]:
			group.add_child(Greybox.mi(Greybox.box(Vector3(2.2, 130.0, 2.2)), pier,
					Vector3(side * 3.6, -66.0, 0)))
			group.add_child(Greybox.mi(Greybox.box(Vector3(1.3, 1.3, 7.0)), pier,
					Vector3(side * 3.6, -4.2, 0)))
		group.add_child(Greybox.mi(Greybox.box(Vector3(9.5, 2.0, 2.6)), pier,
				Vector3(0, -12.0, 0)))
		_dress_pier(group, rng)
		z -= 26.0

	# Ruined spans in every gap between authored sectors.
	for i in stage.sectors.size():
		var s: SectorData = stage.sectors[i]
		var span_start := s.world_z - float(s.length - 1) * Tuning.TILE - Tuning.TILE
		var span_end := span_start - s.gap_after + Tuning.TILE * 2.0
		var half := float(s.width) * Tuning.TILE * 0.5
		var ruin := Node3D.new()
		_world.add_child(ruin)
		for k in 4:
			var zz := lerpf(span_start, span_end, rng.randf())
			var drop := rng.randf_range(1.2, 9.0)
			var chunk := Greybox.mi(
				Greybox.box(Vector3(rng.randf_range(1.4, 3.6), 0.8, rng.randf_range(1.4, 3.4))),
				stone, Vector3(rng.randf_range(-half, half), -drop, zz))
			chunk.rotation_degrees = Vector3(rng.randf_range(-45, 45), rng.randf_range(0, 90),
					rng.randf_range(-45, 45))
			ruin.add_child(chunk)
		# Deck stumps jutting out of each broken end. Kept below the deck plane
		# so they never read as a wall in front of the candidate row.
		ruin.add_child(Greybox.mi(Greybox.box(Vector3(half * 1.25, 0.6, 1.8)), stone,
				Vector3(0, -1.25, span_start - 0.8)))
		ruin.add_child(Greybox.mi(Greybox.box(Vector3(half * 1.05, 0.6, 1.5)), stone,
				Vector3(0, -1.45, span_end + 0.9)))


## The bridge has been reclaimed rather than abandoned: vines with flowers spill
## off the piers, banners still hang from the stonework. This is the whole point
## of the Kirby research - the ruin has to read as "the prosperity and joy of
## what once was", never as a horror set.
func _dress_pier(group: Node3D, rng: RandomNumberGenerator) -> void:
	var vine := Greybox.mat(Greybox.C_LEAF_DARK)
	var leaf := Greybox.mat(Greybox.C_LEAF)
	var banner_cols := [Greybox.C_BANNER, Greybox.C_FLOWER_A, Greybox.C_FLOWER_B]

	for side in [-1.0, 1.0]:
		if rng.randf() > 0.45:
			var len_ := rng.randf_range(5.0, 16.0)
			var x: float = side * rng.randf_range(3.2, 4.6)
			group.add_child(Greybox.mi(Greybox.box(Vector3(0.35, len_, 0.35)), vine,
					Vector3(x, -2.0 - len_ * 0.5, rng.randf_range(-1.0, 1.0))))
			for k in rng.randi_range(2, 5):
				var y := -2.5 - rng.randf() * len_
				group.add_child(Greybox.mi(Greybox.sphere(rng.randf_range(0.5, 1.0), 8), leaf,
						Vector3(x + rng.randf_range(-0.9, 0.9), y, rng.randf_range(-0.9, 0.9))))
				if rng.randf() > 0.55:
					group.add_child(Greybox.mi(Greybox.sphere(0.42, 7),
							Greybox.mat(Greybox.C_FLOWER_A if rng.randf() > 0.5
									else Greybox.C_FLOWER_B, 1.0, 0.0, 0.3),
							Vector3(x + rng.randf_range(-1.2, 1.2), y - 0.4,
									rng.randf_range(-1.2, 1.2))))
		if rng.randf() > 0.6:
			var col: Color = banner_cols[rng.randi() % banner_cols.size()]
			var bh := rng.randf_range(4.0, 8.0)
			group.add_child(Greybox.mi(Greybox.box(Vector3(0.18, bh, 2.6)),
					Greybox.mat(col), Vector3(side * 5.0, -1.0 - bh * 0.5, 0)))
			group.add_child(Greybox.mi(Greybox.cone(1.3, 1.6, 6),
					Greybox.mat(col.darkened(0.2)),
					Vector3(side * 5.0, -1.0 - bh, 0)))


## GDD 5.1 / 21: the destination is on screen from the first second and the
## player actually lands on it (Acceptance Criteria 11).
func _build_sun_gate() -> void:
	_gate = Node3D.new()
	_gate.name = "SunGate"
	_gate.position = Vector3(0, 0, stage.gate_z)
	add_child(_gate)

	var stone := Greybox.mat(Color(0.78, 0.66, 0.46), 0.85)
	var dark := Greybox.mat(Color(0.46, 0.36, 0.26), 0.9)
	var gold := Greybox.mat(Color(1.0, 0.84, 0.36), 0.25, 0.0, 0.45, 2.2)

	# Landing platform - 5 tiles wide so the final launch has somewhere to land.
	_gate.add_child(Greybox.mi(Greybox.box(Vector3(14.0, 1.2, 22.0)), stone,
			Vector3(0, -0.6, -8.0)))
	_gate.add_child(Greybox.mi(Greybox.box(Vector3(20.0, 6.0, 26.0)), dark,
			Vector3(0, -4.0, -9.0)))

	for side in [-1.0, 1.0]:
		_gate.add_child(Greybox.mi(Greybox.box(Vector3(9.0, 78.0, 9.0)), stone,
				Vector3(side * 15.0, 38.0, -18.0)))
		_gate.add_child(Greybox.mi(Greybox.box(Vector3(11.5, 6.0, 11.5)), dark,
				Vector3(side * 15.0, 74.0, -18.0)))
		for k in 5:
			_gate.add_child(Greybox.mi(Greybox.box(Vector3(10.5, 1.4, 10.5)), dark,
					Vector3(side * 15.0, 8.0 + k * 14.0, -18.0)))
	_gate.add_child(Greybox.mi(Greybox.box(Vector3(44.0, 9.0, 11.0)), stone,
			Vector3(0, 80.0, -18.0)))
	_gate.add_child(Greybox.mi(Greybox.box(Vector3(52.0, 4.0, 13.0)), dark,
			Vector3(0, 87.0, -18.0)))

	# The sun disc in the gateway - the thing you have been walking toward.
	var disc := Greybox.mi(Greybox.cyl(11.0, 1.2, 32), gold, Vector3(0, 37.0, -20.0))
	disc.rotation_degrees = Vector3(90, 0, 0)
	_gate.add_child(disc)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var ray := Greybox.mi(Greybox.box(Vector3(1.1, 0.6, 7.0)), gold,
				Vector3(cos(a) * 15.5, 37.0 + sin(a) * 15.5, -20.0))
		ray.rotation_degrees = Vector3(90, 0, rad_to_deg(a))
		_gate.add_child(ray)

	# Warm key on the gateway, kept low: cel shading has no headroom, and a hot
	# lamp here flattens the whole structure into one blown-out yellow shape.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.52)
	lamp.light_energy = 2.4
	lamp.omni_range = 48.0
	lamp.position = Vector3(0, 37.0, -17.0)
	_gate.add_child(lamp)


func gate_landing_position() -> Vector3:
	return Vector3(0, 0, stage.gate_z - 4.0)


## GDD 21.1 / 31.11: after the arrival the whole bridge comes down behind you.
func collapse_everything_behind(from_index: int) -> void:
	for i in _sectors.keys():
		var s := sector(i)
		if s != null and i >= from_index:
			s.collapse()
	if intro_sector != null and is_instance_valid(intro_sector):
		intro_sector.collapse()

