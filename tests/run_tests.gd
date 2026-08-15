extends SceneTree

## Headless test runner. GDD 25.1: MineGrid must be testable with no graphics.
##   S:\GameDev\Godot\Godot_v4.7-stable_win64_console.exe --headless \
##       --path S:\GameDev\MineBeatRush --script res://tests/run_tests.gd

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== MineBeat Rush test run ===")
	_test_number_rule()
	_test_three_wide_patterns()
	_test_five_wide_pattern()
	_test_two_mine_pattern()
	_test_ambiguous_is_rejected()
	_test_pattern_authoring()
	_test_destroyed_clues()
	_test_two_band_boards()
	_test_movement_rules()
	_test_obstacle_routing()
	_test_tempo_map()
	_test_launch_curve()
	_test_stage_chain()

	print("\n=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		printerr("  FAIL  %s" % label)


func eq(a: Variant, b: Variant, label: String) -> void:
	if a == b:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		printerr("  FAIL  %s   (got %s, want %s)" % [label, str(a), str(b)])


# ---------------------------------------------------------------------------

func _sector(width: int, length: int, mine_cols: Array) -> MineGrid:
	var g := MineGrid.new(width, length)
	for c in width:
		g.set_state(Vector2i(c, length - 1), MineGrid.Cell.COVERED)
	for mc in mine_cols:
		g.set_mine(Vector2i(mc, length - 1), true)
	return g


func _clue_row(g: MineGrid) -> Array:
	return _clue_row_of(g, g.length - 2)


func _clue_row_of(g: MineGrid, row: int) -> Array:
	var out := []
	for c in g.width:
		out.append(g.number_at(Vector2i(c, row)))
	return out


## Build a grid straight from an authored ASCII board, exactly the way
## Stage1Data does, so the tests exercise the real authoring path.
func _pattern(rows: Array) -> MineGrid:
	var s := SectorData.new()
	s.id = "test"
	s.pattern = PackedStringArray(rows)
	return s.build_grid()


func _test_number_rule() -> void:
	print("\n[number = count of adjacent mines, 8-neighbourhood]  GDD 8 [LOCK]")
	var g := _sector(3, 3, [1])
	eq(g.number_at(Vector2i(1, 1)), 1, "clue directly behind the mine reads 1")
	eq(g.number_at(Vector2i(0, 1)), 1, "diagonal neighbour also counts")
	eq(g.number_at(Vector2i(1, 0)), 0, "two rows away reads 0")
	var g2 := _sector(5, 3, [1, 3])
	eq(g2.number_at(Vector2i(2, 1)), 2, "a clue between two mines reads 2")


func _test_three_wide_patterns() -> void:
	print("\n[3 wide, the GDD 8.2 patterns]")
	for mine_col in 3:
		var g := _sector(3, 3, [mine_col])
		var res := g.solve()
		ok(res.forced_mines.size() == 1 and res.forced_mines[0] == Vector2i(mine_col, 2),
			"mine at col %d is forced by %s" % [mine_col, str(_clue_row(g))])
	eq(_clue_row(_sector(3, 3, [0])), [1, 1, 0], "col 0 mine reads 1 1 0 (GDD 8.2 example)")
	eq(_clue_row(_sector(3, 3, [2])), [0, 1, 1], "col 2 mine reads 0 1 1")
	eq(_clue_row(_sector(3, 3, [1])), [1, 1, 1], "col 1 mine reads 1 1 1")


func _test_five_wide_pattern() -> void:
	print("\n[5 wide, same rule, wider deck]  GDD 8.3")
	eq(_clue_row(_sector(5, 3, [2])), [0, 1, 1, 1, 0], "centre mine reads 0 1 1 1 0 (GDD 8.3)")
	for mine_col in 5:
		var g := _sector(5, 3, [mine_col])
		var res := g.solve()
		ok(res.forced_mines.size() == 1 and res.forced_mines[0] == Vector2i(mine_col, 2),
			"5-wide mine at col %d is forced" % mine_col)


func _test_two_mine_pattern() -> void:
	print("\n[two escape mines]  GDD 19")
	var g := _sector(5, 3, [0, 4])
	eq(_clue_row(g), [1, 1, 0, 1, 1], "mines at 0 and 4 read 1 1 0 1 1")
	var res := g.solve()
	eq(res.solution_count, 1, "exactly one consistent assignment")
	eq(res.forced_mines.size(), 2, "both escapes are forced, neither is a guess")
	eq(g.validate(Vector2i(2, 0), 12).size(), 0, "sector validates clean")


func _test_ambiguous_is_rejected() -> void:
	print("\n[50/50 boards are rejected]  GDD 8.4 [LOCK]")
	# Two mines placed so that {0,3} and {1,4} both satisfy every clue.
	var g := _sector(5, 3, [0, 3])
	eq(_clue_row(g), [1, 1, 1, 1, 1], "mines at 0 and 3 read 1 1 1 1 1")
	var res := g.solve()
	ok(res.solution_count > 1, "solver finds more than one assignment")
	ok(res.ambiguous.size() > 0, "cells are reported ambiguous")
	ok(g.validate(Vector2i(2, 0), 12).size() > 0, "validate() refuses the board")

	# An escape no clue touches can never be deduced.
	var g2 := _pattern(["#*#", "###", "...", "..."])
	ok(g2.validate(Vector2i(1, 0), 12).size() > 0, "an escape with no live clue is refused")


func _test_destroyed_clues() -> void:
	print("\n[destroyed clues]  GDD 19 \"부분 단서 파손\"")
	# A column has crushed the middle clue. The clues that survive still force
	# the answer, so the board is legal.
	var ok_board := _pattern(["??*??", "..#..", ".....", "....."])
	eq(ok_board.validate(Vector2i(2, 0), 12).size(), 0,
		"a crushed clue is legal when the survivors still force the escape")
	ok(ok_board.solve().solution_count == 1, "and the board still has exactly one solution")

	# Crush the wrong clue on a 3-wide board and it collapses into a coin flip.
	var bad := _pattern(["*??", "..#", "..."])
	ok(bad.validate(Vector2i(1, 0), 12).size() > 0,
		"crushing a load-bearing clue is refused as a guess")


func _test_two_band_boards() -> void:
	print("\n[two covered bands]  GDD 18 - depth comes from combining clues")
	var one := _pattern(["??*??", ".....", "....."])
	eq(one.deduction_depth(), 1, "one band: a single clue row hands it to you")

	# The near band has to be proved empty from the lower clue row before the
	# upper clue row means anything.
	var two := _pattern(["??*??", ".....", "?????", ".....", "....."])
	eq(two.validate(Vector2i(2, 0), 12).size(), 0, "two-band board validates")
	eq(two.deduction_depth(), 2, "two bands: two levels of inference")

	# Charges cluster, so clue numbers finally leave the 0/1 range.
	var pair := _pattern(["?**??", ".....", "....."])
	eq(_clue_row_of(pair, 1), [1, 2, 2, 1, 0], "two adjacent charges read 1 2 2 1 0")
	eq(pair.validate(Vector2i(2, 0), 12).size(), 0, "twin-charge board validates")

	var bank := _pattern(["?***?", ".....", "....."])
	eq(_clue_row_of(bank, 1), [1, 2, 3, 2, 1], "three adjacent charges read 1 2 3 2 1")
	eq(bank.validate(Vector2i(2, 0), 12).size(), 0, "charge-bank board validates")


func _test_pattern_authoring() -> void:
	print("\n[ASCII board authoring]  GDD 25.1 / 27")
	# pattern[0] is the FAR row, so the array reads the way the screen looks.
	var g := _pattern(["*#?", ".~.", "...", "..."])
	eq(g.width, 3, "width comes from the row strings")
	eq(g.length, 4, "length comes from the row count")
	eq(g.state_at(Vector2i(0, 3)), MineGrid.Cell.COVERED, "'*' is a covered slab")
	ok(g.is_mine(Vector2i(0, 3)), "'*' hides a charge, on the far row")
	eq(g.state_at(Vector2i(1, 3)), MineGrid.Cell.OBSTACLE, "'#' is not walkable")
	eq(g.state_at(Vector2i(2, 3)), MineGrid.Cell.COVERED, "'?' is a covered slab")
	eq(g.state_at(Vector2i(1, 2)), MineGrid.Cell.REVEALED, "'~' is a walkable sand slab")

	var holes := _pattern(["?*?", "._.", "..."])
	eq(holes.state_at(Vector2i(1, 1)), MineGrid.Cell.HOLE, "'_' is a hole")
	ok(not holes.is_walkable(Vector2i(1, 1)), "and it is not walkable")

	var s := SectorData.new()
	s.pattern = PackedStringArray(["??*", "..", "..."])
	s.build_grid()
	ok(s.structural_errors().size() > 0, "a ragged board is refused")


func _test_movement_rules() -> void:
	print("\n[left / forward / right only, no diagonals, no back]  GDD 7.1 [LOCK]")
	eq(MineGrid.CORE_MOVES.size(), 3, "exactly three legal moves")
	ok(not MineGrid.CORE_MOVES.has(Vector2i(0, -1)), "back is not a core move")
	for m in MineGrid.CORE_MOVES:
		ok(m.x == 0 or m.y == 0, "%s is not diagonal" % m)

	var g := _sector(3, 4, [2])
	eq(g.dashes_to(Vector2i(0, 0), Vector2i(2, 3)), 5, "3 forward + 2 right = 5 dashes")
	eq(g.dashes_to(Vector2i(2, 3), Vector2i(0, 0)), -1, "you cannot get back to the start")


func _test_obstacle_routing() -> void:
	print("\n[obstacles change the route, not the maths]  GDD 9.2")
	var g := _sector(3, 6, [0])
	eq(g.min_dashes_to_mine(Vector2i(0, 0)), 5, "clear deck: 5 straight forward dashes")

	# A fallen column in the direct lane costs a detour out and back.
	for r in [1, 2, 3]:
		g.set_state(Vector2i(0, r), MineGrid.Cell.OBSTACLE)
	eq(g.min_dashes_to_mine(Vector2i(0, 0)), 7, "detour out and back costs 2 extra dashes")
	eq(_clue_row(g), [1, 1, 0], "the clue row still reads the same - obstacles are not maths")

	# The candidate row is normally a continuous walkable band, which is what
	# guarantees an escape always exists. Cut that band too and it is gone.
	g.set_state(Vector2i(0, 4), MineGrid.Cell.OBSTACLE)
	g.set_state(Vector2i(1, 5), MineGrid.Cell.HOLE)
	eq(g.min_dashes_to_mine(Vector2i(0, 0)), -1, "isolating the mine makes it unreachable")
	ok(g.validate(Vector2i(0, 0), 12).size() > 0, "and validate() catches that")


func _test_tempo_map() -> void:
	print("\n[tempo map]  GDD 26 [LOCK]")
	var tm := TempoMap.new([{"beat": 0, "bpm": 120}, {"beat": 8, "bpm": 60}])
	eq(tm.time_at_beat(0.0), 0.0, "beat 0 is time 0")
	eq(tm.time_at_beat(8.0), 4.0, "8 beats at 120 bpm = 4 s")
	eq(tm.time_at_beat(10.0), 6.0, "2 more beats at 60 bpm = 2 s")
	ok(absf(tm.beat_at_time(6.0) - 10.0) < 1e-9, "beat_at_time inverts time_at_beat")
	ok(absf(tm.beat_at_time(2.0) - 4.0) < 1e-9, "inverse holds inside the first segment")

	var real := TempoMap.from_json_file("res://assets/data/stage1_tempo.json")
	eq(real.bpm_at_beat(0.0), 112.0, "stage 1 opens at 112 bpm")
	eq(real.bpm_at_beat(380.0), 152.0, "stage 1 finishes at 152 bpm")


func _test_launch_curve() -> void:
	print("\n[mine launch trajectory]  GDD 6.3 / 11.1 [LOCK]")
	var tm := TempoMap.from_json_file("res://assets/data/stage1_tempo.json")
	var lc := LaunchController.new()
	lc.setup(tm)
	lc.begin_launch(36.0, Vector3(0, 0, 0), Vector3(0, 0, -24), LaunchController.Grade.PERFECT)

	var t0 := lc.sample(36.0)
	var apex := lc.sample(36.0 + Tuning.APEX_BEAT_OFFSET)
	var land := lc.sample(36.0 + Tuning.AIR_BEATS)
	ok(absf(t0.y) < 1e-6, "launch starts on the deck")
	ok(absf(land.y) < 1e-6, "landing ends on the deck")
	ok(apex.y > 5.0, "apex is genuinely high")
	ok(absf(land.z + 24.0) < 1e-6, "lands exactly on the target tile centre")

	var before := lc.sample(36.0 + Tuning.APEX_BEAT_OFFSET - 0.15).y
	var after := lc.sample(36.0 + Tuning.APEX_BEAT_OFFSET + 0.15).y
	ok(apex.y > before and apex.y > after, "apex sits on air beat 2, not before or after")

	# GDD 30: no linear / constant-speed fall. Gravity must be visible.
	var b := 36.0 + Tuning.APEX_BEAT_OFFSET
	var d1 := lc.sample(b + 0.6).y - lc.sample(b + 0.9).y
	var d2 := lc.sample(b + 1.6).y - lc.sample(b + 1.9).y
	ok(d2 > d1 * 1.5, "the fall accelerates (%.2f -> %.2f per 0.3 beat)" % [d1, d2])

	# GDD 11.2 [LOCK]: grade must not touch distance or airtime.
	var lc2 := LaunchController.new()
	lc2.setup(tm)
	lc2.begin_launch(36.0, Vector3(0, 0, 0), Vector3(0, 0, -24), LaunchController.Grade.BAD)
	var same := true
	for k in 17:
		var bt := 36.0 + float(k) * 0.25
		if lc.sample(bt).distance_to(lc2.sample(bt)) > 1e-9:
			same = false
	ok(same, "PERFECT and BAD produce an identical trajectory")


func _test_stage_chain() -> void:
	print("\n[stage 1 authored chain]  GDD 27.1")
	var tm := TempoMap.from_json_file("res://assets/data/stage1_tempo.json")
	var st := Stage1Data.build(tm)
	for line in st.report:
		print("      " + line)
	for e in st.errors:
		printerr("      ! " + e)
	eq(st.errors.size(), 0, "every authored sector validates")
	eq(st.sectors.size(), 44, "44 sectors authored")

	# GDD 18: the ramp has to actually be there, and it has to be a ramp in how
	# many clues you combine - not in what a number means.
	var deep := 0
	var big_clue := 0
	var past_learn := 0
	var past_learn_rich := 0
	for i in st.sectors.size():
		var g: MineGrid = st.grids[i]
		if g.deduction_depth() != 1:
			deep += 1
		var top := 0
		for r in g.length:
			for c in g.width:
				if g.state_at(Vector2i(c, r)) == MineGrid.Cell.REVEALED:
					top = maxi(top, g.number_at(Vector2i(c, r)))
		big_clue = maxi(big_clue, top)
		if st.sectors[i].act != "Learn":
			past_learn += 1
			if top >= 2:
				past_learn_rich += 1
	ok(deep >= 20, "%d sectors need more than one level of inference" % deep)
	eq(big_clue, 3, "clue numbers reach 3, so 0/1 pattern matching is not enough")
	ok(past_learn_rich * 2 >= past_learn,
		"%d of %d post-tutorial sectors carry a clue of 2 or more" % [past_learn_rich, past_learn])
	for i in 3:
		ok((st.grids[i] as MineGrid).deduction_depth() <= 2,
			"the first sectors stay shallow (GDD 12.4)")

	var last_beat := Tuning.sector_ground_beat(st.sectors.size() - 1) + Tuning.CYCLE_BEATS
	var total := tm.time_at_beat(last_beat)
	ok(total > 150.0 and total < 240.0,
		"stage runs %.0f s, inside the 2:30-4:00 window (GDD 20)" % total)
	print("      stage length: %.1f s, bridge span: %.0f m" % [total, absf(st.gate_z)])
