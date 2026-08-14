class_name Stage1Data
extends RefCounted

## Stage 1 - Desert Bridge. GDD 20 / 21: an authored stage with a start, a rise,
## a finale and an arrival. Not endless.
##
## Sectors are authored as "how far forward, how far sideways, what is in the
## way" - the actual clue numbers are always derived by MineGrid, never typed
## in by hand, so a clue can never disagree with the board.

const INTRO_WIDTH := 5
const INTRO_LENGTH := 16
const INTRO_MINE := Vector2i(2, 13)


## Act 0 free-roam deck (GDD 12.1). Not a puzzle: it is a place to learn the
## controls and to meet the first mine. Built directly, not validated as a
## sector, because there is nothing to deduce yet.
static func build_intro_grid() -> MineGrid:
	var g := MineGrid.new(INTRO_WIDTH, INTRO_LENGTH)

	# Scattered unopened slabs, so the player learns that stepping on a covered
	# slab is normal and safe long before one of them turns out not to be.
	for cell in [
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(4, 4), Vector2i(3, 6),
		Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7),
		Vector2i(4, 8), Vector2i(3, 9), Vector2i(0, 10),
	]:
		g.set_state(cell, MineGrid.Cell.COVERED)

	# Ruined railings and a fallen statue give the deck a shape to walk around.
	for cell in [Vector2i(0, 5), Vector2i(4, 6), Vector2i(1, 9)]:
		g.set_state(cell, MineGrid.Cell.OBSTACLE)

	# The far end of the approach has collapsed down to a single passable lane,
	# and the last slab of that lane is the charge. Walking forward is enough.
	for r in range(12, INTRO_LENGTH):
		for c in INTRO_WIDTH:
			if c != 2:
				g.set_state(Vector2i(c, r), MineGrid.Cell.HOLE)
	g.set_state(Vector2i(2, 12), MineGrid.Cell.COVERED)
	g.set_state(INTRO_MINE, MineGrid.Cell.COVERED)
	g.set_mine(INTRO_MINE, true)
	for r in range(14, INTRO_LENGTH):
		g.set_state(Vector2i(2, r), MineGrid.Cell.HOLE)

	return g


static func intro_start_cell() -> Vector2i:
	return Vector2i(2, 1)


# ---------------------------------------------------------------------------
# authored sector table
# ---------------------------------------------------------------------------

static func _s(p: Dictionary) -> SectorData:
	var s := SectorData.new()
	s.id = p.get("id", "?")
	s.act = p.get("act", "")
	s.width = p.get("w", 3)
	s.length = p.get("l", 3)
	s.mine_lat = p.get("lat", 0)
	s.mine_lat_2 = p.get("lat2", 9999)
	s.gap_after = p.get("gap", 22.0)
	s.timing_exempt = p.get("exempt", false)
	s.spectacle = p.get("show", "")
	var obs: Array[Vector2i] = []
	for v in p.get("obs", []):
		obs.append(v)
	s.obstacles = obs
	var hol: Array[Vector2i] = []
	for v in p.get("holes", []):
		hol.append(v)
	s.holes = hol
	var snd: Array[Vector2i] = []
	for v in p.get("sand", []):
		snd.append(v)
	s.sand = snd
	s.set_meta("mine_abs", p.get("abs", []))
	return s


