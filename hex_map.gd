class_name HexMap

# Hex map maths: where hexes are on screen, how far apart they are, and which
# hexes touch. Pointy-top hexes in offset rows (every odd row is shifted right).
# Everything here is "static", so other scripts call it as HexMap.hex_distance(a, b)
# without needing a HexMap object.

const HEX_SIZE := 32.0
const COLS := 12
const ROWS := 10
const OFFSET := Vector2(60, 115) # where the top-left hex sits on screen
const NO_CELL := Vector2i(-1, -1) # means "no hex", e.g. a unit that isn't on the map

static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS

# The screen position of a hex's centre.
static func hex_center(cell: Vector2i) -> Vector2:
	var w := sqrt(3.0) * HEX_SIZE
	var h := 1.5 * HEX_SIZE
	return Vector2(w * (cell.x + 0.5 * (cell.y % 2)), h * cell.y) + OFFSET

# The six corners of a hex, for drawing it.
static func hex_points(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(cos(a), sin(a)) * HEX_SIZE)
	return pts

# How many steps apart two hexes are. Converts our offset rows into
# "cube" hex coordinates, where distance is easy to work out.
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var aq := a.x - (a.y - (a.y & 1)) / 2
	var bq := b.x - (b.y - (b.y & 1)) / 2
	var dq := aq - bq
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2

static func is_neighbour(a: Vector2i, b: Vector2i) -> bool:
	return in_bounds(b) and a != b and hex_center(a).distance_to(hex_center(b)) < HEX_SIZE * 1.9

# All hexes touching this one (only ones on the map).
static func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			if is_neighbour(cell, c):
				result.append(c)
	return result

# The hex under a screen position (e.g. the mouse), or NO_CELL if there isn't one.
static func cell_at(pos: Vector2) -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for row in ROWS:
		for col in COLS:
			var c := Vector2i(col, row)
			var d := pos.distance_to(hex_center(c))
			if d < best_d:
				best_d = d
				best = c
	return best if best_d <= HEX_SIZE else NO_CELL
