extends SceneTree
const H := preload("res://tests/helpers.gd")
func _initialize() -> void:
	seed(15)
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	s.start_landing()
	print("during the Landing: far corner visible=%s (expect false: the ark sees the land, not what's on it)" % s.player_can_see(Vector2i(14, 10)))
	s.try_land(Vector2i(6, 4))
	var u = s.player.units[0]
	u.pos = Vector2i(9, 6)
	print("after landing: 3 from city %s, 4 from city %s, 2 from unit %s, 3 from unit and far from city %s, the Greek city %s" % [s.player_can_see(Vector2i(9, 4)), s.player_can_see(Vector2i(10, 4)), s.player_can_see(Vector2i(10, 8)), s.player_can_see(Vector2i(12, 6)), s.player_can_see(s.ais[2].city_pos)])
	u.pos = Vector2i(6, 4)
	while s.turn < 15:
		H.answer_choices(s)
		s.end_turn()
		if s.has_pending_offer(): s.pending_relation().answer(false)
	m.refresh()
	var shown := 0; var hidden := 0
	for f in s.ais:
		for au in f.units:
			if s.player_can_see(au.pos): shown += 1
			else: hidden += 1
	print("turn %d: AI units you can see %d, hidden by fog %d; Sköll at %s visible=%s" % [s.turn, shown, hidden, s.skoll.pos, s.player_can_see(s.skoll.pos)])
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("%s/fog.png" % OS.get_environment("S"))
	quit()
