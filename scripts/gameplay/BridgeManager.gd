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
	intro_data.width = Stage1Data.INTRO_WIDTH
	intro_data.length = Stage1Data.INTRO_LENGTH
	intro_data.world_z = 0.0
	intro_data.mine_cols = [Stage1Data.INTRO_MINE.x]

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

func _build_canyon() -> void:
	var far_z := stage.gate_z - 160.0
	var rock := Greybox.mat(Color(0.52, 0.40, 0.31), 1.0)
	var rock2 := Greybox.mat(Color(0.60, 0.47, 0.36), 1.0)
	var floor_mat := Greybox.mat(Color(0.68, 0.56, 0.40), 1.0)

	# Canyon floor, a long way down. GDD 5.1: this is a gorge, not a void.
	_world.add_child(Greybox.mi(Greybox.box(Vector3(520.0, 8.0, absf(far_z) + 400.0)),
			floor_mat, Vector3(0, -132.0, far_z * 0.5)))

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for side in [-1.0, 1.0]:
		_world.add_child(Greybox.mi(Greybox.box(Vector3(140.0, 210.0, absf(far_z) + 400.0)),
				rock, Vector3(side * 200.0, -30.0, far_z * 0.5)))
		var z := 40.0
		while z > far_z:
			var w := rng.randf_range(20.0, 55.0)
			var h := rng.randf_range(50.0, 170.0)
			var mesa := Greybox.mi(Greybox.box(Vector3(w, h, rng.randf_range(24.0, 70.0))),
					rock2 if rng.randf() > 0.5 else rock,
					Vector3(side * rng.randf_range(105.0, 165.0), -70.0 + h * 0.5, z))
			mesa.rotation_degrees = Vector3(0, rng.randf_range(-16, 16), 0)
			_world.add_child(mesa)
			z -= rng.randf_range(45.0, 90.0)


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


## GDD 5.1 / 21: the destination is on screen from the first second and the
## player actually lands on it (Acceptance Criteria 11).
func _build_sun_gate() -> void:
	_gate = Node3D.new()
	_gate.name = "SunGate"
	_gate.position = Vector3(0, 0, stage.gate_z)
	add_child(_gate)

	var stone := Greybox.mat(Color(0.78, 0.66, 0.46), 0.85)
	var dark := Greybox.mat(Color(0.46, 0.36, 0.26), 0.9)
	var gold := Greybox.mat(Color(1.0, 0.80, 0.32), 0.25, 0.9, 1.6)

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
	var disc := Greybox.mi(Greybox.cyl(11.0, 1.2, 32), gold, Vector3(0, 44.0, -20.0))
	disc.rotation_degrees = Vector3(90, 0, 0)
	_gate.add_child(disc)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var ray := Greybox.mi(Greybox.box(Vector3(1.1, 0.6, 7.0)), gold,
				Vector3(cos(a) * 15.5, 44.0 + sin(a) * 15.5, -20.0))
		ray.rotation_degrees = Vector3(90, 0, rad_to_deg(a))
		_gate.add_child(ray)

	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.45)
	lamp.light_energy = 8.0
	lamp.omni_range = 70.0
	lamp.position = Vector3(0, 44.0, -18.0)
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
