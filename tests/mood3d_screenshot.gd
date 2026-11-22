extends SceneTree
const H := preload("res://tests/helpers.gd")
# The 3D view's dark mood, lighting, water plane and fog memory on a real game:
# turn 1 just after the Landing (mood3d_turn1*.png), then after turn 15 with
# Sköll loose and ash on the map (mood3d_turn16*.png). The player only explores
# by revealing hexes around the city (as if its scouts had been out).
# Needs a window (not --headless). Saved to $S.
var m
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OS.get_environment("S"), file])
func views(prefix: String) -> void:
	var s = m.state
	var v = m.view_3d
	var last: Vector3 = v.cell_position(Vector2i(HexMap.COLS - 1, HexMap.ROWS - 1))
	v.cam_target = Vector3(last.x * 0.5 + 3.0, 0.0, last.z * 0.5); v.cam_distance = 22.0; v.place_camera()
	for i in 10: await process_frame
	await shot("%s.png" % prefix)
	v.cam_target = v.cell_position(s.player.city_pos); v.cam_distance = 9.0; v.place_camera()
	for i in 5: await process_frame
	await shot("%s_city.png" % prefix)
	# the nearest water hex the player has seen
	var best := HexMap.NO_CELL
	for c in s.terrain:
		if s.terrain[c] == Terrain.Type.WATER and s.player_has_explored(c):
			if best == HexMap.NO_CELL or HexMap.hex_distance(c, s.player.city_pos) < HexMap.hex_distance(best, s.player.city_pos):
				best = c
	if best != HexMap.NO_CELL:
		v.cam_target = v.cell_position(best); v.cam_distance = 7.0; v.place_camera()
		for i in 5: await process_frame
		await shot("%s_water.png" % prefix)
func _initialize() -> void:
	seed(11)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	s.start_landing()
	var spots: Array = H.landing_spots(s)
	spots.sort_custom(func(a, b): return absi(a.x - 7) + absi(a.y - 5) < absi(b.x - 7) + absi(b.y - 5))
	s.try_land(spots[0])
	s.update_sight(); m.refresh()
	m.toggle_3d()
	for i in 30: await process_frame
	await views("mood3d_turn1")
	while s.turn <= 15 and not s.game_over:
		H.answer_choices(s)
		s.end_turn()
		if s.has_pending_offer(): s.pending_relation().answer(false)
		H.answer_choices(s)
		s.reveal_area(s.player, s.player.city_pos, mini(2 + int(s.turn / 3.0), 7))
		s.update_sight()
	print("turn %d, ash %d, Sköll active %s, known rifts %d" % [s.turn, s.ash.size(), s.skoll.active, s.player.known_rifts.size()])
	m.refresh()
	for i in 30: await process_frame
	await views("mood3d_turn16")
	quit()
