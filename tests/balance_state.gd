extends SceneTree
const H := preload("res://tests/helpers.gd")
func _initialize() -> void:
	await process_frame
	seed(4242)
	for holder_name in ["player", "rival"]:
		var st := {"survived": 0, "fell": 0, "found early": 0, "first: player": 0, "first: rival": 0}
		for g in 500:
			var m = load("res://main.tscn").instantiate()
			root.add_child(m)
			var s = m.state
			for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
			s.start_landing()
			s.daughter.holder = s.player if holder_name == "player" else s.ais[g % 3]
			var spots = H.landing_spots(s)
			s.try_land(spots[(g * 7) % spots.size()])
			var first := ""
			while not s.game_over:
				H.answer_choices(s)
				if s.player.industry >= 10 and s.player.walls < 1: s.player_build_walls()
				elif s.player.units.size() < 3: s.player_build_unit()
				s.end_turn()
				if s.has_pending_offer(): s.pending_relation().answer(randf() < 0.5)
				for msg in s.messages:
					if first == "" and ("Norse's city (defence" in msg or msg.begins_with("Sköll attacked Norse's city")): first = "player"
					if first == "" and "city (defence" in msg and not "Norse's city" in msg: first = "rival"
			if first != "": st["first: " + first] += 1
			if s.end_title == "You survived until the Doom": st["survived"] += 1
			elif s.end_title == "Your city has fallen": st["fell"] += 1
			else: st["found early"] += 1
			m.queue_free()
		print("Daughter with %s (500 games): %s" % [holder_name, st])
	quit()