## GDD 21 beat sheet, expressed as sectors. 34 sectors * 8 beats = 272 beats of
## play after the accident, which lands the Sun Gate at roughly 3:05.
static func sector_table() -> Array[SectorData]:
	var t: Array[SectorData] = []

	# --- Act 1 "Learn" : 3 wide, nothing in the way, generous time ----------
	# GDD 12.4: first a 0 clue, then 0+1 narrowing to one candidate, then two
	# 1s that only overlap on one cell.
	t.append(_s({"id": "L1", "act": "Learn", "w": 3, "l": 3, "lat": 1, "gap": 20.0, "exempt": true}))
	t.append(_s({"id": "L2", "act": "Learn", "w": 3, "l": 3, "lat": -2, "gap": 20.0, "exempt": true}))
	t.append(_s({"id": "L3", "act": "Learn", "w": 3, "l": 3, "lat": 1, "gap": 20.0, "exempt": true}))
	t.append(_s({"id": "L4", "act": "Learn", "w": 3, "l": 4, "lat": -1, "gap": 21.0}))
	t.append(_s({"id": "L5", "act": "Learn", "w": 3, "l": 4, "lat": 2, "gap": 21.0}))
	t.append(_s({"id": "L6", "act": "Learn", "w": 3, "l": 4, "lat": -1, "gap": 22.0}))

	# --- Act 2 "Master" : same rules, further to run ------------------------
	t.append(_s({"id": "M1", "act": "Master", "w": 3, "l": 5, "lat": 1, "gap": 23.0}))
	t.append(_s({"id": "M2", "act": "Master", "w": 3, "l": 5, "lat": -2, "gap": 23.0}))
	t.append(_s({"id": "M3", "act": "Master", "w": 3, "l": 5, "lat": 1, "gap": 24.0}))
	t.append(_s({"id": "M4", "act": "Master", "w": 3, "l": 6, "lat": 1, "gap": 24.0}))
	t.append(_s({"id": "M5", "act": "Master", "w": 3, "l": 6, "lat": -2, "gap": 25.0}))
	t.append(_s({"id": "M6", "act": "Master", "w": 3, "l": 6, "lat": 2, "gap": 25.0}))
	# GDD 21, 1:20-1:45 "First Obstacle": a fallen column across the direct line.
	t.append(_s({"id": "M7", "act": "Master", "w": 3, "l": 6, "lat": -2, "gap": 26.0,
			"obs": [Vector2i(1, 2), Vector2i(1, 3)], "show": "fallen_column"}))
	t.append(_s({"id": "M8", "act": "Master", "w": 3, "l": 6, "lat": 2, "gap": 26.0,
			"obs": [Vector2i(1, 3)], "holes": [Vector2i(0, 2)]}))

	# --- Act 3 "Escalate" : 5 wide, obstacles, big structural collapse ------
	t.append(_s({"id": "E1", "act": "Escalate", "w": 3, "l": 6, "lat": -2, "gap": 27.0,
			"obs": [Vector2i(1, 1), Vector2i(2, 3)]}))
	t.append(_s({"id": "E2", "act": "Escalate", "w": 3, "l": 6, "lat": -1, "gap": 28.0,
			"obs": [Vector2i(0, 2), Vector2i(2, 3)]}))
	# GDD 21, 1:45-2:10 "Five Wide": the deck widens, the maths does not change.
	t.append(_s({"id": "E3", "act": "Escalate", "w": 5, "l": 5, "lat": 2, "gap": 28.0,
			"show": "widen"}))
	t.append(_s({"id": "E4", "act": "Escalate", "w": 5, "l": 5, "lat": -3, "gap": 29.0}))
	t.append(_s({"id": "E5", "act": "Escalate", "w": 5, "l": 6, "lat": 3, "gap": 29.0}))
	t.append(_s({"id": "E6", "act": "Escalate", "w": 5, "l": 6, "lat": -3, "gap": 30.0}))
	t.append(_s({"id": "E7", "act": "Escalate", "w": 5, "l": 6, "lat": 3, "gap": 30.0,
			"obs": [Vector2i(2, 2), Vector2i(2, 3)]}))
	t.append(_s({"id": "E8", "act": "Escalate", "w": 5, "l": 6, "lat": -3, "gap": 31.0,
			"obs": [Vector2i(1, 2), Vector2i(3, 3)], "sand": [Vector2i(2, 1)]}))
	t.append(_s({"id": "E9", "act": "Escalate", "w": 5, "l": 6, "lat": 3, "gap": 31.0,
			"obs": [Vector2i(2, 2), Vector2i(3, 3)]}))
	t.append(_s({"id": "E10", "act": "Escalate", "w": 5, "l": 6, "lat": -3, "gap": 32.0,
			"obs": [Vector2i(1, 2), Vector2i(1, 3), Vector2i(3, 3)]}))
	# GDD 19 [TEST] "지뢰 2개": two legal escapes, one near and one far.
	# Columns are pinned so the clue row reads 1 1 0 1 1, which forces both.
	t.append(_s({"id": "E11", "act": "Escalate", "w": 5, "l": 6, "gap": 33.0,
			"abs": [0, 4], "show": "collapse_showpiece"}))
	t.append(_s({"id": "E12", "act": "Escalate", "w": 5, "l": 6, "lat": 3, "gap": 34.0,
			"obs": [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)], "show": "pier_fall"}))

	# --- Act 4 "Remix" : everything already learned, fast ------------------
	t.append(_s({"id": "R1", "act": "Remix", "w": 3, "l": 5, "lat": 2, "gap": 34.0}))
	t.append(_s({"id": "R2", "act": "Remix", "w": 5, "l": 5, "lat": -3, "gap": 35.0}))
	t.append(_s({"id": "R3", "act": "Remix", "w": 3, "l": 5, "lat": 2, "gap": 35.0,
			"obs": [Vector2i(1, 2)]}))
	t.append(_s({"id": "R4", "act": "Remix", "w": 5, "l": 6, "lat": 3, "gap": 36.0,
			"obs": [Vector2i(2, 2)]}))
	t.append(_s({"id": "R5", "act": "Remix", "w": 3, "l": 6, "lat": -2, "gap": 36.0,
			"obs": [Vector2i(1, 1), Vector2i(1, 3)]}))
	t.append(_s({"id": "R6", "act": "Remix", "w": 5, "l": 6, "lat": 4, "gap": 38.0,
			"obs": [Vector2i(2, 3)]}))

	# --- Finale (GDD 21, 2:55-3:20) ----------------------------------------
	t.append(_s({"id": "F1", "act": "Finale", "w": 5, "l": 6, "lat": -4, "gap": 46.0,
			"show": "bridge_twist"}))
	t.append(_s({"id": "F2", "act": "Finale", "w": 5, "l": 5, "gap": 64.0,
			"abs": [2], "show": "final_gap"}))

	return t


