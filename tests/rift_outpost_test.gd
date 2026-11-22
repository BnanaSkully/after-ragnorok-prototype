extends SceneTree
const H := preload("res://tests/helpers.gd")

# Rifts and outposts never share a hex (Nathan: "outpost?????" at an outpost on a rift).
# 1. You can't found an outpost on a rift you know of. 2. Founding one on a hidden rift
# moves the rift. 3. Over many games (the player founds outposts wherever it can), no
# outpost ever stands on a rift at the end of a turn.

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func _initialize() -> void:
	await process_frame
	seed(21)
	var ok := true
	var m = new_game(); var s = m.state
	s.skoll.place_rifts()
	var rift: Vector2i = s.skoll.rifts[0]
	s.player.industry = 50
	s.reveal_area(s.player, rift, 1)
	s.player.known_rifts[rift] = true
	var known_blocked: bool = not s.can_place_outpost(s.player, rift)
	print("1. outpost on a rift you know of allowed=%s (expect false)" % (not known_blocked))
	ok = ok and known_blocked
	s.player.known_rifts.erase(rift)
	# put a hidden rift on a hex where the player may found an outpost
	var spot: Vector2i = s.outpost_spots(s.player)[0]
	var owner_name: String = s.skoll.rift_city[rift]
	s.skoll.rift_city.erase(rift)
	s.skoll.rifts[0] = spot
	s.skoll.rift_city[spot] = owner_name
	var before: int = s.skoll.rifts.size()
	var placed: bool = s.build_outpost(s.player, spot)
	var moved: bool = placed and not (spot in s.skoll.rifts) and s.skoll.rifts.size() == before and s.skoll.rift_city.get(s.skoll.rifts[0], "") == owner_name
	print("2. outpost founded on a hidden rift: founded=%s, rift moved for the same city=%s, rifts still %d (expect true, true, %d)" % [placed, moved, s.skoll.rifts.size(), before])
	ok = ok and moved
	m.queue_free()
	var games := int(OS.get_environment("GAMES")) if OS.get_environment("GAMES") != "" else 100
	var shared := 0
	var founded := 0
	var on_hidden := 0
	for g in games:
		m = new_game(); s = m.state
		while not s.game_over and s.turn <= 40:
			H.answer_choices(s)
			for c in s.outpost_spots(s.player):
				if s.player.industry >= s.OUTPOST_COST:
					if c in s.skoll.rifts: on_hidden += 1
					if s.build_outpost(s.player, c): founded += 1
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(false)
			for f in s.factions:
				for o in f.outposts:
					if o in s.skoll.rifts: shared += 1
		m.queue_free()
	print("3. %d games: outposts you founded %d (%d on a hidden rift, which moved), turns ending with an outpost on a rift: %d (expect 0)" % [games, founded, on_hidden, shared])
	ok = ok and shared == 0
	print("ALL OK" if ok else "FAILED")
	quit()
