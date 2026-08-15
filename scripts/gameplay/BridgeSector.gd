class_name BridgeSector
extends Node3D

## GDD 9 / 25: one authored stretch of the bridge.
##
## GDD 9 [LOCK]: "platform" is a logic word. On screen this must read as a
## continuous stretch of the same stone bridge - deck, kerbs, railings, piers,
## structural joints - never as a square island floating in the sky.
## GDD 6.1 [LOCK]: damage is applied to the whole sector as one body, 1 -> 2 ->
## 3, and the whole thing goes on GO. Tiles are never deleted one at a time from
## the back (GDD 30).

signal collapse_finished

const SETTLE := [0.0, 0.07, 0.22, 0.46]
const TILT_DEG := [0.0, 0.20, 0.60, 1.45]
const DAMAGE_TINT := [
	Color(1.00, 1.00, 1.00),
	Color(0.97, 0.94, 0.90),
	Color(0.90, 0.84, 0.78),
	Color(0.82, 0.73, 0.66),
]

var data: SectorData
var grid: MineGrid
var index := 0
var damage := 0
var revealed := false

var _deck: Node3D
var _cracks: Node3D
var _tiles: Dictionary = {}          ## Vector2i -> Node3D
var _covered_caps: Dictionary = {}   ## Vector2i -> Node3D
var _mats: Dictionary = {}           ## key -> ShaderMaterial, owned by this sector
var _base_albedo: Dictionary = {}
var _tile_keys: Dictionary = {}      ## keys whose material is the tile shader
var _dust: Array[GPUParticles3D] = []

var _collapsing := false
var _collapse_t := 0.0
var _fall_vel := 0.0
var _spin := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


## Every sector owns its own material instances so that damage can tint the
## whole body at once without touching any other sector.
func _m(key: String, color: Color, _rough: float = 1.0, metal: float = 0.0) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var opts := {}
	if metal > 0.4:
		opts["rim"] = 1.6
		opts["bands"] = 4.0
	var mt := Greybox.toon(color, opts)
	_mats[key] = mt
	_base_albedo[key] = color
	return mt


## Tile faces are their own materials so a sector can tint them with damage
## alongside everything else.
func _tile_mat(key: String, covered: bool, face: Color) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var mt := Greybox.tile_material(covered, face)
	_mats[key] = mt
	_base_albedo[key] = face
	_tile_keys[key] = true
	return mt


func build(d: SectorData, g: MineGrid, sector_index: int) -> void:
	data = d
	grid = g
	index = sector_index
	position = Vector3(0.0, 0.0, d.world_z)
	_rng.seed = hash("sector%d" % sector_index)
	set_process(false)

	_deck = Node3D.new()
	_deck.name = "Deck"
	add_child(_deck)
	_cracks = Node3D.new()
	_cracks.name = "Cracks"
	_cracks.visible = false
	add_child(_cracks)

	for r in g.length:
		for c in g.width:
			_build_cell(Vector2i(c, r))

	_build_structure()
	_build_cracks()


# ---------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------

func _build_cell(cell: Vector2i) -> void:
	var state := grid.state_at(cell)
	if state == MineGrid.Cell.HOLE:
		_build_broken_edge(cell)
		return

	var node := Node3D.new()
	node.position = data.cell_to_local(cell)
	_deck.add_child(node)
	_tiles[cell] = node

	var is_sand: bool = data.sand_cells.has(cell)
	var slab_key := "sand" if is_sand else "deck"
	var slab_color := Greybox.C_SAND if is_sand else Greybox.C_DECK
	# The slab body carries the thickness; its face carries the Minesweeper
	# bevel and grid line (see shaders/tile.gdshader).
	node.add_child(Greybox.mi(
		Greybox.box(Vector3(Tuning.TILE, Tuning.DECK_THICKNESS, Tuning.TILE)),
		_m(slab_key, slab_color.darkened(0.18)),
		Vector3(0, -Tuning.DECK_THICKNESS * 0.5, 0)))
	if state != MineGrid.Cell.COVERED:
		node.add_child(Greybox.mi(Greybox.plane(Vector2(Tuning.TILE, Tuning.TILE)),
				_tile_mat("open_" + slab_key, false, slab_color), Vector3(0, 0.006, 0)))

	match state:
		MineGrid.Cell.COVERED:
			_build_covered_cap(node, cell)
		MineGrid.Cell.OBSTACLE:
			_build_obstacle(node, cell)
		_:
			var n := grid.number_at(cell)
			if n > 0:
				node.add_child(Greybox.number_label(n))


