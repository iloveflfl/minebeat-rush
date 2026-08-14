class_name SectorData
extends Resource

## One authored bridge sector. GDD 27: this is the level-design payload.
## GDD 25.1: a designer can tune these without touching game code.
##
## Row layout is fixed and deliberate (GDD 8.2 / 8.3):
##   row 0             landing deck            REVEALED
##   rows 1..L-3       approach deck           REVEALED (obstacles / holes / sand live here)
##   row L-2           CLUE ROW                REVEALED, shows the adjacency numbers
##   row L-1           CANDIDATE ROW           COVERED, hides the escape mine(s)
##
## Keeping every covered slab inside one candidate row is what makes the
## "shown clues alone force the mine" guarantee (GDD 8.4) provable rather than
## hopeful.

@export var id: String = ""
@export var act: String = ""

@export_range(3, 5, 2) var width: int = 3
@export_range(3, 12) var length: int = 3

## Lateral intent for the escape mine, as an offset from the landing column.
## Resolved into a real column at build time (mirrored if it would fall off the
## deck), so the authored chain can never produce an illegal sector.
@export var mine_lat: int = 0
## Optional second escape mine (GDD 19: "지뢰 2개" - multiple escape options).
@export var mine_lat_2: int = 9999   # 9999 == unused

@export var obstacles: Array[Vector2i] = []
@export var holes: Array[Vector2i] = []
@export var sand: Array[Vector2i] = []

## Centre-to-centre distance from this sector's candidate row to the next
## sector's landing row. This is the broken span the Mine Launch has to cross.
@export var gap_after: float = 22.0

## GDD 12.4 / 23: the first sectors are timing-judgement exempt.
@export var timing_exempt: bool = false

## GDD 21: which showpiece runs on this sector.
@export var spectacle: String = ""

## Resolved at build time by Stage1Data.build().
var start_col: int = 1
var mine_cols: Array[int] = []
var world_z: float = 0.0

const TILE := 2.0


func clue_row() -> int:
	return length - 2


func candidate_row() -> int:
	return length - 1


## Centre-aligned grid -> world. col increases toward +X (screen right),
## row increases toward -Z (forward). GDD 7.1 [LOCK].
func cell_to_local(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - (width - 1) * 0.5) * TILE, 0.0, -cell.y * TILE)


func cell_to_world(cell: Vector2i) -> Vector3:
	var p := cell_to_local(cell)
	return Vector3(p.x, 0.0, world_z + p.z)


## World X of a column, independent of any sector. Used to carry the landing
## column across a 3 <-> 5 width change without any air steering.
static func col_to_x(col: int, w: int) -> float:
	return (col - (w - 1) * 0.5) * TILE


static func x_to_col(x: float, w: int) -> int:
	return clampi(int(round(x / TILE + (w - 1) * 0.5)), 0, w - 1)


func resolve_mine_cols(from_col: int) -> Array[int]:
	var out: Array[int] = []
	out.append(_resolve_lat(from_col, mine_lat))
	if mine_lat_2 != 9999:
		var second := _resolve_lat(from_col, mine_lat_2)
		if second != out[0]:
			out.append(second)
	return out


func _resolve_lat(from_col: int, lat: int) -> int:
	var c := from_col + lat
	if c < 0 or c >= width:
		c = from_col - lat
	return clampi(c, 0, width - 1)


## Build the pure-data grid this sector describes. All numbers come out of
## MineGrid.number_at(), never from authored values, so a clue can never lie.
func build_grid() -> MineGrid:
	var g := MineGrid.new(width, length)
	for c in width:
		g.set_state(Vector2i(c, candidate_row()), MineGrid.Cell.COVERED)
	for mc in mine_cols:
		g.set_mine(Vector2i(mc, candidate_row()), true)
	for o in obstacles:
		g.set_state(o, MineGrid.Cell.OBSTACLE)
	for h in holes:
		g.set_state(h, MineGrid.Cell.HOLE)
	return g


## Structural rules that are cheaper to check here than to debug in-engine.
func structural_errors() -> PackedStringArray:
	var e := PackedStringArray()
	if width != 3 and width != 5:
		e.append("%s: width must be 3 or 5 (GDD 8.3)" % id)
	if length < 3:
		e.append("%s: length must be >= 3 (landing + clue + candidate rows)" % id)
	for group_name in ["obstacles", "holes", "sand"]:
		for cell in get(group_name) as Array[Vector2i]:
			if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= length:
				e.append("%s: %s %s is outside the deck" % [id, group_name, cell])
			elif cell.y >= clue_row():
				e.append("%s: %s %s sits on the clue/candidate row" % [id, group_name, cell])
			elif cell.y == 0 and group_name != "sand":
				e.append("%s: %s %s blocks the landing row" % [id, group_name, cell])
	if gap_after <= 0.0:
		e.append("%s: gap_after must be positive" % id)
	return e
