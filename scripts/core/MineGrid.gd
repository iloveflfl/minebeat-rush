class_name MineGrid
extends RefCounted

## Pure Minesweeper data for one bridge sector. GDD 25.1: no graphics, no scene
## tree, unit-testable on its own. GDD 8 [LOCK]: a number always means "count of
## adjacent mines", 8-neighbourhood, for the whole game.
##
## Coordinates are Vector2i(col, row).
##   col 0..width-1   increases toward SCREEN RIGHT (world +X)
##   row 0..length-1  increases FORWARD, away from the player's start (world -Z)

enum Cell {
	REVEALED,  ## flat opened slab, walkable, shows its number (0 renders blank)
	COVERED,   ## raised unopened slab, walkable, hides whatever is under it
	OBSTACLE,  ## fallen column / statue debris - not walkable, big silhouette
	HOLE,      ## deck is physically missing - not walkable
}

var width: int = 3
var length: int = 3

var _state: PackedInt32Array = PackedInt32Array()
var _mine: PackedByteArray = PackedByteArray()

const NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## GDD 7.1 [LOCK]: three directions only, no diagonals, no back.
const MOVE_LEFT := Vector2i(-1, 0)
const MOVE_RIGHT := Vector2i(1, 0)
const MOVE_FORWARD := Vector2i(0, 1)
const MOVE_BACK := Vector2i(0, -1)
const CORE_MOVES: Array[Vector2i] = [MOVE_LEFT, MOVE_FORWARD, MOVE_RIGHT]


func _init(w: int = 3, l: int = 3) -> void:
	resize(w, l)


func resize(w: int, l: int) -> void:
	width = w
	length = l
	_state.resize(w * l)
	_mine.resize(w * l)
	_state.fill(Cell.REVEALED)
	_mine.fill(0)


# ---------------------------------------------------------------------------
# basic access
# ---------------------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < width and c.y >= 0 and c.y < length


func _idx(c: Vector2i) -> int:
	return c.y * width + c.x


func state_at(c: Vector2i) -> Cell:
	if not in_bounds(c):
		return Cell.HOLE
	return _state[_idx(c)] as Cell


func set_state(c: Vector2i, s: Cell) -> void:
	if in_bounds(c):
		_state[_idx(c)] = s


func is_mine(c: Vector2i) -> bool:
	return in_bounds(c) and _mine[_idx(c)] != 0


func set_mine(c: Vector2i, v: bool = true) -> void:
	if in_bounds(c):
		_mine[_idx(c)] = 1 if v else 0


func mine_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in length:
		for c in width:
			var cell := Vector2i(c, r)
			if is_mine(cell):
				out.append(cell)
	return out


func covered_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in length:
		for c in width:
			var cell := Vector2i(c, r)
			if state_at(cell) == Cell.COVERED:
				out.append(cell)
	return out


## GDD 8 [LOCK] - the one and only maths rule of this game.
func number_at(c: Vector2i) -> int:
	var n := 0
	for d in NEIGHBORS_8:
		if is_mine(c + d):
			n += 1
	return n


## Walkable = the player may dash onto it. Covered slabs ARE walkable; that is
## the whole point of the game (GDD 1). Obstacles and holes are not.
func is_walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var s := state_at(c)
	return s == Cell.REVEALED or s == Cell.COVERED


# ---------------------------------------------------------------------------
# reachability - GDD 27.1
# ---------------------------------------------------------------------------

## BFS over the three legal moves. Returns cell -> minimum dash count.
func dash_distances(start: Vector2i, moves: Array[Vector2i] = CORE_MOVES) -> Dictionary:
	var dist: Dictionary = {}
	if not is_walkable(start):
		return dist
	dist[start] = 0
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = dist[cur]
		for m in moves:
			var nxt: Vector2i = cur + m
			if not is_walkable(nxt) or dist.has(nxt):
				continue
			dist[nxt] = d + 1
			queue.append(nxt)
	return dist


func dashes_to(start: Vector2i, target: Vector2i) -> int:
	var d := dash_distances(start)
	return int(d.get(target, -1))


# ---------------------------------------------------------------------------
# solver - GDD 8.4 / 27.1: the shown clues alone must force the target mine
# ---------------------------------------------------------------------------

const MAX_UNKNOWNS := 22
const MAX_SOLUTIONS := 20000


class SolveResult extends RefCounted:
	var solution_count: int = 0
	var forced_mines: Array[Vector2i] = []
	var forced_safe: Array[Vector2i] = []
	var ambiguous: Array[Vector2i] = []
	var unconstrained: Array[Vector2i] = []
	var overflowed: bool = false


