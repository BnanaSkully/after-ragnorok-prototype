extends SceneTree
# The 3D view's tiles (tile_kit_3d.gd) on a normal random map: plains, forest,
# hills, mountains, water, some ash, your territory and fog of war
# (tiles3d.png), and a close-up (tiles3d_close.png). Needs a window (not --headless). Saved to $S.
var m
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OS.get_environment("S"), file])
func _initialize() -> void:
	seed(7)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	s.start_landing()
	var landed := false
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			if not landed and s.can_land_at(Vector2i(col, row)) and absi(col - 7) + absi(row - 5) < 4:
				landed = s.try_land(Vector2i(col, row))
	s.turn = 16
	s.reveal_area(s.player, Vector2i(7, 5), 6)
	var ash := 0
	for c in s.terrain:
		if ash < 4 and c.x == 0:
			s.ash[c] = true; ash += 1
	# a rift and ruins in sight, to show their models
	var near: Vector2i = s.player.city_pos + Vector2i(2, -1)
	s.player.known_rifts[near] = true
	s.player.add_unit(s.player.city_pos + Vector2i(-1, 1))
	for r in s.ruins:
		if r["cell"].x >= 5 and r["cell"].x <= 10:
			s.reveal_area(s.player, r["cell"], 1)
	s.update_sight(); m.refresh()
	m.toggle_3d()
	for i in 30: await process_frame
	await shot("tiles3d.png")
	var v = m.view_3d
	v.cam_distance = 9.0; v.place_camera()
	for i in 5: await process_frame
	await shot("tiles3d_close.png")
	v.cam_target = v.cell_position(s.player.city_pos); v.cam_distance = 6.0; v.place_camera()
	for i in 5: await process_frame
	await shot("tiles3d_city.png")
	v.cam_target = v.cell_position(near); v.place_camera()
	for i in 5: await process_frame
	await shot("tiles3d_rift.png")
	for land in [Terrain.Type.MOUNTAINS, Terrain.Type.WATER, Terrain.Type.FOREST]:
		for c in s.terrain:
			if s.terrain[c] == land and s.player_has_explored(c):
				v.cam_target = v.cell_position(c); v.cam_distance = 6.0; v.place_camera()
				break
		for i in 5: await process_frame
		await shot("tiles3d_%s.png" % Terrain.NAMES[land].to_lower())
	quit()
