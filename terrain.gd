class_name Terrain

# The land each hex is made of (standard 4X), as the RULES see it: how much it
# costs to enter, how much it helps a defender, what an outpost on it yields,
# and whether it can be crossed at all. How it looks is up to the view (main.gd).
# GameState.terrain holds one Type per hex; generate() makes a new map each game.

enum Type { PLAINS, FOREST, HILLS, MOUNTAINS, WATER }

const NAMES := ["Plains", "Forest", "Hills", "Mountains", "Water"]
const MOVE_COST := [1, 2, 2, 0, 0] # moves to enter (0 = impassable)
const DEFENCE := [0, 1, 2, 0, 0] # added to a unit (or city) defending on it
const OUTPOST_FOOD := [2, 1, 0, 0, 0] # what an outpost here makes each turn
const OUTPOST_INDUSTRY := [0, 1, 2, 0, 0]
# How common each type is before clumping (out of 100).
const WEIGHTS := [50, 22, 14, 7, 7]
const CLUMP_PASSES := 2 # each pass, every hex may copy a neighbour: makes forests, ranges, lakes

static func passable(t: int) -> bool:
	return MOVE_COST[t] > 0

# A random map: weighted types, clumped together. The hexes in "keep_open"
# (AI cities) are plains and their neighbours passable; every passable hex can
# be reached from every other (tries again until it is).
static func generate(keep_open: Array) -> Dictionary:
	for attempt in 50:
		var map := {}
		for row in HexMap.ROWS:
			for col in HexMap.COLS:
				map[Vector2i(col, row)] = pick_weighted()
		for p in CLUMP_PASSES:
			var copy := map.duplicate()
			for c in map:
				if randf() < 0.5:
					copy[c] = map[HexMap.neighbours(c).pick_random()]
			map = copy
		for city in keep_open:
			map[city] = Type.PLAINS
			for n in HexMap.neighbours(city):
				if not passable(map[n]):
					map[n] = Type.PLAINS
		if all_connected(map):
			return map
	var plain := {} # (practically never happens) give up: all plains
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			plain[Vector2i(col, row)] = Type.PLAINS
	return plain

static func pick_weighted() -> int:
	var roll := randi() % 100
	for t in WEIGHTS.size():
		if roll < WEIGHTS[t]:
			return t
		roll -= WEIGHTS[t]
	return Type.PLAINS

# True if every passable hex can be reached from every other.
static func all_connected(map: Dictionary) -> bool:
	var start := HexMap.NO_CELL
	var total := 0
	for c in map:
		if passable(map[c]):
			total += 1
			start = c
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for n in HexMap.neighbours(c):
			if not seen.has(n) and passable(map[n]):
				seen[n] = true
				queue.append(n)
	return seen.size() == total