## Enumerate every mine assignment over the covered cells that is consistent
## with the revealed numbers, then report which covered cells are the same in
## every solution.
func solve() -> SolveResult:
	var res := SolveResult.new()

	# Unknowns are covered cells touched by at least one revealed clue.
	var unknown_ids: Dictionary = {}   # Vector2i -> bit index
	var unknown_cells: Array[Vector2i] = []
	var constraints: Array = []        # [{mask: int, n: int}]

	for r in length:
		for c in width:
			var cell := Vector2i(c, r)
			if state_at(cell) != Cell.REVEALED:
				continue
			var n := number_at(cell)
			var neigh: Array[Vector2i] = []
			for d in NEIGHBORS_8:
				var nb: Vector2i = cell + d
				if state_at(nb) == Cell.COVERED:
					neigh.append(nb)
			if neigh.is_empty():
				continue
			var mask := 0
			for nb in neigh:
				if not unknown_ids.has(nb):
					unknown_ids[nb] = unknown_cells.size()
					unknown_cells.append(nb)
				mask |= 1 << int(unknown_ids[nb])
			constraints.append({"mask": mask, "n": n})

	for cell in covered_cells():
		if not unknown_ids.has(cell):
			res.unconstrained.append(cell)

	if unknown_cells.is_empty():
		return res
	if unknown_cells.size() > MAX_UNKNOWNS:
		res.overflowed = true
		return res

	var k := unknown_cells.size()
	var all_ones := 0
	var solutions: Array[int] = []
	_enumerate(0, 0, k, constraints, solutions)
	res.solution_count = solutions.size()
	if solutions.size() >= MAX_SOLUTIONS:
		res.overflowed = true

	if solutions.is_empty():
		return res

	var always_mine := -1  # all bits
	var always_safe := -1
	for s in solutions:
		always_mine &= s
		always_safe &= ~s
	all_ones = (1 << k) - 1

	for i in k:
		var bit := 1 << i
		if always_mine & bit:
			res.forced_mines.append(unknown_cells[i])
		elif always_safe & bit:
			res.forced_safe.append(unknown_cells[i])
		else:
			res.ambiguous.append(unknown_cells[i])
	return res


func _enumerate(i: int, assigned: int, k: int, constraints: Array, out: Array[int]) -> void:
	if out.size() >= MAX_SOLUTIONS:
		return
	if i == k:
		for con in constraints:
			if _popcount(assigned & int(con["mask"])) != int(con["n"]):
				return
		out.append(assigned)
		return

	var decided_mask := (1 << i) - 1
	for v in 2:
		var next_assigned := assigned | (v << i)
		if _feasible(next_assigned, decided_mask | (1 << i), constraints):
			_enumerate(i + 1, next_assigned, k, constraints, out)


func _feasible(assigned: int, decided_mask: int, constraints: Array) -> bool:
	for con in constraints:
		var m: int = int(con["mask"])
		var n: int = int(con["n"])
		var placed := _popcount(assigned & m & decided_mask)
		var undecided := _popcount(m & ~decided_mask)
		if placed > n or placed + undecided < n:
			return false
	return true


static func _popcount(v: int) -> int:
	var n := 0
	while v != 0:
		v &= v - 1
		n += 1
	return n


# ---------------------------------------------------------------------------
# validation - GDD 27.1
# ---------------------------------------------------------------------------

## Returns an array of human-readable problems. Empty array == sector is legal.
func validate(start: Vector2i, max_dashes: int) -> PackedStringArray:
	var errors := PackedStringArray()

	# A mine may only ever hide under a covered slab, otherwise the number
	# under it would already be visible and the puzzle would be a lie.
	for cell in mine_cells():
		if state_at(cell) != Cell.COVERED:
			errors.append("mine at %s is not on a COVERED cell" % cell)

	if not is_walkable(start):
		errors.append("start cell %s is not walkable" % start)

	# NOTE: an obstacle standing on a cell that *would* have carried a number is
	# allowed on purpose - that is GDD 19's "부분 단서 파손", a destroyed clue the
	# player has to work around. It is safe to allow because the solver below
	# still has to prove the escape is forced by the clues that remain.

	var res := solve()
	if res.overflowed:
		errors.append("solver overflowed (too many unknowns or solutions)")
	if res.solution_count == 0:
		errors.append("no mine assignment is consistent with the shown clues")

	var mines := mine_cells()
	if mines.is_empty():
		errors.append("sector has no mine - there is no way out")

	# GDD 8.4 [LOCK]: the target mines must be *forced* by the visible clues.
	# 50/50 guessing is banned.
	for m in mines:
		if not res.forced_mines.has(m):
			if res.unconstrained.has(m):
				errors.append("mine at %s is not adjacent to any shown clue" % m)
			else:
				errors.append("mine at %s is not uniquely deducible (50/50)" % m)

	# Anything the clues force to be a mine had better actually be one.
	for f in res.forced_mines:
		if not is_mine(f):
			errors.append("clues force a mine at %s but none is placed there" % f)

	# GDD 27.1: reachable within the ground phase.
	var dist := dash_distances(start)
	var best := -1
	for m in mines:
		var d := int(dist.get(m, -1))
		if d >= 0 and (best < 0 or d < best):
			best = d
	if best < 0:
		errors.append("no mine is reachable from %s with left/forward/right only" % start)
	elif best > max_dashes:
		errors.append("nearest mine needs %d dashes but only %d fit in the ground phase"
				% [best, max_dashes])

	return errors


