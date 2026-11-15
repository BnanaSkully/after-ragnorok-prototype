# Shared bits for the test scripts (use: const H := preload("res://tests/helpers.gd")).

# Answers every waiting ruin/event pop-up with an affordable option
# (random, or always the first one).
static func answer_choices(s, random := true) -> int:
	var answered := 0
	while s.has_pending_choice():
		var opts: Array = s.pending_choices[0]["options"]
		var ok := []
		for i in opts.size():
			if s.can_afford(opts[i]["effects"]):
				ok.append(i)
		s.answer_choice(ok.pick_random() if random else ok[0])
		answered += 1
	return answered

# Every hex the player could land on.
static func landing_spots(s) -> Array:
	var spots := []
	for r in HexMap.ROWS:
		for c in HexMap.COLS:
			if s.can_land_at(Vector2i(c, r)):
				spots.append(Vector2i(c, r))
	return spots

# Makes the whole map plains: for tests that place units on fixed hexes and
# check one rule exactly (random terrain would block or change them).
static func flatten(s) -> void:
	for c in s.terrain:
		s.terrain[c] = Terrain.Type.PLAINS

# How many games a simulation plays: the number asked for, or fewer when the
# GAMES environment variable is set (quick runs while building, e.g. GAMES=50).
# Averages divide by this number; totals printed in quick mode are smaller.
static func games(full: int) -> int:
	var quick := OS.get_environment("GAMES")
	if quick != "" and int(quick) < full:
		print("(quick mode: %d games instead of %d)" % [int(quick), full])
		return int(quick)
	return full
