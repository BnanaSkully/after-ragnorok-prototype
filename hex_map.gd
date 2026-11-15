class_name HexMap

# The hex grid as the RULES see it: map size, which hexes exist, how far apart
# two hexes are, and which hexes touch. No pixels or screen positions here, so
# the rules work the same however the map is drawn (2D now, maybe 3D later).
# Pointy-top hexes in offset rows (every odd row is shifted right by half a hex).
# Everything here is "static": other scripts call HexMap.hex_distance(a, b).
# Where hexes appear on screen is in hex_view_2d.gd.

const COLS := 12
const ROWS := 10
const NO_CELL := Vector2i(-1, -1) # means "no hex", e.g. a unit that isn't on the map

static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS

# How many steps apart two hexes are. Converts our offset rows into
# "cube" hex coordinates, where distance is easy to work out.
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var aq := a.x - (a.y - (a.y & 1)) / 2
	var bq := b.x - (b.y - (b.y & 1)) / 2
	var dq := aq - bq
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2

# Two different hexes on the map that share an edge.
static func is_neighbour(a: Vector2i, b: Vector2i) -> bool:
	return in_bounds(a) and in_bounds(b) and a != b and hex_distance(a, b) == 1

# All hexes touching this one (only ones on the map).
static func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			if is_neighbour(cell, c):
				result.append(c)
	return result