## GDD 8.1: an unopened slab is a raised, strongly bevelled stone that reads as
## "press me". A two-step profile keeps that silhouette from any camera angle.
## GDD 8.1: an unopened slab is a raised button. One block of the right height
## plus the bevelled face shader, rather than a stack of shrinking boxes - the
## bevel is drawn, so it stays crisp at any distance and any tile size.
func _build_covered_cap(node: Node3D, cell: Vector2i) -> void:
	var cap := Node3D.new()
	cap.name = "Cap"
	node.add_child(cap)
	cap.add_child(Greybox.mi(
		Greybox.box(Vector3(Tuning.TILE, Tuning.COVERED_RISE, Tuning.TILE)),
		_m("cov_side", Greybox.C_COVERED.darkened(0.30)),
		Vector3(0, Tuning.COVERED_RISE * 0.5, 0)))
	cap.add_child(Greybox.mi(
		Greybox.plane(Vector2(Tuning.TILE, Tuning.TILE)),
		_tile_mat("cov_face", true, Greybox.C_COVERED),
		Vector3(0, Tuning.COVERED_RISE + 0.006, 0)))
	_covered_caps[cell] = cap


## GDD 9.2 / 8.1: an obstacle must never be mistakable for an unopened slab, so
## it gets the opposite silhouette - tall, dark, round and broken.
func _build_obstacle(node: Node3D, cell: Vector2i) -> void:
	var mt := _m("obstacle", Greybox.C_OBSTACLE, 0.95)
	var seed := hash(Vector2i(cell.x + index * 31, cell.y))
	var r := RandomNumberGenerator.new()
	r.seed = seed

	var drum := Greybox.mi(Greybox.cyl(0.62, 1.55, 12), mt, Vector3(0, 0.72, 0))
	drum.rotation_degrees = Vector3(r.randf_range(-14, 14), r.randf_range(0, 90),
			r.randf_range(-14, 14))
	node.add_child(drum)

	var chunk := Greybox.mi(Greybox.cyl(0.55, 0.85, 10), mt, Vector3(0.32, 0.24, -0.28))
	chunk.rotation_degrees = Vector3(78, r.randf_range(0, 180), 0)
	node.add_child(chunk)

	var top := Greybox.mi(Greybox.box(Vector3(1.32, 0.28, 1.32)), mt, Vector3(0, 1.58, 0))
	top.rotation_degrees = Vector3(0, r.randf_range(0, 45), 0)
	node.add_child(top)


func _build_broken_edge(cell: Vector2i) -> void:
	var node := Node3D.new()
	node.position = data.cell_to_local(cell)
	_deck.add_child(node)
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(cell.x * 7 + index, cell.y * 13))
	for i in 2:
		var stub := Greybox.mi(
			Greybox.box(Vector3(r.randf_range(0.4, 0.9), Tuning.DECK_THICKNESS * 0.8,
					r.randf_range(0.4, 0.9))),
			_m("edge", Greybox.C_DECK_EDGE),
			Vector3(r.randf_range(-0.7, 0.7), -Tuning.DECK_THICKNESS * 0.7,
					r.randf_range(-0.7, 0.7)))
		stub.rotation_degrees = Vector3(r.randf_range(-20, 20), 0, r.randf_range(-20, 20))
		node.add_child(stub)


## GDD 9.1 / 15.2: kerbs, railings, posts, an underside, a maintenance walkway
## and piers into the canyon, so the sector boundary reads as a structural joint
## rather than as the edge of an island.
func _build_structure() -> void:
	var half := float(data.width) * Tuning.TILE * 0.5
	var span := float(data.length) * Tuning.TILE
	var mid_z := -float(data.length - 1) * Tuning.TILE * 0.5
	var rail := _m("rail", Greybox.C_RAIL, 0.9)
	var pier := _m("pier", Greybox.C_PIER, 0.95)

	for side in [-1.0, 1.0]:
		var x: float = side * (half + 0.28)
		_deck.add_child(Greybox.mi(Greybox.box(Vector3(0.55, 0.42, span)), rail,
				Vector3(x, -0.12, mid_z)))
		_deck.add_child(Greybox.mi(Greybox.box(Vector3(0.16, 0.60, span)), rail,
				Vector3(x, 1.05, mid_z)))
		var posts := maxi(2, data.length / 2)
		for i in posts:
			var z := -float(i) * span / float(posts) - 0.4
			_deck.add_child(Greybox.mi(Greybox.box(Vector3(0.30, 1.10, 0.30)), rail,
					Vector3(x, 0.45, z)))

	_deck.add_child(Greybox.mi(Greybox.box(Vector3(half * 2.0 + 1.1, 0.9, span)), pier,
			Vector3(0, -1.05, mid_z)))

	# GDD 10.2 [TEST]: the lower maintenance route a scarf glide sags through.
	_deck.add_child(Greybox.mi(Greybox.box(Vector3(half * 1.05, 0.30, span)), pier,
			Vector3(0, -7.9, mid_z)))
	for side2 in [-1.0, 1.0]:
		_deck.add_child(Greybox.mi(Greybox.box(Vector3(0.22, 7.0, 0.22)), pier,
				Vector3(side2 * half * 0.5, -4.4, mid_z)))

	for z_end in [0.0, -float(data.length - 1) * Tuning.TILE]:
		var joint := Node3D.new()
		joint.position = Vector3(0, 0, z_end)
		_deck.add_child(joint)
		joint.add_child(Greybox.mi(Greybox.box(Vector3(half * 2.0 + 1.4, 1.2, 1.5)), pier,
				Vector3(0, -1.9, 0)))
		for side3 in [-1.0, 1.0]:
			joint.add_child(Greybox.mi(Greybox.box(Vector3(1.6, 36.0, 1.6)), pier,
					Vector3(side3 * half * 0.62, -20.5, 0)))
			joint.add_child(Greybox.mi(Greybox.box(Vector3(1.1, 1.1, 3.4)), pier,
					Vector3(side3 * half * 0.62, -3.0, -1.4)))


