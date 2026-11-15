extends SceneTree
const H := preload("res://tests/helpers.gd")
func _initialize() -> void:
	await process_frame
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	s.turn = 15
	var sk = s.skoll
	sk.active = true; sk.target = s.ais[0]
	for dist in [4, 3, 2]:
		s.daughter.go_rogue(Vector2i(7, 9)); sk.pos = Vector2i(7 - dist, 9)
		var before = sk.pos
		s.messages.clear()
		sk.take_turn()
		var hunted = s.messages.any(func(x): return "spotted" in x or "caught" in x)
		print("she is %d hexes away: he can see her=%s, hunted her=%s (moved %s -> %s)" % [dist, sk.can_see(Vector2i(7, 9)) or s.daughter.is_swallowed(), hunted, before, sk.pos])
	# full chase from 2 hexes
	s.daughter.state = SunDaughter.State.SHELTERED
	s.daughter.go_rogue(Vector2i(7, 9)); sk.pos = Vector2i(5, 9); sk.strength = Skoll.STRENGTH
	var turns := 0
	while s.daughter.is_rogue() and turns < 6:
		turns += 1
		sk.take_turn()
		if s.daughter.is_rogue(): s.daughter_flee()
	print("spotted at 2 hexes: swallowed=%s after %d turns" % [s.daughter.is_swallowed(), turns])
	quit()
