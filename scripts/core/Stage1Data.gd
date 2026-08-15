class_name Stage1Data
extends RefCounted

## Stage 1 - Desert Bridge. GDD 20 / 21: an authored stage with a start, a rise,
## a finale and an arrival. Not endless.
##
## 44 sectors. Boards are drawn as ASCII (see SectorData for the legend) with
## the far row first, so the table below reads the way the stage looks.
##
## GDD 18 [LOCK] governs the difficulty curve: the meaning of a number never
## changes, so the ramp comes from combining more clues, longer routes, wider
## decks and less time - never from new arithmetic.
##
##   Learn      one covered band, one clue row.  Deduction depth 1.
##   Master     a second covered band appears; its emptiness has to be proved
##              from a different clue row before the far band can be read.
##              Depth 2.
##   Escalate   five wide, charges cluster so clue numbers reach 2 and 3,
##              fallen columns destroy individual clues (GDD 19 "부분 단서 파손").
##   Remix      all of it, alternating widths, at 144-152 BPM.
##   Finale     the longest routes and the biggest spans.

const INTRO_WIDTH := 5
const INTRO_LENGTH := 13
const INTRO_MINE := Vector2i(2, 10)


## Act 0 free-roam deck (GDD 12.1). Not a puzzle: it is a place to learn the
## controls and to meet the first charge.
static func build_intro_grid() -> MineGrid:
	var g := MineGrid.new(INTRO_WIDTH, INTRO_LENGTH)

	# Scattered unopened slabs, so the player learns that stepping on a covered
	# slab is normal and safe long before one of them turns out not to be.
	for cell in [
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(4, 3), Vector2i(3, 5),
		Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(4, 7),
	]:
		g.set_state(cell, MineGrid.Cell.COVERED)

	for cell in [Vector2i(0, 4), Vector2i(4, 5), Vector2i(1, 8)]:
		g.set_state(cell, MineGrid.Cell.OBSTACLE)

	# The far end of the approach has collapsed to a single passable lane and
	# the last slab of that lane is the charge. Walking forward is enough.
	for r in range(9, INTRO_LENGTH):
		for c in INTRO_WIDTH:
			if c != 2:
				g.set_state(Vector2i(c, r), MineGrid.Cell.HOLE)
	g.set_state(Vector2i(2, 9), MineGrid.Cell.COVERED)
	g.set_state(INTRO_MINE, MineGrid.Cell.COVERED)
	g.set_mine(INTRO_MINE, true)
	for r in range(11, INTRO_LENGTH):
		g.set_state(Vector2i(2, r), MineGrid.Cell.HOLE)

	return g


static func intro_start_cell() -> Vector2i:
	return Vector2i(2, 1)


# ---------------------------------------------------------------------------
# authored sector table
# ---------------------------------------------------------------------------

static func _s(id: String, act: String, rows: Array, gap: float,
		opts: Dictionary = {}) -> SectorData:
	var s := SectorData.new()
	s.id = id
	s.act = act
	s.pattern = PackedStringArray(rows)
	s.gap_after = gap
	s.timing_exempt = opts.get("exempt", false)
	s.spectacle = opts.get("show", "")
	return s