# ---------------------------------------------------------------------------
# chain build + validation (GDD 27.1)
# ---------------------------------------------------------------------------

class BuiltStage extends RefCounted:
	var sectors: Array[SectorData] = []
	var grids: Array = []                 ## Array[MineGrid], parallel to sectors
	var errors: PackedStringArray = PackedStringArray()
	var report: PackedStringArray = PackedStringArray()
	var intro_z: float = 0.0
	var gate_z: float = 0.0


## Lay the whole bridge out, resolve every mine column, and prove every sector.
static func build(tempo: TempoMap) -> BuiltStage:
	var out := BuiltStage.new()
	out.sectors = sector_table()

	# The intro deck runs from z=0 backwards; sector 0 starts past its end.
	var intro_end_z := -float(INTRO_LENGTH - 1) * Tuning.TILE
	out.intro_z = 0.0
	var z := intro_end_z - 26.0

	# Nominal landing column, carried across the gap with no air steering.
	# The intro charge sits in the middle lane, so sector 0 starts centred.
	var carry_x := SectorData.col_to_x(INTRO_MINE.x, INTRO_WIDTH)

	for i in out.sectors.size():
		var s: SectorData = out.sectors[i]
		s.world_z = z
		s.start_col = SectorData.x_to_col(carry_x, s.width)

		var abs_cols: Array = s.get_meta("mine_abs", [])
		if abs_cols.is_empty():
			s.mine_cols = s.resolve_mine_cols(s.start_col)
		else:
			var mc: Array[int] = []
			for c in abs_cols:
				mc.append(clampi(int(c), 0, s.width - 1))
			s.mine_cols = mc

		var grid: MineGrid = s.build_grid()
		out.grids.append(grid)

		carry_x = SectorData.col_to_x(s.mine_cols[0], s.width)
		z -= float(s.length - 1) * Tuning.TILE + s.gap_after

	out.gate_z = z

	_validate(out, tempo)
	return out


static func _validate(st: BuiltStage, tempo: TempoMap) -> void:
	for i in st.sectors.size():
		var s: SectorData = st.sectors[i]
		var grid: MineGrid = st.grids[i]

		st.errors.append_array(s.structural_errors())

		var gb := Tuning.sector_ground_beat(i)
		var ground_seconds := tempo.time_at_beat(gb + Tuning.GROUND_BEATS) - tempo.time_at_beat(gb)
		var budget := Tuning.ground_dash_budget(ground_seconds)

		# Uniqueness, clue honesty and obstacle sanity, from the nominal start.
		for e in grid.validate(Vector2i(s.start_col, 0), budget):
			st.errors.append("%s: %s" % [s.id, e])

		# GDD 10.2: a scarf glide drops the player into the next sector on
		# whatever column they happened to be standing on, and a two-mine sector
		# can end on either column. So every column has to be a legal landing.
		var worst := -1
		var worst_col := -1
		for c in s.width:
			var start := Vector2i(c, 0)
			if not grid.is_walkable(start):
				st.errors.append("%s: landing column %d is not walkable" % [s.id, c])
				continue
			var d := grid.min_dashes_to_mine(start)
			if d < 0:
				st.errors.append("%s: no mine reachable from landing column %d" % [s.id, c])
				continue
			if d > worst:
				worst = d
				worst_col = c
		if worst > budget:
			st.errors.append("%s: worst landing column %d needs %d dashes, budget is %d"
					% [s.id, worst_col, worst, budget])

		st.report.append("%-4s %s  %dx%d  start c%d  mine %s  worst %d/%d dash  %.2fs ground  gap %.0fm"
				% [s.id, s.act.substr(0, 3), s.width, s.length, s.start_col,
					str(s.mine_cols), worst, budget, ground_seconds, s.gap_after])