## GDD 16: the crack network that widens across damage stages 1-3.
func _build_cracks() -> void:
	var half := float(data.width) * Tuning.TILE * 0.5
	# Cracks are confined to the rows nearest the player that carry no
	# information at all - no covered slabs, no numbers. A clue can then never
	# be read through a crack (GDD 15.3, and GDD 30 bans exactly this).
	var last_blank := 0
	for r in grid.length:
		var blank := true
		for c in grid.width:
			var cell := Vector2i(c, r)
			if grid.state_at(cell) != MineGrid.Cell.REVEALED or grid.number_at(cell) > 0:
				blank = false
				break
		if not blank:
			break
		last_blank = r
	var span := float(last_blank) * Tuning.TILE
	var mt := _m("crack", Color(0.16, 0.13, 0.11), 1.0)
	for i in maxi(4, data.length):
		var z := -_rng.randf_range(0.0, span)
		var x := _rng.randf_range(-half, half)
		var len_ := _rng.randf_range(0.9, 2.0)
		var c := Greybox.mi(Greybox.box(Vector3(0.10, 0.06, len_)), mt, Vector3(x, 0.02, z))
		c.rotation_degrees = Vector3(0, _rng.randf_range(-70, 70), 0)
		c.scale = Vector3(1, 1, 0.25)
		_cracks.add_child(c)


# ---------------------------------------------------------------------------
# damage - GDD 6.1 / 16
# ---------------------------------------------------------------------------

func set_damage(stage: int) -> void:
	damage = clampi(stage, 0, 3)

	# The whole sector settles and leans as one body (GDD 6.1 [LOCK]).
	position.y = -SETTLE[damage]
	var lean := 1.0 if index % 2 == 0 else -1.0
	rotation_degrees.z = TILT_DEG[damage] * lean
	rotation_degrees.x = -TILT_DEG[damage] * 0.35

	var tint: Color = DAMAGE_TINT[damage]
	for key in _mats:
		var base: Color = _base_albedo[key]
		var c := Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a)
		if _tile_keys.has(key):
			var mt: ShaderMaterial = _mats[key]
			mt.set_shader_parameter("face_color", c)
			mt.set_shader_parameter("bevel_light", c.lightened(0.42))
			mt.set_shader_parameter("bevel_dark", c.darkened(0.34))
		else:
			Greybox.set_albedo(_mats[key], c)

	_cracks.visible = damage > 0
	for c in _cracks.get_children():
		(c as Node3D).scale = Vector3(1.0 + 0.5 * damage, 1.0, 0.25 + 0.28 * damage)

	if damage > 0:
		_spawn_dust(damage)


## GDD 16: sand pouring through the widening cracks, then falling stone.
func _spawn_dust(stage: int) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.4 * stage
	pm.initial_velocity_max = 1.5 * stage
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.05
	pm.scale_max = 0.10 + 0.05 * stage
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(float(data.width) * Tuning.TILE * 0.5, 0.2,
			float(data.length) * Tuning.TILE * 0.5)
	p.process_material = pm
	p.draw_pass_1 = Greybox.box(Vector3(0.13, 0.13, 0.13))
	p.material_override = Greybox.mat(Color(0.78, 0.69, 0.53))
	p.amount = 10 * stage
	p.lifetime = 1.5
	p.explosiveness = 0.1
	p.position = Vector3(0, -0.6, -float(data.length - 1) * Tuning.TILE * 0.5)
	add_child(p)
	p.emitting = true
	_dust.append(p)