static func sector_table() -> Array[SectorData]:
	var t: Array[SectorData] = []

	# --- Act 1 "Learn" -------------------------------------------------------
	# GDD 12.4: a 0 clue first, then 0 and 1 narrowing to one candidate, then
	# two 1s that only overlap on one cell.
	t.append(_s("L1", "Learn", ["??*", "...", "..."], 20.0, {"exempt": true}))
	t.append(_s("L2", "Learn", ["*??", "...", "..."], 20.0, {"exempt": true}))
	t.append(_s("L3", "Learn", ["?*?", "...", "..."], 21.0, {"exempt": true}))
	t.append(_s("L4", "Learn", ["*??", "...", "...", "..."], 21.0))
	t.append(_s("L5", "Learn", ["??*", "...", "...", "..."], 22.0))
	t.append(_s("L6", "Learn", ["?*?", "...", "...", "..."], 22.0))
	t.append(_s("L7", "Learn", ["*??", "...", "...", "...", "..."], 23.0))

	# --- Act 2 "Master" : a second charged band, so clues stop being 0/1 -----
	t.append(_s("M1", "Master", ["??*", "...", "...", "...", "..."], 23.0))
	t.append(_s("M2", "Master", ["?*?", "...", "...", "...", "..."], 24.0))
	# The second band arrives empty first, so the player learns to walk across
	# covered slabs they have proved safe rather than ones they hope are safe.
	t.append(_s("M3", "Master", ["?*?", "...", "???", "...", "..."], 24.0,
			{"show": "second_band"}))
	t.append(_s("M4", "Master", ["*??", "...", "???", "...", "..."], 25.0))
	# ...and then it is charged too. Two charges stacked in the same column make
	# the upper clue row read 2 2 2 - the first number that is not 0 or 1.
	t.append(_s("M5", "Master", ["?*?", "...", "?*?", "...", "..."], 25.0,
			{"show": "stacked_charge"}))
	t.append(_s("M6", "Master", ["??*", "...", "??*", "...", "..."], 26.0))
	# GDD 21, "First Obstacle": a fallen column across the direct line.
	t.append(_s("M7", "Master", ["??*", "...", "???", ".#.", "...", "..."], 26.0,
			{"show": "fallen_column"}))
	t.append(_s("M8", "Master", ["*??", "...", "*??", "...", "..#", "..."], 27.0))
	t.append(_s("M9", "Master", ["?*?", "...", "???", "...", ".#.", "..."], 27.0))
	t.append(_s("M10", "Master", ["*??", "...", "?*?", "...", "..#", "..."], 28.0))

	# --- Act 3 "Escalate" : five wide, clustered charges, destroyed clues ----
	# GDD 21, "Five Wide": the deck widens, the maths does not change.
	t.append(_s("E1", "Escalate", ["??*??", ".....", "....."], 28.0, {"show": "widen"}))
	t.append(_s("E2", "Escalate", ["????*", ".....", ".....", "....."], 29.0))
	# Two charges side by side: a clue reads 2.
	t.append(_s("E3", "Escalate", ["?**??", ".....", ".....", "....."], 29.0,
			{"show": "twin_charge"}))
	t.append(_s("E4", "Escalate", ["*?*??", ".....", ".....", "....."], 30.0))
	t.append(_s("E5", "Escalate", ["??*??", ".....", "??*??", ".....", "....."], 30.0))
	# GDD 19 "부분 단서 파손": a column has crushed one clue. The clues that
	# survive still force the answer - the solver proves it, every build.
	t.append(_s("E6", "Escalate", ["??*??", "..#..", ".....", "....."], 31.0,
			{"show": "broken_clue"}))
	t.append(_s("E7", "Escalate", ["?*???", ".....", "???*?", ".....", "....."], 31.0))
	t.append(_s("E8", "Escalate", ["*???*", ".....", ".....", "....."], 32.0))
	t.append(_s("E9", "Escalate", ["?*???", ".....", "?*???", "..#..", "....."], 32.0))
	# Three in a row: a clue reads 3.
	t.append(_s("E10", "Escalate", ["?***?", ".....", ".....", "....."], 33.0,
			{"show": "charge_bank"}))
	t.append(_s("E11", "Escalate", ["?*???", "#....", "?????", ".....", "....."], 33.0))
	t.append(_s("E12", "Escalate", ["???*?", ".....", "??*??", "..#..", "....."], 34.0))
	t.append(_s("E13", "Escalate", ["??*?*", ".....", "?????", ".....", "....."], 34.0))
	t.append(_s("E14", "Escalate", ["*????", ".....", "??*??", ".#...", "....."], 35.0))
	t.append(_s("E15", "Escalate", ["??***", ".....", "..#..", "....."], 35.0,
			{"show": "collapse_showpiece"}))

	# --- Act 4 "Remix" : everything already learned, at 144 BPM -------------
	t.append(_s("R1", "Remix", ["?*?", "...", "?*?", "...", "..."], 36.0))
	t.append(_s("R2", "Remix", ["???*?", ".....", "?*???", ".....", "....."], 36.0))
	t.append(_s("R3", "Remix", ["??*", "...", "???", ".#.", "...", "..."], 37.0))
	t.append(_s("R4", "Remix", ["*???*", "...#.", ".....", "....."], 37.0))
	t.append(_s("R5", "Remix", ["???**", ".....", ".....", "....."], 38.0))
	t.append(_s("R6", "Remix", ["*??", "...", "*??", "...", "..#", "..."], 38.0))
	t.append(_s("R7", "Remix", ["??*??", ".....", "??*??", "..#..", "....."], 39.0))
	t.append(_s("R8", "Remix", ["?*???", ".....", "???*?", "~~~..", "....."], 39.0,
			{"show": "sandfall"}))
	t.append(_s("R9", "Remix", ["?**??", ".....", "?????", ".....", "....."], 40.0))

	# --- Finale (GDD 21, 2:55-3:20) -----------------------------------------
	t.append(_s("F1", "Finale", ["???*?", ".....", "?*???", "..#..", "....."], 46.0,
			{"show": "bridge_twist"}))
	t.append(_s("F2", "Finale", ["?***?", ".....", "?????", ".....", "....."], 52.0,
			{"show": "charge_bank"}))
	t.append(_s("F3", "Finale", ["??*??", ".....", ".....", ".....", "....."], 70.0,
			{"show": "final_gap"}))

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


static func build(tempo: TempoMap) -> BuiltStage:
	var out := BuiltStage.new()
	out.sectors = sector_table()

	var intro_end_z := -float(INTRO_LENGTH - 1) * Tuning.TILE
	out.intro_z = 0.0
	var z := intro_end_z - 26.0

	for i in out.sectors.size():
		var s: SectorData = out.sectors[i]
		var grid: MineGrid = s.build_grid()
		s.world_z = z
		out.grids.append(grid)
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

		# GDD 10.2: a scarf glide drops the player onto whatever column they
		# happened to be standing on, so *every* column has to be a legal start.
		var worst := -1
		var worst_col := -1
		for c in s.width:
			var start := Vector2i(c, 0)
			if not grid.is_walkable(start):
				st.errors.append("%s: landing column %d is not walkable" % [s.id, c])
				continue
			for e in grid.validate(start, budget):
				st.errors.append("%s (from col %d): %s" % [s.id, c, e])
			var d := grid.min_dashes_to_mine(start)
			if d > worst:
				worst = d
				worst_col = c
		if worst > budget:
			st.errors.append("%s: worst landing column %d needs %d dashes, budget is %d"
					% [s.id, worst_col, worst, budget])

		var depth := grid.deduction_depth()
		var max_clue := 0
		for r in grid.length:
			for c2 in grid.width:
				var cell := Vector2i(c2, r)
				if grid.state_at(cell) == MineGrid.Cell.REVEALED:
					max_clue = maxi(max_clue, grid.number_at(cell))

		st.report.append("%-4s %-3s %dx%-2d depth %-2s maxclue %d  worst %2d/%2d dash  %.2fs  gap %2.0fm  %s"
				% [s.id, s.act.substr(0, 3), s.width, s.length,
					("case" if depth < 0 else str(depth)), max_clue,
					worst, budget, ground_seconds, s.gap_after, s.ascii_preview()])
