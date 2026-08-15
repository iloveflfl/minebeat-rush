class_name SectorData
extends Resource

## One authored bridge sector, written as ASCII so a designer can see the board
## the way the player will (GDD 25.1: tunable without touching game code).
##
## `pattern[0]` is the FAR row - the one the player is running toward - and the
## last string is the landing row, so the array reads top-down exactly like the
## screen. Every clue number is derived by MineGrid from the mines actually
## placed here, never typed in, so a clue can physically not disagree with the
## board (GDD 8 [LOCK]).
##
##   .  opened slab. Shows its adjacency number; blank when that number is 0.
##   ?  unopened slab. Walkable, hides whatever is under it.
##   *  unopened slab hiding an escape charge.
##   #  fallen column / statue debris. Not walkable. Destroys any clue that
##      would have been on this cell - GDD 19 "부분 단서 파손".
##   _  the deck is physically gone here.
##   ~  opened slab buried in sand. Walkable but slower (GDD 9.2 [TEST]).

@export var id: String = ""
@export var act: String = ""

## The board. See the legend above.
@export var pattern: PackedStringArray = PackedStringArray()

## Centre-to-centre distance from this sector's far row to the next sector's
## landing row: the broken span the Mine Launch has to cross.
@export var gap_after: float = 22.0

## GDD 12.4 / 23: the first sectors are timing-judgement exempt.
@export var timing_exempt: bool = false

## GDD 21: which showpiece runs on this sector.
@export var spectacle: String = ""

## Resolved when the stage is built.
var width: int = 3
var length: int = 3
var world_z: float = 0.0
var mine_cells: Array[Vector2i] = []
var sand_cells: Dictionary = {}

const TILE := 2.0


func _row_string(row: int) -> String:
	# pattern[0] is the far row, so the array is indexed back-to-front.
	return pattern[length - 1 - row]


func char_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= length or cell.x < 0 or cell.x >= width:
		return "_"
	return _row_string(cell.y).substr(cell.x, 1)


## Centre-aligned grid -> world. col increases toward +X (screen right),
## row increases toward -Z (forward). GDD 7.1 [LOCK].
func cell_to_local(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - (width - 1) * 0.5) * TILE, 0.0, -cell.y * TILE)


func cell_to_world(cell: Vector2i) -> Vector3:
	var p := cell_to_local(cell)
	return Vector3(p.x, 0.0, world_z + p.z)


## World X of a column, independent of any sector. Used to carry the landing
## column across a 3 <-> 5 width change with no air steering.
static func col_to_x(col: int, w: int) -> float:
	return (col - (w - 1) * 0.5) * TILE


static func x_to_col(x: float, w: int) -> int:
	return clampi(int(round(x / TILE + (w - 1) * 0.5)), 0, w - 1)


func build_grid() -> MineGrid:
	length = pattern.size()
	width = 0 if length == 0 else pattern[0].length()

	var g := MineGrid.new(width, length)
	mine_cells = []
	sand_cells = {}

	for r in length:
		for c in width:
			var cell := Vector2i(c, r)
			match char_at(cell):
				"?":
					g.set_state(cell, MineGrid.Cell.COVERED)
				"*":
					g.set_state(cell, MineGrid.Cell.COVERED)
					g.set_mine(cell, true)
					mine_cells.append(cell)
				"#":
					g.set_state(cell, MineGrid.Cell.OBSTACLE)
				"_":
					g.set_state(cell, MineGrid.Cell.HOLE)
				"~":
					sand_cells[cell] = true
				_:
					pass  # "." stays REVEALED
	return g


## The far row is the one the launch fires from; the camera frames up to here.
func far_row() -> int:
	return length - 1


## Structural rules that are cheaper to check here than to debug in-engine.
func structural_errors() -> PackedStringArray:
	var e := PackedStringArray()
	if pattern.is_empty():
		e.append("%s: pattern is empty" % id)
		return e
	if width != 3 and width != 5:
		e.append("%s: width must be 3 or 5 (GDD 8.3), got %d" % [id, width])
	if length < 3:
		e.append("%s: needs at least 3 rows (landing + clue + candidates)" % id)
	for i in pattern.size():
		if pattern[i].length() != width:
			e.append("%s: pattern row %d is %d wide, expected %d"
					% [id, i, pattern[i].length(), width])
		for ch in pattern[i]:
			if not (ch in ".?*#_~"):
				e.append("%s: unknown pattern character '%s'" % [id, ch])
	# The landing row has to be a solid, walkable strip: the player arrives on
	# whichever column the flight happened to end on (GDD 10.2).
	for c in width:
		var ch := char_at(Vector2i(c, 0))
		if ch == "#" or ch == "_":
			e.append("%s: landing column %d is blocked" % [id, c])
	if mine_cells.is_empty():
		e.append("%s: no escape charge - there is no way out" % id)
	if gap_after <= 0.0:
		e.append("%s: gap_after must be positive" % id)
	return e


func ascii_preview() -> String:
	return " / ".join(pattern)