# ---------------------------------------------------------------------------
# the GO moment - GDD 10.3 / 6.1
# ---------------------------------------------------------------------------

## Every covered slab in the candidate row opens and shows what was under it.
## The player learns "ah, that one was the mine" from the world itself. No WRONG
## text, no warning box, no pause (GDD 10.3 [LOCK]).
func reveal_all_candidates() -> void:
	if revealed:
		return
	revealed = true
	for cell in _covered_caps.keys():
		var cap: Node3D = _covered_caps[cell]
		var node: Node3D = _tiles[cell]
		cap.queue_free()
		if grid.is_mine(cell):
			node.add_child(_build_mine_visual())
		else:
			var n := grid.number_at(cell)
			if n > 0:
				node.add_child(Greybox.number_label(n))
	_covered_caps.clear()


## GDD 8.1: the charge only shows itself as it opens - an ancient brass demolition
## device sunk into the deck, unmistakable and nothing like an obstacle.
func _build_mine_visual() -> Node3D:
	var n := Node3D.new()
	n.name = "Mine"
	n.add_child(Greybox.mi(Greybox.cyl(0.68, 0.16, 14),
			_m("mine_trim", Greybox.C_MINE_TRIM, 0.35, 0.85), Vector3(0, 0.06, 0)))
	n.add_child(Greybox.mi(Greybox.sphere(0.44, 14),
			_m("mine_body", Greybox.C_MINE_BODY, 0.45, 0.7), Vector3(0, 0.30, 0)))
	for i in 5:
		var a := TAU * float(i) / 5.0
		var spike := Greybox.mi(Greybox.cyl(0.07, 0.34, 6), _m("mine_trim", Greybox.C_MINE_TRIM),
				Vector3(cos(a) * 0.38, 0.46, sin(a) * 0.38))
		spike.rotation_degrees = Vector3(sin(a) * 20.0, 0.0, -cos(a) * 20.0)
		n.add_child(spike)
	return n


## GDD 23: the only hint this game is allowed to give. It shows which cells a
## single clue is *counting* - the adjacency relationship - and never which cell
## is the answer (GDD 30 forbids that outright). Offered only after the player
## has been struggling, and switchable off.
## Picks the clue nearest the given landing column that actually constrains
## something, so the hint below has something worth showing.
func best_clue_for(col: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := 999.0
	for r in grid.length:
		for c in grid.width:
			var cell := Vector2i(c, r)
			if grid.state_at(cell) != MineGrid.Cell.REVEALED or grid.number_at(cell) <= 0:
				continue
			var score := absf(float(c - col)) + float(grid.length - r) * 0.35
			if score < best_score:
				best_score = score
				best = cell
	return best


func flash_adjacency(clue: Vector2i) -> void:
	if clue.x < 0:
		return
	var holder := Node3D.new()
	add_child(holder)
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(1.0, 0.95, 0.72, 0.30)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for d in MineGrid.NEIGHBORS_8:
		var c: Vector2i = clue + d
		if not grid.in_bounds(c):
			continue
		var q := Greybox.mi(Greybox.box(Vector3(Tuning.TILE - 0.2, 0.05, Tuning.TILE - 0.2)), mt,
				data.cell_to_local(c) + Vector3(0, 0.42, 0))
		holder.add_child(q)
	var tw := create_tween()
	tw.tween_property(mt, "albedo_color:a", 0.0, 1.6).set_delay(0.9)
	tw.tween_callback(holder.queue_free)


func cell_world_position(cell: Vector2i) -> Vector3:
	return Vector3(0.0, 0.0, data.world_z) + data.cell_to_local(cell)


## GDD 6.1 / 16: the whole deck fractures and drops, and the kerbs, railings and
## piers go with it - a building failing, not a tile disappearing.
func collapse() -> void:
	if _collapsing:
		return
	_collapsing = true
	reveal_all_candidates()
	for p in _dust:
		p.emitting = false
	_spin = Vector3(_rng.randf_range(-0.50, -0.14), _rng.randf_range(-0.25, 0.25),
			_rng.randf_range(-0.40, 0.40))
	_fall_vel = 1.4
	set_process(true)


func _process(delta: float) -> void:
	if not _collapsing:
		return
	_collapse_t += delta
	_fall_vel += 26.0 * delta
	position.y -= _fall_vel * delta
	rotation += _spin * delta
	if _collapse_t > 5.5:
		collapse_finished.emit()
		queue_free()
