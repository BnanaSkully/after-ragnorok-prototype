extends SceneTree
const H := preload("res://tests/helpers.gd")
func _initialize() -> void:
	await process_frame
	var bad := {}
	var rerolled := 0; var drives := 0
	var n_games: int = H.games(200)
	for g in n_games:
		var m = load("res://main.tscn").instantiate()
		root.add_child(m)
		var s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
		s.start_landing()
		if s.skoll.rifts.size() != 0: bad["rifts during landing"] = 1
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		if g == 0: print("valid landing hexes now that rifts don't block: %d" % spots.size())
		s.end_turn()
		if s.has_pending_offer(): s.pending_relation().answer(false)
		if s.turn != 2 or s.skoll.rifts.size() != 4: bad["not 1 rift per city (4) on turn 2"] = bad.get("not 1 rift per city (4) on turn 2", 0) + 1
		for r in s.skoll.rifts:
			for f in s.factions:
				if HexMap.hex_distance(r, f.city_pos) < Skoll.RIFT_MIN_CITY_DISTANCE: bad["rift near a city"] = bad.get("rift near a city", 0) + 1
		if s.skoll.revealed_rift != HexMap.NO_CELL: bad["revealed before 14"] = 1
		var turn2 = s.skoll.rifts.duplicate()
		while s.turn < 14 and not s.game_over:
			H.answer_choices(s)
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(false)
		if s.game_over: m.queue_free(); continue
		if s.skoll.rifts != turn2: bad["rifts changed before arrival"] = 1
		if s.skoll.revealed_rift != s.skoll.pos or not s.skoll.pos in s.skoll.rifts: bad["arrival not at a revealed rift"] = bad.get("arrival not at a revealed rift", 0) + 1
		var before = s.skoll.rifts.duplicate()
		s.skoll.drive_back()
		drives += 1
		if s.skoll.rifts != before: rerolled += 1
		if s.skoll.revealed_rift != s.skoll.pos: bad["return not at revealed rift"] = 1
		m.queue_free()
	print("200 games: problems %s; after being driven back the rifts changed in %d/%d cases" % [bad if bad.size() > 0 else "none", rerolled, drives])
	quit()
