extends SceneTree
const H := preload("res://tests/helpers.gd")
const TurnEvents := preload("res://turn_events.gd")

# A player who chases Sunna's rising (not run by run_all.sh): the same full
# 40-turn games as midgame_test.gd Part 2, but the player grants every Sunna
# request it can afford, keeps an oath going while it shelters her, and accepts
# oaths, peace and open borders (refuses everything else). Nathan's target for
# Dawn with this kind of player: about 15%.

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func play_turn(s) -> void:
	H.answer_choices(s)
	s.end_turn()
	if s.has_pending_offer(): s.pending_relation().answer(false)

func _initialize() -> void:
	var m; var s
	# Part 2: full games
	var n_games: int = H.games(300)
	var ends := {}; var bad := {}
	var st := {"returns": 0.0, "ash": 0.0, "rose": 0.0, "rose with you": 0.0, "swallowed": 0.0, "requests": 0.0, "game length": 0.0, "factions devoured": 0.0, "you hold her on turn 10": 0.0, "AIs demand her": 0.0, "wars on you over her": 0.0, "AI wars over her": 0.0, "carried off by a conquest": 0.0, "blocked only by Sköll never attacking (you)": 0.0, "blocked only by Sköll never attacking (anyone)": 0.0, "you had Favour 8+ on turn 20+ but no recognition": 0.0}
	for g in n_games:
		m = load("res://main.tscn").instantiate()
		root.add_child(m)
		s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		var requests := 0
		var only_held := {}; var no_recognition := false # Faction -> true: on a turn from RISE_TURN, only the "held against Sköll" condition was missing
		while not s.game_over:
			for c in s.pending_choices:
				if c["title"].begins_with("SUNNA"): requests += 1
			while s.has_pending_choice():
				var opts: Array = s.pending_choices[0]["options"]
				var pick: int = -1
				if s.pending_choices[0]["title"].begins_with("SUNNA") and s.can_afford(opts[0]["effects"]): pick = 0
				if pick < 0:
					for i in opts.size():
						if s.can_afford(opts[i]["effects"]): pick = i; break
				s.answer_choice(pick)
			var allied: bool = s.relations.any(func(r): return r.pact_active())
			if not allied and s.daughter.shelters_with(s.player):
				var best = null
				for r in s.relations:
					if r.can_propose() and (best == null or r.accept_chance() > best.accept_chance()): best = r
				if best != null: best.propose_pact()
			if s.player.walls < 2 and s.player.industry >= GameState.WALL_COST and s.turn >= 8: s.player_build_walls()
			elif s.gold_change(s.player) >= GameState.ARMY_GOLD: s.player_build_unit()
			for key in GameState.Buildings.LIST: s.player_build_building(key)
			s.end_turn()
			if s.turn == 10 and s.daughter.shelters_with(s.player): st["you hold her on turn 10"] += 1
			var h = s.daughter.holder
			if s.turn >= GameState.RISE_TURN and s.daughter.state == SunDaughter.State.SHELTERED and h != null and h.is_alive():
				var miss = s.rise_missing(h)
				if miss.size() == 1 and "Sköll" in miss[0]: only_held[h] = true
				if h == s.player and h.favour >= SunDaughter.RISE_FAVOUR and not s.recognised(h): no_recognition = true
			for msg in s.messages:
				if "their lost sun)" in msg: st["wars on you over her" if "on you" in msg else "AI wars over her"] += 1
				if "carried" in msg and "off from" in msg: st["carried off by a conquest"] += 1
			if s.has_pending_offer():
				if s.pending_relation().pending.get("type") == "claim": st["AIs demand her"] += 1
				var ty = s.pending_relation().pending.get("type")
				s.pending_relation().answer(ty in ["oath", "peace", "borders"])
			for c in s.ash:
				if s.next_to_a_city(c): bad["ash next to a city"] = 1
				if s.outpost_owner(c) != null: bad["outpost on ash"] = 1
			if s.skoll.active and not HexMap.in_bounds(s.skoll.pos): bad["Sköll active off the map"] = 1
			if s.turn > GameState.END_TURN: bad["game ran past the end"] = 1; break
		if not s.daughter.is_risen():
			st["blocked only by Sköll never attacking (you)"] += int(only_held.has(s.player))
			st["blocked only by Sköll never attacking (anyone)"] += int(not only_held.is_empty())
			st["you had Favour 8+ on turn 20+ but no recognition"] += int(no_recognition)
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		st["returns"] += s.skoll.returns; st["ash"] += s.ash.size(); st["game length"] += s.turn
		st["rose"] += int(s.daughter.is_risen()); st["rose with you"] += int(s.daughter.risen_with(s.player))
		st["swallowed"] += int(s.daughter.is_swallowed()); st["requests"] += requests; st["factions devoured"] += s.devoured.size()
		m.queue_free()
	print("Part 2, %d games, per game: %s" % [n_games, ", ".join(st.keys().map(func(k): return "%s %.2f" % [k, st[k] / n_games]))])
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
