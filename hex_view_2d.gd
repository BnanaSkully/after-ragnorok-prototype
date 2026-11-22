class_name HexView2D

# Where hexes appear on the 2D screen. Only drawing and mouse code use this;
# the game rules never do (they use hex coordinates from hex_map.gd). A future
# 3D view would replace this file with its own positions.

const HEX_SIZE := 32.0 # pixels from a hex's centre to a corner (the map fills the screen between the HUD edges)
const OFFSET := Vector2(148, 84) # where the top-left hex sits on screen (clear of the icon column and the goal line)

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

# The hex under a screen position (e.g. the mouse), or NO_CELL if there isn't one.
static func cell_at(pos: Vector2) -> Vector2i:
	var best := HexMap.NO_CELL
	var best_d := INF
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			var d := pos.distance_to(hex_center(c))
			if d < best_d:
				best_d = d
				best = c
	return best if best_d <= HEX_SIZE else HexMap.NO_CELL
