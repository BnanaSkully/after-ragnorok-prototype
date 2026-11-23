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
		if s.rifts.cells.size() != 0: bad["rifts during landing"] = 1
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		if g == 0: print("valid landing hexes now that rifts don't block: %d" % spots.size())
		s.end_turn()
		if s.has_pending_offer(): s.pending_relation().answer(false)
		if s.turn != 2 or s.rifts.cells.size() != 4: bad["not 1 rift per city (4) on turn 2"] = bad.get("not 1 rift per city (4) on turn 2", 0) + 1
		for r in s.rifts.cells:
			for f in s.factions:
				if HexMap.hex_distance(r, f.city_pos) < Rifts.MIN_CITY_DISTANCE: bad["rift near a city"] = bad.get("rift near a city", 0) + 1
		if s.rifts.revealed != HexMap.NO_CELL: bad["revealed before 14"] = 1
		var turn2 = s.rifts.cells.duplicate()
		while s.turn < 14 and not s.game_over:
			H.answer_choices(s)
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(false)
		if s.game_over: m.queue_free(); continue
		if s.rifts.cells != turn2: bad["rifts changed before arrival"] = 1
		if not came_out_of(s, s.rifts.revealed): bad["arrival not at a revealed rift"] = bad.get("arrival not at a revealed rift", 0) + 1
		var before = s.rifts.cells.duplicate()
		s.skoll.drive_back()
		drives += 1
		if s.rifts.cells != before: rerolled += 1
		if s.skoll.active or s.skoll.away_until != s.turn + Skoll.RETURN_TURNS: bad["not away for RETURN_TURNS after being driven back"] = 1
		while s.turn < s.skoll.away_until and not s.game_over:
			H.answer_choices(s)
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(false)
		if not s.game_over and not s.skoll.slain and s.skoll.active and not came_out_of(s, s.rifts.revealed): bad["return not at revealed rift"] = bad.get("return not at revealed rift", 0) + 1
		m.queue_free()
	print("%d games: problems %s; after being driven back the rifts changed in %d/%d cases (expect 0: permanent)" % [n_games, bad if bad.size() > 0 else "none", rerolled, drives])
	guarded_rift()
	quit()

# He came out of this rift: on it, or (a unit stood on it) right next to it.
func came_out_of(s, rift) -> bool:
	if not s.skoll.active or not rift in s.rifts.cells:
		return false
	return s.skoll.pos == rift or HexMap.is_neighbour(s.skoll.pos, rift)

# A unit parked on the only rift: he still comes through it, comes out next
# to it and attacks that unit.
func guarded_rift() -> void:
	seed(7)
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	while s.turn < Rifts.RIFT_TURN:
		H.answer_choices(s); s.end_turn()
		if s.has_pending_offer(): s.pending_relation().answer(false)
	var rift: Vector2i = s.rifts.cells[0]
	var owner_name: String = s.rifts.city[rift]
	s.rifts.cells.assign([rift]) # only this rift
	var u = s.player.add_unit(rift)
	var hp0: int = u.hp
	s.skoll.arrive()
	print("guarded rift: revealed=%s (expect true), came out beside it=%s (expect true), hunts %s (expect %s), the unit was attacked=%s (expect true)" % [
		s.rifts.revealed == rift, HexMap.is_neighbour(s.skoll.pos, rift) or s.skoll.pos == rift,
		s.skoll.target.name if s.skoll.target else "nobody", owner_name, u.hp < hp0 or not u in s.player.units])
	m.queue_free()
