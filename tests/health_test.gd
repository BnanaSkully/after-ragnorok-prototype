extends SceneTree
const H := preload("res://tests/helpers.gd")

# Unit health. Part 1: the combat maths over many fights, wounded units
# fighting weaker, healing at rest and at home. Part 2: full games (HP always
# in range, endings).

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func _initialize() -> void:
	await process_frame
	seed(5)
	var m = new_game(); var s = m.state
	var jp = s.ais[0]
	s.relation(jp).rival_declare_war("test")
	# 1. 1000 fights between fresh Strength 3 units on plains, and Strength 6 against 3
	for pair in [[3, 3], [6, 3]]:
		var dealt := 0; var taken := 0; var kills := 0; var deaths := 0; var moved_in := 0
		for i in 1000:
			var a = s.player.add_unit(Vector2i(2, 2)); a.strength = pair[0]
			var d = jp.add_unit(Vector2i(3, 2)); d.strength = pair[1]
			s.resolve_combat(a, d)
			dealt += Unit.MAX_HP - d.hp; taken += Unit.MAX_HP - a.hp
			if not d in jp.units: kills += 1
			else: jp.remove_unit(d)
			if not a in s.player.units: deaths += 1
			else:
				if a.pos == Vector2i(3, 2): moved_in += 1
				s.player.remove_unit(a)
		print("1. Strength %d attacks %d, 1000 fresh fights: deals %.1f, takes %.1f on average; defender killed %d, attacker killed %d, attacker moved in %d (only when the defender died)" % [pair[0], pair[1], dealt / 1000.0, taken / 1000.0, kills, deaths, moved_in])
	# 2. wounded units fight weaker
	var w = s.player.add_unit(Vector2i(2, 2))
	var shown := []
	for hp in [10, 7, 4, 1]:
		w.hp = hp; shown.append("%d HP -> %d" % [hp, w.fighting_strength()])
	print("2. a Strength 3 unit fights at: %s" % ", ".join(shown))
	s.player.remove_unit(w)
	# 3. healing
	var home = s.player.units[0]; home.hp = 3
	var away = s.player.add_unit(Vector2i(10, 6)); away.hp = 3
	var mover = s.player.add_unit(Vector2i(11, 6)); mover.hp = 3
	s.player_unit_act(mover, Vector2i(12, 6))
	H.answer_choices(s); s.end_turn()
	if s.has_pending_offer(): s.pending_relation().answer(false)
	print("3. one turn: resting in your land 3 -> %d (expect %d), resting outside 3 -> %d (expect %d), after moving 3 -> %d (expect 3)" % [home.hp, 3 + GameState.HEAL_HOME, away.hp, 3 + GameState.HEAL_REST, mover.hp])
	# 4. a badly hurt AI unit rests instead of attacking
	var hurt = jp.units[0]; hurt.hp = GameState.AI_REST_HP; hurt.pos = Vector2i(9, 2)
	var bait = s.player.add_unit(Vector2i(10, 2))
	var attacked := false
	for i in 20:
		hurt.moves = 1; bait.hp = Unit.MAX_HP; hurt.hp = GameState.AI_REST_HP
		s.messages.clear(); s.ai_take_turn(jp)
		if s.messages.any(func(x): return x.begins_with("Japanese attacked")): attacked = true
	print("4. a Japanese unit at %d HP next to yours (at war), 20 AI turns: attacked=%s (expect false)" % [GameState.AI_REST_HP, attacked])
	m.queue_free()

	var n_games: int = H.games(300)
	var bad := {}; var ends := {}; var fights := 0.0; var deaths := 0.0
	for g in n_games:
		m = load("res://main.tscn").instantiate()
		root.add_child(m)
		s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		while not s.game_over:
			H.answer_choices(s)
			if s.gold_change(s.player) >= GameState.ARMY_GOLD: s.player_build_unit()
			s.messages.clear()
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(randf() < 0.5)
			for msg in s.messages:
				if " attacked " in msg and "dealt" in msg:
					fights += 1
					if "destroyed" in msg: deaths += 1
			for f in s.factions:
				for u in f.units:
					if u.hp <= 0 or u.hp > Unit.MAX_HP: bad["HP out of range"] = bad.get("HP out of range", 0) + 1
			if s.turn > 40: bad["game never ended"] = 1; break
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	print("Part 2, %d games: %.1f unit fights a game, %.0f%% of fights killed a unit" % [n_games, fights / n_games, 100.0 * deaths / maxf(1, fights)])
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