## GDD 18 [LOCK]: difficulty must come from how many clues you have to combine,
## never from changing what a number means. This measures exactly that.
##
## It runs the three deductions a human actually performs:
##   * this clue is already satisfied, so its remaining neighbours are safe
##   * this clue has exactly as many unknowns left as it still needs, so they
##     are all charges
##   * this clue's cells are a subset of that one's, so the difference carries
##     the difference of the counts
## and reports how many rounds pass before an escape charge is pinned down.
##
##   1    one clue hands it to you
##   2    a 0 and a 1 have to be read together
##   3+   clues from different rows have to be chained through a covered band
##  -1    even subset reasoning stalls; the board needs real case analysis
func deduction_depth() -> int:
	var known: Dictionary = {}   # Vector2i -> bool (true == mine)
	var rounds := 0

	while rounds < 24:
		rounds += 1
		var progress := false
		# Deductions are gathered against a snapshot and applied at the end of
		# the round, so "one round" really means "one level of inference".
		# Applying them immediately would let a lucky iteration order collapse a
		# genuinely chained board into a single pass and under-report it.
		var pending: Dictionary = {}
		var active: Array = []   # [{cells: Array[Vector2i], n: int}]

		for r in length:
			for c in width:
				var clue := Vector2i(c, r)
				if state_at(clue) != Cell.REVEALED:
					continue
				var n := number_at(clue)
				var unknown: Array[Vector2i] = []
				var found := 0
				for d in NEIGHBORS_8:
					var nb: Vector2i = clue + d
					if state_at(nb) != Cell.COVERED:
						continue
					if known.has(nb):
						if known[nb]:
							found += 1
					else:
						unknown.append(nb)
				if unknown.is_empty():
					continue
				active.append({"cells": unknown, "n": n - found})
				if found == n:
					for u in unknown:
						pending[u] = false
					progress = true
				elif n - found == unknown.size():
					for u in unknown:
						pending[u] = true
					progress = true

		# Subset rule: if A's cells sit entirely inside B's, then B minus A holds
		# exactly (n_B - n_A) charges. This is what lets a human crack 1 1 1.
		for a in active:
			for b in active:
				if a == b or (a["cells"] as Array).size() >= (b["cells"] as Array).size():
					continue
				var inside := true
				for cell in a["cells"]:
					if not (b["cells"] as Array).has(cell):
						inside = false
						break
				if not inside:
					continue
				var diff: Array[Vector2i] = []
				for cell in b["cells"]:
					if not (a["cells"] as Array).has(cell):
						diff.append(cell)
				if diff.is_empty():
					continue
				var dn: int = int(b["n"]) - int(a["n"])
				if dn == 0:
					for u in diff:
						pending[u] = false
					progress = true
				elif dn == diff.size():
					for u in diff:
						pending[u] = true
					progress = true

		for cell in pending:
			known[cell] = pending[cell]

		for m in mine_cells():
			if known.get(m, false):
				return rounds
		if not progress:
			return -1
	return -1


func min_dashes_to_mine(start: Vector2i) -> int:
	var dist := dash_distances(start)
	var best := -1
	for m in mine_cells():
		var d := int(dist.get(m, -1))
		if d >= 0 and (best < 0 or d < best):
			best = d
	return best


func debug_string() -> String:
	var lines := PackedStringArray()
	for r in range(length - 1, -1, -1):
		var row := PackedStringArray()
		for c in width:
			var cell := Vector2i(c, r)
			match state_at(cell):
				Cell.OBSTACLE:
					row.append(" # ")
				Cell.HOLE:
					row.append("   ")
				Cell.COVERED:
					row.append("[*]" if is_mine(cell) else "[ ]")
				_:
					var n := number_at(cell)
					row.append(" %d " % n if n > 0 else " . ")
		lines.append("r%02d %s" % [r, "".join(row)])
	return "\n".join(lines)
